"""
nutri-ai-mcp – FastAPI application entry point.

Starts:
  • FastAPI HTTP inference API  (production agent path / health checks)
  • MCP Server                  (SSE tool surface for protocol experiments)
"""

import logging
import os

import numpy as np
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.inference import run_inference
from app.routers import inference, health
from app.mcp_server import mcp_app

logger = logging.getLogger(__name__)

# ── FastAPI application ────────────────────────────────────────────────────
app = FastAPI(
    title="Nutri-AI MCP Service",
    description=(
        "Swin Transformer food instance-segmentation service. "
        "Exposes a REST API for the agent and an MCP tool interface for experiments."
    ),
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, tags=["Health"])
app.include_router(inference.router, prefix="/v1", tags=["Inference"])

# Mount MCP server at /mcp (SSE transport)
app.mount("/mcp", mcp_app)


@app.on_event("startup")
def warmup_segmentation_model() -> None:
    try:
        dummy_image = np.zeros((64, 64, 3), dtype=np.uint8)
        _, _, _, model_version = run_inference(dummy_image, confidence_threshold=0.99)
        logger.info("Segmentation model warmup complete (%s)", model_version)
    except Exception as exc:
        logger.exception("Segmentation model warmup failed: %s", exc)
        if os.getenv("NUTRI_REQUIRE_CHECKPOINT", "false").strip().lower() in {
            "1", "true", "yes", "on",
        }:
            raise


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
