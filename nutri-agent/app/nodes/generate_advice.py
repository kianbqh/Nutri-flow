"""
Node: generate_advice

Uses an LLM (via LangChain) to synthesise segmentation results, RAG context,
and user memory into a personalised dietary advice report.
"""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING

from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState

logger = logging.getLogger(__name__)


class LLMSettings(BaseSettings):
    moonshot_api_key: str = ""
    moonshot_base_url: str = "https://api.moonshot.cn/v1"
    llm_model: str = "moonshot-v1-8k"
    llm_temperature: float = 0.3

    class Config:
        env_prefix = "NUTRI_"


_settings = LLMSettings()

ADVICE_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        (
            "You are a professional registered dietitian. "
            "Analyse the user's meal and provide concise, actionable dietary advice. "
            "Always consider the user's health goals and dietary restrictions. "
            "Be encouraging and specific."
        ),
    ),
    (
        "human",
        (
            "## Detected Meal Items\n{segmentation_summary}\n\n"
            "## Nutritional Knowledge\n{rag_context}\n\n"
            "## User Profile & History\n{user_memory}\n\n"
            "## User Health Context\n{user_context}\n\n"
            "Please provide a personalised dietary analysis and recommendations for this meal."
        ),
    ),
])


def _build_segmentation_summary(segmentation_result: dict | None) -> str:
    if not segmentation_result:
        return "No segmentation data available."
    items = segmentation_result.get("detected_items", [])
    if not items:
        return "No food items were detected in the image."
    lines = []
    for item in items:
        label = item.get("label", "unknown")
        conf = item.get("confidence", 0.0)
        weight = item.get("estimated_weight_g")
        weight_str = f"{weight:.0f}g" if weight else "weight unknown"
        lines.append(f"- {label} (confidence: {conf:.0%}, {weight_str})")
    return "\n".join(lines)


async def generate_advice(state: "AgentState") -> dict:
    """
    Call the LLM to generate a personalised dietary advice report.
    """
    logger.info("Generating dietary advice for task_id=%s", state["task_id"])

    segmentation_summary = _build_segmentation_summary(state.get("segmentation_result"))
    rag_context = state.get("rag_context") or "Not available."
    user_memory = state.get("user_memory") or "No history available."
    user_context_str = json.dumps(state.get("user_context") or {}, ensure_ascii=False)

    try:
        llm = ChatOpenAI(
            model=_settings.llm_model,
            temperature=_settings.llm_temperature,
            api_key=_settings.moonshot_api_key or None,
            base_url=_settings.moonshot_base_url,
        )
        chain = ADVICE_PROMPT | llm
        response = await chain.ainvoke({
            "segmentation_summary": segmentation_summary,
            "rag_context": rag_context,
            "user_memory": user_memory,
            "user_context": user_context_str,
        })
        advice_report: str = response.content
    except Exception as exc:
        logger.error("LLM advice generation failed: %s", exc)
        advice_report = (
            f"Unable to generate personalised advice at this time. "
            f"Detected items: {segmentation_summary}"
        )

    return {"advice_report": advice_report}
