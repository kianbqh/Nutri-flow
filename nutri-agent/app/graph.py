"""
nutri-agent LangGraph StateGraph.

Graph topology
──────────────
START
  │
  ▼
[call_mcp_segmentation]  – call nutri-ai-mcp via MCP tool to segment the image
  │
  ▼
[fetch_user_memory]  – query user's long-term preferences using detected food labels
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

Rationale for node order
─────────────────────────
Segmentation runs first so that the detected food labels (e.g. "chicken",
"broccoli") are available as targeted query terms when fetching user memory
and nutritional knowledge.  This makes both retrieval steps more relevant
than querying with only the raw user-id or meal-type.
"""

from __future__ import annotations

from typing import Literal, TypedDict, Optional

from langgraph.graph import StateGraph, START, END

from app.nodes.call_mcp_segmentation import call_mcp_segmentation
from app.nodes.fetch_user_memory import fetch_user_memory
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
    segmentation_result: Optional[dict]  # raw MCP tool response (populated first)
    detected_labels: Optional[list[str]] # normalized labels extracted from segmentation
    workflow_mode: Optional[Literal["FULL", "CALORIE_ONLY"]]
    workflow_trace: Optional[list[str]]  # human-readable decision path for debugging and UI display
    user_memory: Optional[str]           # serialised user preference history
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
    builder.add_node("call_mcp_segmentation", call_mcp_segmentation)
    builder.add_node("fetch_user_memory", fetch_user_memory)
    builder.add_node("rag_nutrition_lookup", rag_nutrition_lookup)
    builder.add_node("generate_advice", generate_advice)
    builder.add_node("publish_result", publish_result)

    # Define edges – segmentation first so downstream nodes have food labels
    builder.add_edge(START, "call_mcp_segmentation")

    # If segmentation is unavailable/empty, skip retrieval and use fallback advice.
    def _route_after_segmentation(state: AgentState) -> str:
      mode = state.get("workflow_mode") or "FULL"
      return "generate_advice" if mode == "CALORIE_ONLY" else "fetch_user_memory"

    builder.add_conditional_edges(
      "call_mcp_segmentation",
      _route_after_segmentation,
      {
        "fetch_user_memory": "fetch_user_memory",
        "generate_advice": "generate_advice",
      },
    )
    builder.add_edge("fetch_user_memory", "rag_nutrition_lookup")
    builder.add_edge("rag_nutrition_lookup", "generate_advice")
    builder.add_edge("generate_advice", "publish_result")
    builder.add_edge("publish_result", END)

    return builder.compile()


# Singleton compiled graph
nutri_graph = build_graph()
