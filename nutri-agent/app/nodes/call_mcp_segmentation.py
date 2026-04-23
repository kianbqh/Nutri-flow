"""
Node: call_mcp_segmentation

Calls the nutri-ai-mcp MCP server's ``segment_food_image`` tool to obtain
food-instance segmentation results.
"""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING

import httpx
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState
else:
    AgentState = dict

logger = logging.getLogger(__name__)


class McpSettings(BaseSettings):
    mcp_server_url: str = "http://localhost:8000"

    class Config:
        env_prefix = "NUTRI_"


_settings = McpSettings()


async def call_mcp_segmentation(state: "AgentState") -> dict:
    """
    Invoke the MCP ``segment_food_image`` tool on nutri-ai-mcp.

    Uses a direct HTTP call to the MCP SSE endpoint; a full MCP client SDK
    can replace this for richer protocol handling.
    """
    task_id: str = state["task_id"]
    image_url: str = state["image_url"]
    user_context: dict = state.get("user_context") or {}
    confidence_threshold: float = user_context.get("confidence_threshold", 0.5)
    workflow_trace = list(state.get("workflow_trace") or [])

    logger.info("Calling MCP segment_food_image for task_id=%s", task_id)

    payload = {
        "image_url": image_url,
        "task_id": task_id,
        "confidence_threshold": confidence_threshold,
    }

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{_settings.mcp_server_url}/v1/segment",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            resp.raise_for_status()
            content = resp.json()
            segmentation_result = {
                "task_id": content.get("task_id", task_id),
                "detected_items": content.get("detected_items", []),
                "inference_time_ms": content.get("inference_time_ms", 0.0),
                "total_calories_kcal": content.get("total_calories_kcal", 0.0),
                "model_version": content.get("model_version", "unknown"),
            }
    except Exception as exc:
        logger.error("MCP segmentation call failed: %s", exc)
        segmentation_result = {"error": str(exc), "detected_items": []}

    labels: list[str] = []
    for item in segmentation_result.get("detected_items", []):
        label = (
            item.get("label")
            or item.get("class_name")
            or item.get("display_name")
            or ""
        )
        if label:
            labels.append(str(label))

    workflow_mode = "FULL" if labels else "CALORIE_ONLY"
    if labels:
        workflow_trace.append(
            f"call_mcp_segmentation: detected {len(labels)} labels, continue with FULL workflow"
        )
    else:
        workflow_trace.append(
            "call_mcp_segmentation: no labels detected or segmentation failed, switch to CALORIE_ONLY workflow"
        )

    return {
        "segmentation_result": segmentation_result,
        "detected_labels": labels,
        "workflow_mode": workflow_mode,
        "workflow_trace": workflow_trace,
    }
