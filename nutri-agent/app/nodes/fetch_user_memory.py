"""
Node: fetch_user_memory

Retrieves the user's long-term dietary preferences and history from ChromaDB,
providing context for personalised meal advice.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

import chromadb
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState

logger = logging.getLogger(__name__)


class ChromaSettings(BaseSettings):
    chroma_host: str = "localhost"
    chroma_port: int = 8100
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

    Returns a partial state update with ``user_memory`` populated.
    """
    user_id: str = state["user_id"]
    logger.info("Fetching user memory for user_id=%s", user_id)

    try:
        client = _get_chroma_client()
        collection = client.get_or_create_collection(_settings.chroma_user_memory_collection)
        results = collection.query(
            query_texts=[f"user dietary preferences and history for {user_id}"],
            n_results=5,
            where={"user_id": user_id},
        )
        documents: list[str] = results.get("documents", [[]])[0]
        user_memory = "\n".join(documents) if documents else "No previous history found."
        logger.debug("Retrieved %d memory documents for user_id=%s", len(documents), user_id)
    except Exception as exc:
        logger.warning("Failed to fetch user memory: %s", exc)
        user_memory = "Memory unavailable."

    return {"user_memory": user_memory}
