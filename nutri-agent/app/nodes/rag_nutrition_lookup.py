"""
Node: rag_nutrition_lookup

Retrieves relevant nutritional knowledge from ChromaDB based on the detected
food items, providing grounding context for the LLM advice generation.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, List

import chromadb
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState

logger = logging.getLogger(__name__)


class ChromaRagSettings(BaseSettings):
    chroma_host: str = "localhost"
    chroma_port: int = 8100
    chroma_nutrition_collection: str = "nutrition_knowledge"

    class Config:
        env_prefix = "NUTRI_"


_settings = ChromaRagSettings()
_chroma_client: chromadb.HttpClient | None = None


def _get_chroma_client() -> chromadb.HttpClient:
    global _chroma_client
    if _chroma_client is None:
        _chroma_client = chromadb.HttpClient(
            host=_settings.chroma_host,
            port=_settings.chroma_port,
        )
    return _chroma_client


async def rag_nutrition_lookup(state: "AgentState") -> dict:
    """
    Query the nutrition knowledge base for each detected food item.

    Combines retrieved passages into a single context string for the LLM node.
    """
    segmentation_result: dict = state.get("segmentation_result") or {}
    detected_items: List[dict] = segmentation_result.get("detected_items", [])

    if not detected_items:
        logger.info("No detected items – skipping RAG lookup")
        return {"rag_context": "No food items detected in the image."}

    # Build a combined query from detected labels
    labels: List[str] = [item["label"] for item in detected_items if item.get("label")]
    query = "Nutritional information and health benefits of: " + ", ".join(labels)

    logger.info("RAG lookup for foods: %s", labels)

    try:
        client = _get_chroma_client()
        collection = client.get_or_create_collection(_settings.chroma_nutrition_collection)
        results = collection.query(query_texts=[query], n_results=5)
        documents: List[str] = results.get("documents", [[]])[0]
        rag_context = "\n\n".join(documents) if documents else "No nutritional data found."
    except Exception as exc:
        logger.warning("RAG lookup failed: %s", exc)
        rag_context = "Nutritional knowledge base unavailable."

    return {"rag_context": rag_context}
