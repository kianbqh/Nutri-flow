"""
nutri-agent LangGraph StateGraph.

Graph topology
──────────────
START
  │
  ▼
[fetch_user_memory]  – load user long-term preferences from ChromaDB
  │
  ▼
[call_mcp_segmentation]  – call nutri-ai-mcp via MCP tool to segment the image
  │
  ▼
[rag_nutrition_lookup]  – retrieve relevant nutritional facts from ChromaDB RAG
  │
  ▼
[generate_advice]  – LLM call: synthesise segmentation + RAG + memory → advice
  │
  ▼
[publish_result]  – publish analysis report back to RabbitMQ callback queue
  │
  ▼
END
"""

from __future__ import annotations

from typing import Annotated, TypedDict, List, Optional

from langgraph.graph import StateGraph, START, END

from app.nodes.fetch_user_memory import fetch_user_memory
from app.nodes.call_mcp_segmentation import call_mcp_segmentation
from app.nodes.rag_nutrition_lookup import rag_nutrition_lookup
from app.nodes.generate_advice import generate_advice
from app.nodes.publish_result import publish_result


# ── Agent state ───────────────────────────────────────────────────────────────

class AgentState(TypedDict):
    # ── Inputs ──────────────────────────────────────────────────────────────
    task_id: str
    user_id: str
    image_url: str
    meal_type: str
    callback_routing_key: Optional[str]
    user_context: Optional[dict]

    # ── Intermediate ─────────────────────────────────────────────────────────
    user_memory: Optional[str]           # serialised user preference history
    segmentation_result: Optional[dict]  # raw MCP tool response
    rag_context: Optional[str]           # retrieved nutritional knowledge

    # ── Output ───────────────────────────────────────────────────────────────
    advice_report: Optional[str]         # final LLM-generated advice text
    error: Optional[str]                 # set if any node fails


# ── Graph construction ────────────────────────────────────────────────────────

def build_graph() -> StateGraph:
    """
    Construct and compile the Nutri-Flow dietary-advice StateGraph.

    Returns a compiled graph ready to be invoked with an initial AgentState.
    """
    builder = StateGraph(AgentState)

    # Register nodes
    builder.add_node("fetch_user_memory", fetch_user_memory)
    builder.add_node("call_mcp_segmentation", call_mcp_segmentation)
    builder.add_node("rag_nutrition_lookup", rag_nutrition_lookup)
    builder.add_node("generate_advice", generate_advice)
    builder.add_node("publish_result", publish_result)

    # Define edges (linear pipeline)
    builder.add_edge(START, "fetch_user_memory")
    builder.add_edge("fetch_user_memory", "call_mcp_segmentation")
    builder.add_edge("call_mcp_segmentation", "rag_nutrition_lookup")
    builder.add_edge("rag_nutrition_lookup", "generate_advice")
    builder.add_edge("generate_advice", "publish_result")
    builder.add_edge("publish_result", END)

    return builder.compile()


# Singleton compiled graph
nutri_graph = build_graph()
