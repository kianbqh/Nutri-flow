"""
Async RabbitMQ consumer.

Listens on the food-analysis task queue and triggers the LangGraph
dietary-advice pipeline for each incoming message.

Dead-letter handling
────────────────────
Messages that fail more than MAX_RETRIES times are rejected (not requeued)
so RabbitMQ routes them to the dead-letter exchange/queue if one is declared.
The retry count is tracked in the message header ``x-nutri-retry-count``.

Important: RabbitMQ does NOT auto-increment headers on requeue.
To persist the counter we ACK the original message and re-publish a new
message to the same queue carrying the incremented header value.
"""

from __future__ import annotations

import asyncio
import json
import logging

import aio_pika
from aio_pika.abc import AbstractIncomingMessage
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.graph import nutri_graph, AgentState

logger = logging.getLogger(__name__)

MAX_RETRIES = 3


class ConsumerSettings(BaseSettings):
    rabbitmq_url: str = "amqp://nutri_mq:nutri_mq_pass@localhost:5672/"
    mq_task_queue: str = "nutri.food.analysis.task"
    mq_dead_letter_exchange: str = "nutri.food.analysis.dlx"
    mq_result_exchange: str = "nutri.food.analysis.exchange"
    mq_default_result_routing_key: str = "nutri.food.analysis.result"
    mq_prefetch_count: int = 1
    agent_task_timeout_sec: int = 300

    model_config = SettingsConfigDict(
        env_prefix="NUTRI_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


_settings = ConsumerSettings()


async def _publish_failed_result(
    channel: aio_pika.abc.AbstractChannel,
    body: dict,
    error_message: str,
) -> None:
    """Publish a terminal FAILED result so business can stop polling quickly."""
    routing_key = body.get("callbackRoutingKey") or _settings.mq_default_result_routing_key
    payload = {
        "taskId": body.get("taskId", "unknown"),
        "userId": body.get("userId", ""),
        "mealType": body.get("mealType"),
        "adviceReport": None,
        "segmentationResult": None,
        "workflowMode": "CALORIE_ONLY",
        "detectedLabels": [],
        "workflowTrace": ["mq_consumer: terminal failure published from agent"],
        "error": error_message,
        "status": "FAILED",
    }

    exchange = await channel.get_exchange(_settings.mq_result_exchange)
    await exchange.publish(
        aio_pika.Message(
            body=json.dumps(payload, ensure_ascii=False).encode(),
            content_type="application/json",
            delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
        ),
        routing_key=routing_key,
    )


async def _handle_message(
    message: AbstractIncomingMessage,
    channel: aio_pika.abc.AbstractChannel,
) -> None:
    """Process a single food-analysis task message.

    Retry strategy
    ──────────────
    * On failure, ACK the original message and publish a new copy with
      ``x-nutri-retry-count`` incremented by 1.  This guarantees the
      counter actually persists across deliveries (``reject(requeue=True)``
      would leave the header unchanged, causing an infinite loop).
    * After MAX_RETRIES attempts the message is dead-lettered via
      ``reject(requeue=False)``.
    """
    headers: dict = dict(message.headers or {})
    retry_count: int = int(headers.get("x-nutri-retry-count", 0))

    # Parse body
    try:
        body = json.loads(message.body.decode())
    except json.JSONDecodeError as exc:
        logger.error("Invalid JSON in message, rejecting without requeue: %s", exc)
        await message.reject(requeue=False)
        return

    task_id: str = body.get("taskId", "unknown")
    logger.info(
        "Received analysis task: task_id=%s (attempt %d/%d)",
        task_id, retry_count + 1, MAX_RETRIES,
    )

    initial_state: AgentState = {
        "task_id": task_id,
        "user_id": body.get("userId", ""),
        "image_url": body.get("imageUrl", ""),
        "image_base64": body.get("analysisImageBase64"),
        "meal_type": body.get("mealType", ""),
        "callback_routing_key": body.get("callbackRoutingKey"),
        "user_context": body.get("userContext"),
        "user_memory": None,
        "segmentation_result": None,
        "rag_context": None,
        "advice_report": None,
        "error": None,
    }

    try:
        final_state = await asyncio.wait_for(
            nutri_graph.ainvoke(initial_state),
            timeout=_settings.agent_task_timeout_sec,
        )
        logger.info(
            "Graph completed for task_id=%s status=%s",
            task_id,
            "OK" if final_state.get("advice_report") else "NO_ADVICE",
        )
        await message.ack()

    except Exception as exc:
        logger.exception("Graph execution failed for task_id=%s: %s", task_id, exc)

        if retry_count + 1 >= MAX_RETRIES:
            logger.error(
                "task_id=%s exceeded max retries (%d), dead-lettering",
                task_id, MAX_RETRIES,
            )
            try:
                await _publish_failed_result(
                    channel=channel,
                    body=body,
                    error_message=f"Agent failed after retries: {exc}",
                )
                await message.ack()
            except Exception as pub_exc:
                logger.exception(
                    "Failed to publish terminal FAILED result for task_id=%s: %s",
                    task_id,
                    pub_exc,
                )
                await message.reject(requeue=False)
        else:
            # ACK the original so it leaves the queue, then publish a fresh
            # copy with the incremented retry counter in the headers.
            new_retry = retry_count + 1
            logger.warning("Scheduling retry %d for task_id=%s", new_retry, task_id)
            await message.ack()
            await channel.default_exchange.publish(
                aio_pika.Message(
                    body=message.body,
                    headers={**headers, "x-nutri-retry-count": new_retry},
                    delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                    content_type="application/json",
                ),
                routing_key=_settings.mq_task_queue,
            )


async def start_consumer() -> None:
    """Connect to RabbitMQ and start consuming the task queue indefinitely."""
    logger.info("Connecting to RabbitMQ: %s", _settings.rabbitmq_url)

    connection = await aio_pika.connect_robust(
        _settings.rabbitmq_url,
        reconnect_interval=5,
    )

    async with connection:
        channel = await connection.channel()
        await channel.set_qos(prefetch_count=_settings.mq_prefetch_count)

        queue = await channel.declare_queue(
            _settings.mq_task_queue,
            durable=True,
        )

        logger.info("Waiting for messages on queue: %s", _settings.mq_task_queue)
        async with queue.iterator() as queue_iter:
            async for message in queue_iter:
                await _handle_message(message, channel)

