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

logger = logging.getLogger(__name__)


class McpSettings(BaseSettings):
    mcp_server_url: str = "http://localhost:8000/mcp"

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

    logger.info("Calling MCP segment_food_image for task_id=%s", task_id)

    payload = {
        "name": "segment_food_image",
        "arguments": {
            "image_url": image_url,
            "task_id": task_id,
            "confidence_threshold": confidence_threshold,
        },
    }

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{_settings.mcp_server_url}/call",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            resp.raise_for_status()
            content = resp.json()
            # MCP response: list of TextContent objects
            text_result = content[0]["text"] if content else "{}"
            segmentation_result = json.loads(text_result)
    except Exception as exc:
        logger.error("MCP segmentation call failed: %s", exc)
        segmentation_result = {"error": str(exc), "detected_items": []}

    return {"segmentation_result": segmentation_result}
