"""
Node: fetch_user_memory

Builds a "user long-term memory" string for the LLM advice node.

Sources (in order of preference):

1. nutri-business diet history API – authoritative source of truth for
   recent meals and previously generated advice reports. Aligns with
   ``docs/软件工程文档包/04_数据库设计文档.md``.
2. Optional ChromaDB ``user_memory`` collection – appended if reachable.
3. Rule-based fallback – derived from ``state["user_context"]``.
"""

from __future__ import annotations

from collections import Counter
import logging
from typing import TYPE_CHECKING, List

import httpx
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.chroma_http import query_text_records, upsert_text_records

if TYPE_CHECKING:
    from app.graph import AgentState
else:
    AgentState = dict

logger = logging.getLogger(__name__)


MEAL_TYPE_DISPLAY_NAMES = {
    "BREAKFAST": "早餐",
    "LUNCH": "午餐",
    "DINNER": "晚餐",
    "SNACK": "加餐",
}

ADVICE_THEME_KEYWORDS = {
    "控制油脂": ("少油", "油炸", "油脂", "清淡", "高油"),
    "补充蔬菜": ("蔬菜", "纤维", "绿叶", "沙拉"),
    "增加蛋白": ("蛋白", "鸡蛋", "豆腐", "鱼", "鸡胸", "瘦肉"),
    "控制主食": ("主食", "碳水", "米饭", "面", "馒头"),
    "控制糖分": ("糖", "甜", "饮料", "奶茶", "甜点"),
    "注意饮水": ("饮水", "喝水", "水分"),
    "规律进食": ("规律", "定时", "晚餐过晚", "夜宵"),
}

GENDER_DISPLAY_NAMES = {
    "MALE": "男性",
    "FEMALE": "女性",
    "OTHER": "未说明性别",
}

ACTIVITY_LEVEL_DISPLAY_NAMES = {
    "LOW": "活动量低",
    "MEDIUM": "活动量中",
    "HIGH": "活动量高",
}


class MemorySettings(BaseSettings):
    business_base_url: str = "http://localhost:8080/api/v1"
    business_history_size: int = 8
    business_timeout_seconds: float = 5.0

    chroma_host: str = "localhost"
    chroma_port: int = 8100
    chroma_user_memory_collection: str = "user_memory"
    chroma_enabled: bool = True
    chroma_user_memory_results: int = 4
    chroma_memory_bootstrap_from_history: bool = True
    chroma_memory_max_bootstrap_records: int = 20

    model_config = SettingsConfigDict(
        env_prefix="NUTRI_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


_settings = MemorySettings()


def _truncate(text: str, limit: int = 80) -> str:
    text = (text or "").strip().replace("\n", " ")
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def _meal_type_display(meal_type: str) -> str:
    normalized = str(meal_type or "").strip().upper()
    return MEAL_TYPE_DISPLAY_NAMES.get(normalized, meal_type or "未知餐次")


def _as_float(value: object, default: float = 0.0) -> float:
    try:
        return float(value)  # type: ignore[arg-type]
    except Exception:
        return default


def _build_body_condition_lines(user_context: dict | None) -> List[str]:
    user_context = user_context or {}
    age = user_context.get("age")
    height_cm = user_context.get("heightCm")
    weight_kg = user_context.get("weightKg")
    gender = str(user_context.get("gender") or "").strip().upper()
    activity_level = str(user_context.get("activityLevel") or "").strip().upper()

    lines: List[str] = []
    if age:
        lines.append(f"- 年龄：{age} 岁")
    if height_cm:
        lines.append(f"- 身高：{height_cm} cm")
    if weight_kg:
        lines.append(f"- 体重：{weight_kg} kg")
    if gender:
        lines.append(f"- 性别：{GENDER_DISPLAY_NAMES.get(gender, gender)}")
    if activity_level:
        lines.append(
            f"- 活动水平：{ACTIVITY_LEVEL_DISPLAY_NAMES.get(activity_level, activity_level)}"
        )

    height_m = _as_float(height_cm, 0.0) / 100.0
    weight_value = _as_float(weight_kg, 0.0)
    if height_m > 0 and weight_value > 0:
        bmi = weight_value / (height_m * height_m)
        if bmi < 18.5:
            bmi_status = "偏瘦"
        elif bmi < 24.0:
            bmi_status = "正常范围"
        elif bmi < 28.0:
            bmi_status = "超重"
        else:
            bmi_status = "肥胖风险偏高"
        lines.append(f"- BMI 约 {bmi:.1f}，体型判断：{bmi_status}")
    return lines


async def _fetch_history_from_business(user_id: str) -> List[dict]:
    url = f"{_settings.business_base_url.rstrip('/')}/diet-logs"
    params = {"userId": user_id, "page": 0, "size": _settings.business_history_size}
    async with httpx.AsyncClient(timeout=_settings.business_timeout_seconds) as client:
        resp = await client.get(url, params=params)
        resp.raise_for_status()
        body = resp.json()
    content = body.get("content") if isinstance(body, dict) else None
    return list(content or [])


def _format_history_lines(records: List[dict]) -> List[str]:
    lines: List[str] = []
    for rec in records:
        meal = rec.get("mealType") or "-"
        logged_at = (rec.get("loggedAt") or "")[:10] or "-"
        status = rec.get("status") or "-"
        items_count = rec.get("detectedItemsCount") or 0
        advice = _truncate(rec.get("adviceReport") or "", 60)
        if status == "COMPLETED":
            line = f"- {logged_at} {meal}: {items_count} 类食物"
            if advice:
                line += f"，上次建议：{advice}"
            lines.append(line)
        else:
            lines.append(f"- {logged_at} {meal}: 状态={status}")
    return lines


def _summarise_history_patterns(records: List[dict]) -> List[str]:
    if not records:
        return ["- 暂无可用历史模式。"]

    completed_records = [rec for rec in records if str(rec.get("status") or "") == "COMPLETED"]
    meal_counter = Counter(
        _meal_type_display(str(rec.get("mealType") or "UNKNOWN"))
        for rec in completed_records
    )
    avg_items = 0.0
    if completed_records:
        avg_items = sum(int(rec.get("detectedItemsCount") or 0) for rec in completed_records) / len(completed_records)

    advice_theme_counter: Counter[str] = Counter()
    for rec in completed_records:
        advice_text = str(rec.get("adviceReport") or "")
        for theme, keywords in ADVICE_THEME_KEYWORDS.items():
            if any(keyword in advice_text for keyword in keywords):
                advice_theme_counter[theme] += 1

    lines = [
        f"- 最近 {len(records)} 条记录中，已完成 {len(completed_records)} 条分析。",
    ]
    if meal_counter:
        top_meals = "、".join(
            f"{meal} {count} 次" for meal, count in meal_counter.most_common(2)
        )
        lines.append(f"- 最近完成记录里最常出现的餐次：{top_meals}。")
    if completed_records:
        lines.append(f"- 已完成记录平均识别约 {avg_items:.1f} 类食物。")
    if advice_theme_counter:
        themes = "、".join(
            f"{theme} ({count})" for theme, count in advice_theme_counter.most_common(3)
        )
        lines.append(f"- 历史建议高频主题：{themes}。")
    return lines


def _history_records_to_memory_docs(user_id: str, records: List[dict]) -> List[dict]:
    docs: List[dict] = []
    for rec in records[: _settings.chroma_memory_max_bootstrap_records]:
        task_id = str(rec.get("taskId") or "")
        meal_type = str(rec.get("mealType") or "UNKNOWN")
        logged_at = str(rec.get("loggedAt") or "")
        status = str(rec.get("status") or "")
        items_count = rec.get("detectedItemsCount") or 0
        advice = _truncate(rec.get("adviceReport") or "", 120)
        document = (
            f"用户{user_id} 在 {logged_at} 的 {meal_type} 餐次状态={status}，"
            f"识别{items_count}类食物。"
        )
        if advice:
            document += f"历史建议：{advice}"
        doc_id = f"u:{user_id}:task:{task_id or logged_at or meal_type}"
        docs.append(
            {
                "id": doc_id,
                "document": document,
                "metadata": {
                    "domain": "user_memory",
                    "user_id": str(user_id),
                    "task_id": task_id,
                    "meal_type": meal_type,
                },
            }
        )
    return docs


def _summarise_user_context(user_context: dict | None) -> List[str]:
    user_context = user_context or {}
    goal = user_context.get("healthGoal", "GENERAL_HEALTH")
    target = user_context.get("dailyCalorieTarget")
    restrictions = user_context.get("dietaryRestrictions") or []
    restrictions_text = "、".join(map(str, restrictions)) if restrictions else "无明确限制"
    lines = [
        f"- 健康目标：{goal}",
        f"- 每日热量目标：{target if target else '未设置'} kcal",
        f"- 饮食限制：{restrictions_text}",
    ]
    lines.extend(_build_body_condition_lines(user_context))
    return lines


async def _augment_from_chroma(user_id: str, food_labels: List[str]) -> List[str]:
    if not _settings.chroma_enabled:
        return []
    try:
        if food_labels:
            query = (
                f"dietary preferences for user {user_id} "
                f"regarding foods: {', '.join(food_labels)}"
            )
        else:
            query = f"long-term dietary preferences for user {user_id}"
        results = await query_text_records(
            _settings.chroma_user_memory_collection,
            query,
            n_results=_settings.chroma_user_memory_results,
            where={"user_id": str(user_id)},
            metadata={"domain": "user_memory"},
        )
        documents: List[str] = (results.get("documents") or [[]])[0]
        return [f"- (向量记忆) {doc}" for doc in documents if doc]
    except Exception as exc:
        logger.debug("Chroma user_memory augmentation skipped: %s", exc)
        return []


async def fetch_user_memory(state: "AgentState") -> dict:
    user_id: str = str(state["user_id"])
    workflow_trace = list(state.get("workflow_trace") or [])
    food_labels: List[str] = list(state.get("detected_labels") or [])
    user_context = state.get("user_context") or {}

    sections: List[str] = ["## 用户画像"]
    sections.extend(_summarise_user_context(user_context))
    sources: List[str] = []

    history_records: List[dict] = []
    history_error: str | None = None
    try:
        history_records = await _fetch_history_from_business(user_id)
    except Exception as exc:
        history_error = str(exc)
        logger.warning("fetch_user_memory: business history unavailable: %s", exc)

    if history_records:
        sections.append("\n## 最近用餐记录（来自业务库）")
        sections.extend(_format_history_lines(history_records))
        sections.append("\n## 历史模式摘要")
        sections.extend(_summarise_history_patterns(history_records))
        sources.append(f"业务历史 {len(history_records)} 条")

        # Keep user memory vector-store warm with recent history so retrieval
        # remains useful even when business API latency fluctuates.
        if _settings.chroma_enabled and _settings.chroma_memory_bootstrap_from_history:
            try:
                docs = _history_records_to_memory_docs(user_id, history_records)
                upserted = await upsert_text_records(
                    _settings.chroma_user_memory_collection,
                    docs,
                    metadata={"domain": "user_memory"},
                )
                if upserted > 0:
                    sources.append(f"记忆入库 {upserted} 条")
            except Exception as exc:
                logger.debug("Chroma user_memory bootstrap skipped: %s", exc)
    elif history_error:
        sections.append("\n## 最近用餐记录")
        sections.append("- 业务历史接口暂不可用，已退化为画像兜底。")

    chroma_lines = await _augment_from_chroma(user_id, food_labels)
    if chroma_lines:
        sections.append("\n## 长期偏好（向量记忆）")
        sections.extend(chroma_lines)
        sources.append(f"向量记忆 {len(chroma_lines)} 条")

    user_memory = "\n".join(sections).strip()

    if sources:
        workflow_trace.append(
            "fetch_user_memory: retrieved "
            f"{_settings.chroma_user_memory_results} memory docs max for user_id={user_id} "
            "(" + " + ".join(sources) + ")"
        )
    else:
        workflow_trace.append(
            "fetch_user_memory: user memory unavailable, fallback to profile context"
        )

    return {"user_memory": user_memory, "workflow_trace": workflow_trace}
