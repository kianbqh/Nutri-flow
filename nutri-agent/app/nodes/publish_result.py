"""
Node: publish_result

Publishes the completed analysis report back to RabbitMQ so that
nutri-business can store the result and notify the user.
"""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING

import aio_pika
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState

logger = logging.getLogger(__name__)


class MQSettings(BaseSettings):
    rabbitmq_url: str = "amqp://nutri_mq:nutri_mq_pass@localhost:5672/"
    mq_result_exchange: str = "nutri.food.analysis.exchange"

    class Config:
        env_prefix = "NUTRI_"


_settings = MQSettings()


async def publish_result(state: "AgentState") -> dict:
    """
    Publish the analysis report to the callback routing key specified in the
    original task message.
    """
    task_id: str = state["task_id"]
    routing_key: str = state.get("callback_routing_key") or "nutri.food.analysis.result"

    result_payload = {
        "taskId": task_id,
        "userId": state["user_id"],
        "mealType": state.get("meal_type"),
        "adviceReport": state.get("advice_report"),
        "segmentationResult": state.get("segmentation_result"),
        "status": "COMPLETED" if state.get("advice_report") else "FAILED",
    }

    logger.info("Publishing result for task_id=%s to routing_key=%s", task_id, routing_key)

    try:
        connection = await aio_pika.connect_robust(_settings.rabbitmq_url)
        async with connection:
            channel = await connection.channel()
            exchange = await channel.get_exchange(_settings.mq_result_exchange)
            await exchange.publish(
                aio_pika.Message(
                    body=json.dumps(result_payload, ensure_ascii=False).encode(),
                    content_type="application/json",
                    delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                ),
                routing_key=routing_key,
            )
        logger.info("Result published successfully for task_id=%s", task_id)
    except Exception as exc:
        logger.error("Failed to publish result for task_id=%s: %s", task_id, exc)
        return {"error": f"Result publish failed: {exc}"}

    return {}
