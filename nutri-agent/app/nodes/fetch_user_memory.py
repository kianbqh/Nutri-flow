"""
Node: fetch_user_memory

Retrieves the user's long-term dietary preferences and history from ChromaDB.
Because this node now runs AFTER call_mcp_segmentation, the detected food
labels are available in state and used to build a targeted query – e.g.
"user X history with chicken, broccoli" – making results more relevant than
a generic user-id lookup.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, List

import chromadb
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState

logger = logging.getLogger(__name__)


class ChromaSettings(BaseSettings):
    chroma_host: str = "localhost"  # override with NUTRI_CHROMA_HOST=chroma inside Docker
    chroma_port: int = 8100         # host-mapped port; container-internal port is 8000
    chroma_user_memory_collection: str = "user_memory"

    class Config:
        env_prefix = "NUTRI_"


_settings = ChromaSettings()
_chroma_client: chromadb.HttpClient | None = None


def _get_chroma_client() -> chromadb.HttpClient:
    global _chroma_client
    if _chroma_client is None:
        _chroma_client = chromadb.HttpClient(
            host=_settings.chroma_host,
            port=_settings.chroma_port,
        )
    return _chroma_client


async def fetch_user_memory(state: "AgentState") -> dict:
    """
    Query ChromaDB for the user's stored dietary history and preferences.

    Uses the detected food labels from segmentation_result (populated by the
    preceding call_mcp_segmentation node) to build a context-aware query,
    making the retrieved memories more relevant to the current meal.
    """
    user_id: str = state["user_id"]

    # Build a targeted query from detected food labels when available
    segmentation_result: dict = state.get("segmentation_result") or {}
    detected_items: List[dict] = segmentation_result.get("detected_items", [])
    food_labels: List[str] = [
        item["label"] for item in detected_items if item.get("label")
    ]

    if food_labels:
        query = (
            f"dietary history and preferences for user {user_id} "
            f"regarding foods: {', '.join(food_labels)}"
        )
        logger.info(
            "Fetching user memory for user_id=%s with food context: %s",
            user_id, food_labels,
        )
    else:
        query = f"user dietary preferences and history for {user_id}"
        logger.info("Fetching user memory for user_id=%s (no food context)", user_id)

    try:
        client = _get_chroma_client()
        collection = client.get_or_create_collection(_settings.chroma_user_memory_collection)
        results = collection.query(
            query_texts=[query],
            n_results=5,
            where={"user_id": user_id},
        )
        documents: List[str] = results.get("documents", [[]])[0]
        user_memory = "\n".join(documents) if documents else "No previous history found."
        logger.debug("Retrieved %d memory documents for user_id=%s", len(documents), user_id)
    except Exception as exc:
        logger.warning("Failed to fetch user memory: %s", exc)
        user_memory = "Memory unavailable."

    return {"user_memory": user_memory}
