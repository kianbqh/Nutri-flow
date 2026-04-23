"""
Node: rag_nutrition_lookup

Retrieves relevant nutritional knowledge from ChromaDB based on the detected
food items, providing grounding context for the LLM advice generation.
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


class ChromaRagSettings(BaseSettings):
    chroma_host: str = "localhost"
    chroma_port: int = 8100
    chroma_nutrition_collection: str = "nutrition_knowledge"

    class Config:
        env_prefix = "NUTRI_"


_settings = ChromaRagSettings()
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


async def rag_nutrition_lookup(state: "AgentState") -> dict:
    """
    Query the nutrition knowledge base for each detected food item.

    Combines retrieved passages into a single context string for the LLM node.
    """
    labels: List[str] = list(state.get("detected_labels") or [])
    workflow_trace = list(state.get("workflow_trace") or [])

    if not labels:
        logger.info("No detected items – skipping RAG lookup")
        workflow_trace.append("rag_nutrition_lookup: skipped because no labels were detected")
        return {"rag_context": "No food items detected in the image.", "workflow_trace": workflow_trace}

    # Build a combined query from normalized labels
    query = "Nutritional information and health benefits of: " + ", ".join(labels)

    logger.info("RAG lookup for foods: %s", labels)

    try:
        client = _get_chroma_client()
        collection = client.get_or_create_collection(_settings.chroma_nutrition_collection)
        results = collection.query(query_texts=[query], n_results=5)
        documents: List[str] = results.get("documents", [[]])[0]
        rag_context = "\n\n".join(documents) if documents else "No nutritional data found."
        workflow_trace.append(
            f"rag_nutrition_lookup: retrieved {len(documents)} nutrition passages for {len(labels)} labels"
        )
    except Exception as exc:
        logger.warning("RAG lookup failed: %s", exc)
        rag_context = "Nutritional knowledge base unavailable."
        workflow_trace.append("rag_nutrition_lookup: nutritional knowledge base unavailable, continue with fallback context")

    return {"rag_context": rag_context, "workflow_trace": workflow_trace}
