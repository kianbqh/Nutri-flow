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

import json
import logging

import aio_pika
from aio_pika.abc import AbstractIncomingMessage
from pydantic_settings import BaseSettings

from app.graph import nutri_graph, AgentState

logger = logging.getLogger(__name__)

MAX_RETRIES = 3


class ConsumerSettings(BaseSettings):
    rabbitmq_url: str = "amqp://nutri_mq:nutri_mq_pass@localhost:5672/"
    mq_task_queue: str = "nutri.food.analysis.task"
    mq_dead_letter_exchange: str = "nutri.food.analysis.dlx"
    mq_prefetch_count: int = 1

    class Config:
        env_prefix = "NUTRI_"


_settings = ConsumerSettings()


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
        final_state = await nutri_graph.ainvoke(initial_state)
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

