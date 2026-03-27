"""
nutri-ai-mcp – FastAPI application entry point.

Starts:
  • FastAPI HTTP inference API  (for direct REST calls / health checks)
  • MCP Server                  (for tool invocation by nutri-agent)
"""

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import inference, health
from app.mcp_server import mcp_app

# ── FastAPI application ────────────────────────────────────────────────────
app = FastAPI(
    title="Nutri-AI MCP Service",
    description=(
        "Swin Transformer food instance-segmentation service. "
        "Exposes a REST API and an MCP tool interface for nutri-agent."
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


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
