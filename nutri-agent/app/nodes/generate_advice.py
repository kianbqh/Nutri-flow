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
else:
    AgentState = dict

logger = logging.getLogger(__name__)


class LLMSettings(BaseSettings):
    moonshot_api_key: str = ""
    moonshot_base_url: str = "https://api.moonshot.cn/v1"
    llm_model: str = "kimi-k2-5"
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
        label = item.get("label") or item.get("class_name") or item.get("display_name") or "unknown"
        conf = item.get("confidence")
        if conf is None:
            conf = item.get("confidence_score", 0.0)
        weight = item.get("estimated_weight_g")
        if weight is None:
            weight = item.get("weight_g")
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
    workflow_mode = state.get("workflow_mode") or "FULL"
    workflow_trace = list(state.get("workflow_trace") or [])

    if workflow_mode == "CALORIE_ONLY":
        goal = (state.get("user_context") or {}).get("healthGoal", "GENERAL_HEALTH")
        goal_hint = {
            "WEIGHT_LOSS": "当前目标是减脂，建议优先控制总热量并减少高糖高油食物。",
            "MUSCLE_GAIN": "当前目标是增肌，建议下一餐增加优质蛋白并保证主食摄入。",
            "MAINTENANCE": "当前目标是体重维持，建议三餐规律并维持均衡搭配。",
            "GENERAL_HEALTH": "建议保持蔬菜、蛋白与主食搭配，避免长期单一饮食。",
        }.get(goal, "建议保持食物多样性，控制总热量。")

        fallback = (
            "本次图像识别结果较少，已按热量管理模式提供基础建议：\n"
            f"1) {goal_hint}\n"
            "2) 可尝试在更明亮环境下重拍，提升识别稳定性。\n"
            "3) 结果为估算值，请结合实际份量调整。"
        )
        workflow_trace.append("generate_advice: CALORIE_ONLY fallback advice generated")
        return {"advice_report": fallback, "workflow_trace": workflow_trace}

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
        workflow_trace.append("generate_advice: FULL workflow advice generated successfully")
    except Exception as exc:
        logger.error("LLM advice generation failed: %s", exc)
        goal = (state.get("user_context") or {}).get("healthGoal", "GENERAL_HEALTH")
        goal_hint = {
            "WEIGHT_LOSS": "当前目标是减脂，建议下一餐减少主食分量并增加蔬菜占比。",
            "MUSCLE_GAIN": "当前目标是增肌，建议下一餐补充优质蛋白并保持适量碳水。",
            "MAINTENANCE": "当前目标是体重维持，建议控制总量并保持三餐规律。",
            "GENERAL_HEALTH": "建议保持食物多样性，少油少盐，注意饮水。",
        }.get(goal, "建议保持食物多样性，控制总热量。")
        advice_report = (
            "暂时无法调用大模型服务，已为你提供基础建议：\n"
            f"1) {goal_hint}\n"
            "2) 本餐尽量做到主食、蛋白、蔬菜搭配。\n"
            "3) 若本餐偏油或偏咸，下一餐可适当清淡。"
        )
        workflow_trace.append("generate_advice: LLM unavailable, fallback advice generated")

    return {"advice_report": advice_report, "workflow_trace": workflow_trace}
