"""
Async RabbitMQ consumer.

Listens on the food-analysis task queue and triggers the LangGraph
dietary-advice pipeline for each incoming message.

Dead-letter handling
────────────────────
Messages that fail more than MAX_RETRIES times are rejected (not requeued)
so RabbitMQ routes them to the dead-letter exchange/queue if one is declared.
The retry count is tracked in the message header ``x-nutri-retry-count``.
"""

from __future__ import annotations

import asyncio
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


async def _handle_message(message: AbstractIncomingMessage) -> None:
    """Process a single food-analysis task message.

    On unrecoverable failure the message is rejected (dead-lettered) after
    MAX_RETRIES attempts, preventing infinite redelivery loops.
    """
    # Determine current retry count from message headers
    headers: dict = message.headers or {}
    retry_count: int = int(headers.get("x-nutri-retry-count", 0))

    # Parse body
    try:
        body = json.loads(message.body.decode())
    except json.JSONDecodeError as exc:
        logger.error("Invalid JSON in message, rejecting: %s", exc)
        await message.reject(requeue=False)
        return

    task_id: str = body.get("taskId", "unknown")
    logger.info("Received analysis task: task_id=%s (attempt %d/%d)", task_id, retry_count + 1, MAX_RETRIES)

    initial_state: AgentState = {
        "task_id": task_id,
        "user_id": body.get("userId", ""),
        "image_url": body.get("imageUrl", ""),
        "meal_type": body.get("mealType", ""),
        "callback_routing_key": body.get("callbackRoutingKey"),
        "user_context": body.get("userContext"),
        # Intermediate fields – initialised as None
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
                "task_id=%s exceeded max retries (%d), dead-lettering message",
                task_id,
                MAX_RETRIES,
            )
            await message.reject(requeue=False)
        else:
            # Requeue for retry; increment counter in headers
            logger.warning("Requeueing task_id=%s (retry %d)", task_id, retry_count + 1)
            await message.reject(requeue=True)


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
                await _handle_message(message)
