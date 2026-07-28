"""
MCP Server for nutri-ai-mcp.

Exposes the food-segmentation capability as an MCP tool so that
nutri-agent can call it via the Model Context Protocol (MCP).

Transport: SSE (Server-Sent Events) – the Starlette sub-application is
mounted at /mcp in main.py.
"""

from __future__ import annotations

import base64
import io
import json
import logging

import httpx
import numpy as np
from PIL import Image
from starlette.applications import Starlette
from starlette.routing import Mount, Route

from mcp.server import Server
from mcp.server.sse import SseServerTransport
from mcp.types import Tool, TextContent

from app.inference import run_inference

logger = logging.getLogger(__name__)

# ── MCP server instance ───────────────────────────────────────────────────────
server = Server("nutri-ai-mcp")

# ── Tool definitions ──────────────────────────────────────────────────────────
SEGMENT_FOOD_TOOL = Tool(
    name="segment_food_image",
    description=(
        "Analyse a meal image using Swin Transformer + BiFPN + Coordinate Attention. "
        "Returns detected food items, bounding boxes, segmentation masks (RLE), "
        "estimated portion weights, and per-item nutrition estimates."
    ),
    inputSchema={
        "type": "object",
        "required": ["task_id"],
        "properties": {
            "image_url": {
                "type": "string",
                "description": "Pre-signed OSS/MinIO URL of the meal image.",
            },
            "image_base64": {
                "type": "string",
                "description": "Optional base64-encoded meal image. Preferred for local async tasks.",
            },
            "task_id": {
                "type": "string",
                "description": "UUID of the originating analysis task.",
            },
            "confidence_threshold": {
                "type": "number",
                "default": 0.5,
                "description": "Minimum confidence score (0–1) for returned detections.",
            },
        },
        "anyOf": [
            {"required": ["image_url"]},
            {"required": ["image_base64"]},
        ],
    },
)


@server.list_tools()
async def list_tools() -> list[Tool]:
    return [SEGMENT_FOOD_TOOL]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if name != "segment_food_image":
        raise ValueError(f"Unknown tool: {name}")

    image_url: str = str(arguments.get("image_url") or "")
    image_base64: str = str(arguments.get("image_base64") or "")
    task_id: str = arguments["task_id"]
    confidence_threshold: float = float(arguments.get("confidence_threshold", 0.5))

    logger.info("MCP tool call: segment_food_image task_id=%s", task_id)

    if image_base64:
        image_bytes = base64.b64decode(image_base64)
    elif image_url:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(image_url)
            resp.raise_for_status()
            image_bytes = resp.content
    else:
        raise ValueError("Either image_url or image_base64 is required")

    pil_img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    image_array = np.array(pil_img)

    detections, inference_ms, preview_b64, model_version = run_inference(image_array, confidence_threshold)
    total_calories = sum(
        float((item.get("nutrition") or {}).get("calories_kcal") or 0.0)
        for item in detections
    )

    result = {
        "task_id": task_id,
        "detected_items": detections,
        "inference_time_ms": float(round(inference_ms, 2)),
        "total_calories_kcal": round(total_calories, 1),
        "segmentation_preview_png_base64": preview_b64,
        "model_version": model_version,
    }

    return [TextContent(type="text", text=json.dumps(result, ensure_ascii=False))]


# ── ASGI sub-application (SSE transport) ─────────────────────────────────────
sse_transport = SseServerTransport("/mcp/messages/")


async def _handle_sse(scope, receive, send):
    async with sse_transport.connect_sse(scope, receive, send) as streams:
        await server.run(
            streams[0],
            streams[1],
            server.create_initialization_options(),
        )


mcp_app = Starlette(
    routes=[
        Route("/sse", endpoint=_handle_sse),
        Mount("/messages/", app=sse_transport.handle_post_message),
    ]
)
