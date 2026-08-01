"""
Node: publish_result

Publishes the completed analysis report back to RabbitMQ so that
nutri-business can store the result and notify the user.
"""

from __future__ import annotations

import json
import logging
import time
from typing import TYPE_CHECKING

import aio_pika
from pydantic_settings import BaseSettings

from app.trace_client import record_trace_event

if TYPE_CHECKING:
    from app.graph import AgentState
else:
    AgentState = dict

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
    workflow_trace = list(state.get("workflow_trace") or [])

    result_payload = {
        "taskId": task_id,
        "userId": state["user_id"],
        "mealType": state.get("meal_type"),
        "adviceReport": state.get("advice_report"),
        "segmentationResult": state.get("segmentation_result"),
        "workflowMode": state.get("workflow_mode"),
        "detectedLabels": state.get("detected_labels") or [],
        "workflowTrace": workflow_trace,
        "error": state.get("error")
                 or (state.get("segmentation_result") or {}).get("error"),
        "status": "COMPLETED" if state.get("advice_report") else "FAILED",
    }

    logger.info("Publishing result for task_id=%s to routing_key=%s", task_id, routing_key)
    started_at = time.perf_counter()
    await record_trace_event(
        task_id,
        "RESULT_QUEUE",
        "RUNNING",
        "正在发布分析结果",
        service="rabbitmq",
    )

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
        await record_trace_event(
            task_id,
            "RESULT_QUEUE",
            "COMPLETED",
            "分析结果已发布到返回队列",
            service="rabbitmq",
            duration_ms=(time.perf_counter() - started_at) * 1000,
        )
        workflow_trace.append(f"publish_result: published to {routing_key}")
    except Exception as exc:
        logger.error("Failed to publish result for task_id=%s: %s", task_id, exc)
        await record_trace_event(
            task_id,
            "RESULT_QUEUE",
            "FAILED",
            "分析结果发布失败",
            service="rabbitmq",
            duration_ms=(time.perf_counter() - started_at) * 1000,
        )
        workflow_trace.append("publish_result: publish failed")
        return {"error": f"Result publish failed: {exc}", "workflow_trace": workflow_trace}

    return {"workflow_trace": workflow_trace}
