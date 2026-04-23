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

try:
    import chromadb
except Exception:  # pragma: no cover - optional dependency fallback
    chromadb = None
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState
else:
    AgentState = dict

logger = logging.getLogger(__name__)


class ChromaSettings(BaseSettings):
    chroma_host: str = "localhost"  # override with NUTRI_CHROMA_HOST=chroma inside Docker
    chroma_port: int = 8100         # host-mapped port; container-internal port is 8000
    chroma_user_memory_collection: str = "user_memory"

    class Config:
        env_prefix = "NUTRI_"


_settings = ChromaSettings()
_chroma_client = None


def _get_chroma_client():
    if chromadb is None:
        raise RuntimeError("chromadb is not installed")

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
    workflow_trace = list(state.get("workflow_trace") or [])

    # Build a targeted query from detected food labels when available
    food_labels: List[str] = list(state.get("detected_labels") or [])

    if food_labels:
        query = (
            f"dietary history and preferences for user {user_id} "
            f"regarding foods: {', '.join(food_labels)}"
        )
        logger.info("Fetching user memory for user_id=%s with food context: %s", user_id, food_labels)
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
        workflow_trace.append(
            f"fetch_user_memory: retrieved {len(documents)} memory documents for user_id={user_id}"
        )
    except Exception as exc:
        logger.warning("Failed to fetch user memory: %s", exc)
        user_memory = "Memory unavailable."
        workflow_trace.append("fetch_user_memory: memory unavailable, continue with fallback context")

    return {"user_memory": user_memory, "workflow_trace": workflow_trace}
