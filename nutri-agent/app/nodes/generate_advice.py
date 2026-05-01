"""
Node: generate_advice

Uses an LLM (via LangChain) to synthesise segmentation results, RAG context,
and user memory into a personalised dietary advice report.
"""

from __future__ import annotations

import json
import logging
import time
from typing import TYPE_CHECKING

from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from pydantic_settings import BaseSettings, SettingsConfigDict

if TYPE_CHECKING:
    from app.graph import AgentState
else:
    AgentState = dict

logger = logging.getLogger(__name__)


GOAL_DISPLAY_NAMES = {
    "WEIGHT_LOSS": "减脂",
    "MUSCLE_GAIN": "增肌",
    "MAINTENANCE": "体重维持",
    "GENERAL_HEALTH": "健康饮食",
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

MEAL_TYPE_DISPLAY_NAMES = {
    "BREAKFAST": "早餐",
    "LUNCH": "午餐",
    "DINNER": "晚餐",
    "SNACK": "加餐",
}

MEAL_TARGET_RATIOS = {
    "BREAKFAST": 0.25,
    "LUNCH": 0.35,
    "DINNER": 0.30,
    "SNACK": 0.10,
}

FOOD_CATEGORY_KEYWORDS = {
    "staple": {
        "rice", "noodle", "noodles", "bread", "bun", "pizza", "pasta", "potato",
        "corn", "oat", "米饭", "面", "面条", "面包", "馒头", "包子", "披萨", "土豆",
        "红薯", "玉米", "燕麦", "主食",
    },
    "protein": {
        "beef", "chicken", "fish", "egg", "tofu", "pork", "shrimp", "milk", "steak",
        "meat", "yogurt", "牛肉", "鸡肉", "鱼", "鸡蛋", "蛋", "豆腐", "猪肉", "虾",
        "牛奶", "酸奶", "肉", "蛋白",
    },
    "vegetable": {
        "broccoli", "tomato", "lettuce", "carrot", "eggplant", "cabbage", "mushroom",
        "salad", "vegetable", "broccoli", "西兰花", "番茄", "生菜", "胡萝卜", "茄子",
        "卷心菜", "蘑菇", "沙拉", "蔬菜", "青菜", "黄瓜", "菠菜",
    },
    "fruit": {
        "apple", "banana", "orange", "fruit", "苹果", "香蕉", "橙", "水果",
    },
    "fried": {
        "fried", "fries", "crispy", "炸", "油条", "薯条", "酥", "锅包",
    },
    "sugary": {
        "cake", "dessert", "sweet", "soda", "milk tea", "奶茶", "蛋糕", "甜", "可乐",
        "饮料", "糖", "冰淇淋",
    },
}

RESTRICTION_RULES = {
    "HIGH_SUGAR": {"categories": {"sugary"}, "message": "当前餐次出现甜食或含糖饮品线索，控糖时要重点关注。"},
    "LOW_SUGAR": {"categories": {"sugary"}, "message": "当前餐次出现甜食或含糖饮品线索，控糖时要重点关注。"},
    "HIGH_FAT": {"categories": {"fried"}, "message": "当前餐次疑似存在高油烹饪特征，不利于控脂。"},
    "LOW_FAT": {"categories": {"fried"}, "message": "当前餐次疑似存在高油烹饪特征，不利于控脂。"},
    "GLUTEN": {"keywords": {"bread", "noodle", "noodles", "pasta", "面", "面条", "面包", "馒头"}, "message": "当前餐次可能包含含麸质主食，需进一步确认原料。"},
    "GLUTEN_FREE": {"keywords": {"bread", "noodle", "noodles", "pasta", "面", "面条", "面包", "馒头"}, "message": "当前餐次可能包含含麸质主食，需进一步确认原料。"},
    "SEAFOOD": {"keywords": {"shrimp", "fish", "虾", "鱼", "蟹", "贝"}, "message": "当前餐次出现海鲜线索，若有海鲜限制或过敏需谨慎。"},
    "SEAFOOD_ALLERGY": {"keywords": {"shrimp", "fish", "虾", "鱼", "蟹", "贝"}, "message": "当前餐次出现海鲜线索，若有海鲜限制或过敏需谨慎。"},
    "DAIRY": {"keywords": {"milk", "cheese", "butter", "cream", "牛奶", "芝士", "黄油", "奶"}, "message": "当前餐次可能包含乳制品，不适合乳制品限制人群。"},
    "LACTOSE": {"keywords": {"milk", "cheese", "yogurt", "ice cream", "牛奶", "酸奶", "奶", "冰淇淋"}, "message": "当前餐次可能包含乳糖来源，乳糖不耐受时需控制。"},
    "NUTS": {"keywords": {"nut", "peanut", "almond", "cashew", "坚果", "花生", "腰果", "杏仁"}, "message": "当前餐次可能存在坚果相关食材，若过敏需谨慎。"},
    "SPICY": {"keywords": {"spicy", "chili", "pepper", "辣", "麻辣", "辣椒"}, "message": "当前餐次有辛辣特征，若肠胃敏感或少辣需求明显需控制。"},
    "LOW_CARB": {"categories": {"staple"}, "message": "当前餐次含较明显主食，若执行控碳需注意主食份量。"},
    "NO_BEEF": {"keywords": {"beef", "steak", "牛肉", "牛排"}, "message": "当前餐次包含牛肉线索，与禁牛肉限制冲突。"},
    "NO_PORK": {"keywords": {"pork", "猪肉"}, "message": "当前餐次包含猪肉线索，与禁猪肉限制冲突。"},
    "VEGETARIAN": {"keywords": {"beef", "chicken", "fish", "pork", "shrimp", "牛肉", "鸡肉", "鱼", "猪肉", "虾"}, "message": "当前餐次包含明显动物性食材，与素食限制不一致。"},
}

RESTRICTION_DISPLAY_NAMES = {
    "HIGH_SUGAR": "控糖",
    "LOW_SUGAR": "控糖",
    "HIGH_FAT": "控脂",
    "LOW_FAT": "控脂",
    "GLUTEN": "麸质限制",
    "GLUTEN_FREE": "麸质限制",
    "SEAFOOD": "海鲜限制",
    "SEAFOOD_ALLERGY": "海鲜过敏",
    "DAIRY": "乳制品限制",
    "LACTOSE": "乳糖不耐",
    "NUTS": "坚果过敏",
    "SPICY": "少辣",
    "LOW_CARB": "控碳",
    "NO_BEEF": "不吃牛肉",
    "NO_PORK": "不吃猪肉",
    "VEGETARIAN": "素食",
}


class LLMSettings(BaseSettings):
    llm_provider: str = "moonshot"
    llm_api_key: str = ""
    llm_base_url: str = ""
    moonshot_api_key: str = ""
    moonshot_base_url: str = "https://api.moonshot.cn/v1"
    moonshot_model: str = "moonshot-v1-8k"
    deepseek_api_key: str = ""
    deepseek_base_url: str = "https://api.deepseek.com/v1"
    deepseek_model: str = "deepseek-chat"
    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1"
    openai_model: str = "gpt-4o-mini"
    llm_model: str = "moonshot-v1-8k"
    llm_temperature: float = 0.3
    llm_timeout_seconds: float = 40.0
    llm_max_output_tokens: int = 420
    llm_context_char_limit: int = 1200

    model_config = SettingsConfigDict(
        env_prefix="NUTRI_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


_settings = LLMSettings()


def _resolve_llm_config() -> tuple[str, str, str]:
    provider = (_settings.llm_provider or "moonshot").strip().lower()

    explicit_api_key = (_settings.llm_api_key or "").strip()
    explicit_base_url = (_settings.llm_base_url or "").strip()
    explicit_model = (_settings.llm_model or "").strip()

    provider_defaults = {
        "moonshot": (
            (_settings.moonshot_api_key or "").strip(),
            (_settings.moonshot_base_url or "").strip(),
            (_settings.moonshot_model or "").strip(),
        ),
        "deepseek": (
            (_settings.deepseek_api_key or "").strip(),
            (_settings.deepseek_base_url or "").strip(),
            (_settings.deepseek_model or "").strip(),
        ),
        "openai": (
            (_settings.openai_api_key or "").strip(),
            (_settings.openai_base_url or "").strip(),
            (_settings.openai_model or "").strip(),
        ),
    }

    default_api_key, default_base_url, default_model = provider_defaults.get(
        provider,
        ("", "", explicit_model or "gpt-4o-mini"),
    )
    api_key = explicit_api_key or default_api_key
    base_url = explicit_base_url or default_base_url
    model = explicit_model or default_model
    return provider, api_key, base_url, model


def _resolve_llm_temperature(provider: str, model: str) -> float:
    temperature = float(_settings.llm_temperature)
    normalized_provider = provider.strip().lower()
    normalized_model = model.strip().lower()

    # Kimi K2.6 currently accepts only temperature=1.
    if normalized_provider == "moonshot" and normalized_model.startswith("kimi-k2.6"):
        return 1.0

    return temperature


def _resolve_llm_timeout_seconds(provider: str, model: str) -> float:
    timeout_seconds = float(_settings.llm_timeout_seconds)
    normalized_provider = provider.strip().lower()
    normalized_model = model.strip().lower()

    if normalized_provider == "moonshot" and normalized_model.startswith("kimi-k2.6"):
        return max(timeout_seconds, 180.0)

    return timeout_seconds


def _build_rule_based_advice(state: "AgentState", reason: str) -> str:
    seg = state.get("segmentation_result") or {}
    items = seg.get("detected_items", [])

    labels = []
    total_kcal = 0.0
    for item in items:
        name = item.get("display_name") or item.get("label") or item.get("class_name") or "未知食物"
        labels.append(str(name))
        nutrition = item.get("nutrition") or {}
        kcal = nutrition.get("calories_kcal") or item.get("calories") or 0.0
        try:
            total_kcal += float(kcal)
        except Exception:
            pass

    labels_text = "、".join(labels[:4]) if labels else "未识别到明确菜品"
    kcal_text = f"约 {total_kcal:.1f} 千卡" if total_kcal > 0 else "热量估算中"

    goal = (state.get("user_context") or {}).get("healthGoal", "GENERAL_HEALTH")
    body_condition = _build_body_condition_summary(state)
    goal_hint = {
        "WEIGHT_LOSS": "当前目标是减脂，建议下一餐减少主食分量并增加蔬菜占比。",
        "MUSCLE_GAIN": "当前目标是增肌，建议下一餐补充优质蛋白并保持适量碳水。",
        "MAINTENANCE": "当前目标是体重维持，建议控制总量并保持三餐规律。",
        "GENERAL_HEALTH": "建议保持食物多样性，少油少盐，注意饮水。",
    }.get(goal, "建议保持食物多样性，控制总热量。")

    return (
        f"已进入智能规则建议模式（{reason}）。\n"
        f"本餐识别：{labels_text}；估算热量：{kcal_text}。\n"
        f"身体情况参考：{body_condition.replace(chr(10), '；')}\n"
        f"1) {goal_hint}\n"
        "2) 本餐尽量做到主食、蛋白、蔬菜搭配。\n"
        "3) 若本餐偏油或偏咸，下一餐可适当清淡。"
    )


def _clip_context(text: str, limit: int) -> str:
    cleaned = (text or "").strip()
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 12].rstrip() + "\n...\n[已截断]"


def _as_float(value: object, default: float = 0.0) -> float:
    try:
        return float(value)  # type: ignore[arg-type]
    except Exception:
        return default


def _normalise_text(value: object) -> str:
    return str(value or "").strip()


def _meal_type_display(meal_type: str) -> str:
    normalized = _normalise_text(meal_type).upper()
    return MEAL_TYPE_DISPLAY_NAMES.get(normalized, meal_type or "本餐")


def _goal_display(goal: str) -> str:
    normalized = _normalise_text(goal).upper()
    return GOAL_DISPLAY_NAMES.get(normalized, goal or "健康饮食")


def _gender_display(gender: str) -> str:
    normalized = _normalise_text(gender).upper()
    return GENDER_DISPLAY_NAMES.get(normalized, gender or "未说明性别")


def _activity_level_display(activity_level: str) -> str:
    normalized = _normalise_text(activity_level).upper()
    return ACTIVITY_LEVEL_DISPLAY_NAMES.get(normalized, activity_level or "未说明活动量")


def _restriction_display(restriction: str) -> str:
    normalized = _normalise_text(restriction).upper()
    return RESTRICTION_DISPLAY_NAMES.get(normalized, restriction)


def _item_label(item: dict) -> str:
    return (
        _normalise_text(item.get("display_name"))
        or _normalise_text(item.get("label"))
        or _normalise_text(item.get("class_name"))
        or "未知食物"
    )


def _item_nutrition(item: dict) -> dict[str, float]:
    nutrition = item.get("nutrition") or {}
    return {
        "calories_kcal": _as_float(nutrition.get("calories_kcal") or item.get("calories"), 0.0),
        "protein_g": _as_float(nutrition.get("protein_g"), 0.0),
        "fat_g": _as_float(nutrition.get("fat_g"), 0.0),
        "carbs_g": _as_float(nutrition.get("carbs_g"), 0.0),
        "fiber_g": _as_float(nutrition.get("fiber_g"), 0.0),
    }


def _detect_categories(labels: list[str]) -> dict[str, list[str]]:
    detected = {name: [] for name in FOOD_CATEGORY_KEYWORDS}
    for raw_label in labels:
        normalized_label = _normalise_text(raw_label).lower()
        if not normalized_label:
            continue
        for category, keywords in FOOD_CATEGORY_KEYWORDS.items():
            if any(keyword in normalized_label for keyword in keywords):
                detected[category].append(raw_label)
    return detected


def _meal_ratio_bounds(daily_target: float, meal_type: str) -> tuple[float, float] | None:
    if daily_target <= 0:
        return None
    ratio = MEAL_TARGET_RATIOS.get(_normalise_text(meal_type).upper())
    if ratio is None:
        return None
    base = daily_target * ratio
    return base * 0.85, base * 1.15


def _build_meal_metrics(segmentation_result: dict | None) -> dict[str, object]:
    seg = segmentation_result or {}
    items = list(seg.get("detected_items") or [])
    labels = [_item_label(item) for item in items]
    totals = {
        "calories_kcal": _as_float(seg.get("total_calories_kcal"), 0.0),
        "protein_g": 0.0,
        "fat_g": 0.0,
        "carbs_g": 0.0,
        "fiber_g": 0.0,
        "weight_g": 0.0,
    }
    top_items: list[tuple[str, float]] = []

    for item in items:
        nutrition = _item_nutrition(item)
        weight_g = _as_float(item.get("estimated_weight_g") or item.get("weight_g"), 0.0)
        totals["protein_g"] += nutrition["protein_g"]
        totals["fat_g"] += nutrition["fat_g"]
        totals["carbs_g"] += nutrition["carbs_g"]
        totals["fiber_g"] += nutrition["fiber_g"]
        totals["weight_g"] += weight_g
        top_items.append((_item_label(item), nutrition["calories_kcal"]))

    if totals["calories_kcal"] <= 0:
        totals["calories_kcal"] = sum(calories for _, calories in top_items)

    top_items.sort(key=lambda pair: pair[1], reverse=True)
    category_hits = _detect_categories(labels)
    present_categories = [
        cn for cn, category in (("主食", "staple"), ("蛋白", "protein"), ("蔬菜", "vegetable"), ("水果", "fruit"))
        if category_hits.get(category)
    ]
    missing_categories = [
        cn for cn, category in (("主食", "staple"), ("蛋白", "protein"), ("蔬菜", "vegetable"))
        if not category_hits.get(category)
    ]

    total_kcal = float(totals["calories_kcal"])
    fat_ratio = ((float(totals["fat_g"]) * 9) / total_kcal) if total_kcal > 0 else 0.0
    carb_ratio = ((float(totals["carbs_g"]) * 4) / total_kcal) if total_kcal > 0 else 0.0
    protein_ratio = ((float(totals["protein_g"]) * 4) / total_kcal) if total_kcal > 0 else 0.0
    kcal_density = ((total_kcal / float(totals["weight_g"])) * 100.0) if float(totals["weight_g"]) > 0 else 0.0

    return {
        "items": items,
        "labels": labels,
        "totals": totals,
        "top_items": top_items[:3],
        "category_hits": category_hits,
        "present_categories": present_categories,
        "missing_categories": missing_categories,
        "fat_ratio": fat_ratio,
        "carb_ratio": carb_ratio,
        "protein_ratio": protein_ratio,
        "kcal_density": kcal_density,
    }


def _build_current_meal_profile(state: "AgentState") -> str:
    metrics = _build_meal_metrics(state.get("segmentation_result"))
    labels = list(metrics["labels"])
    totals = metrics["totals"]
    top_items = list(metrics["top_items"])
    if not labels:
        return "- 当前餐次仅有有限识别结果，无法建立稳定的餐食结构画像。"

    lines = [
        f"- 餐次：{_meal_type_display(_normalise_text(state.get('meal_type') or ''))}",
        f"- 识别到 {len(labels)} 类食物：{'、'.join(labels[:6])}",
    ]

    total_kcal = float(totals["calories_kcal"])
    if total_kcal > 0:
        macro_text = (
            f"蛋白 {float(totals['protein_g']):.1f}g / 脂肪 {float(totals['fat_g']):.1f}g / "
            f"碳水 {float(totals['carbs_g']):.1f}g / 纤维 {float(totals['fiber_g']):.1f}g"
        )
        lines.append(f"- 估算总热量约 {total_kcal:.0f} kcal；{macro_text}")
    if float(totals["weight_g"]) > 0:
        lines.append(
            f"- 估算总重量约 {float(totals['weight_g']):.0f}g；能量密度约 {float(metrics['kcal_density']):.0f} kcal/100g"
        )
    if top_items:
        top_text = "、".join(f"{label} {kcal:.0f} kcal" for label, kcal in top_items if kcal > 0)
        if top_text:
            lines.append(f"- 主要热量来源：{top_text}")

    present_categories = list(metrics["present_categories"])
    missing_categories = list(metrics["missing_categories"])
    if present_categories:
        lines.append(f"- 当前搭配已覆盖：{'、'.join(present_categories)}")
    if missing_categories:
        lines.append(f"- 当前搭配相对欠缺：{'、'.join(missing_categories)}")
    return "\n".join(lines)


def _build_goal_alignment(state: "AgentState") -> str:
    user_context = state.get("user_context") or {}
    goal = _normalise_text(user_context.get("healthGoal") or "GENERAL_HEALTH").upper()
    daily_target = _as_float(user_context.get("dailyCalorieTarget"), 0.0)
    meal_type = _normalise_text(state.get("meal_type") or "")
    metrics = _build_meal_metrics(state.get("segmentation_result"))
    totals = metrics["totals"]
    total_kcal = float(totals["calories_kcal"])

    lines = [f"- 当前健康目标：{_goal_display(goal)}"]
    if daily_target > 0:
        lines.append(f"- 每日热量目标：{daily_target:.0f} kcal")
        meal_bounds = _meal_ratio_bounds(daily_target, meal_type)
        if meal_bounds:
            lower, upper = meal_bounds
            lines.append(
                f"- 按{_meal_type_display(meal_type)}分配，本餐参考区间约 {lower:.0f}-{upper:.0f} kcal"
            )
            if total_kcal > 0:
                if total_kcal > upper:
                    lines.append("- 当前餐次热量高于该餐推荐区间，后续餐次应主动回收热量。")
                elif total_kcal < lower:
                    lines.append("- 当前餐次热量低于该餐推荐区间，需关注后续是否出现过度饥饿或补偿进食。")
                else:
                    lines.append("- 当前餐次热量基本落在该餐推荐区间内。")

    protein_g = float(totals["protein_g"])
    fiber_g = float(totals["fiber_g"])
    fat_ratio = float(metrics["fat_ratio"])
    carb_ratio = float(metrics["carb_ratio"])
    present_categories = set(metrics["present_categories"])

    if goal == "WEIGHT_LOSS":
        if fat_ratio >= 0.38:
            lines.append("- 该餐脂肪供能占比较高，减脂阶段更需要压低油脂和隐形热量。")
        if fiber_g < 6:
            lines.append("- 该餐膳食纤维偏少，饱腹感和控能量稳定性可能不足。")
        if "蔬菜" not in present_categories:
            lines.append("- 该餐缺少明确蔬菜来源，不利于减脂期做体积管理。")
    elif goal == "MUSCLE_GAIN":
        if protein_g < 25:
            lines.append("- 该餐蛋白量偏低，增肌阶段可能不足以支持恢复与合成。")
        if total_kcal > 0 and carb_ratio < 0.35:
            lines.append("- 该餐碳水占比偏低，训练后可能不利于糖原补充。")
        if "蛋白" not in present_categories:
            lines.append("- 该餐缺少明确优质蛋白来源。")
    elif goal == "MAINTENANCE":
        if "主食" not in present_categories or "蛋白" not in present_categories or "蔬菜" not in present_categories:
            lines.append("- 该餐结构不够均衡，维持期更需要稳定的主食、蛋白、蔬菜配比。")
        if fat_ratio >= 0.4:
            lines.append("- 该餐脂肪占比偏高，长期不利于体重稳定。")
    else:
        if "主食" not in present_categories or "蛋白" not in present_categories or "蔬菜" not in present_categories:
            lines.append("- 该餐没有形成稳定的主食、蛋白、蔬菜三要素搭配。")
        if fiber_g < 6:
            lines.append("- 该餐纤维偏少，建议通过蔬菜水果补足。")

    return "\n".join(lines)


def _build_restriction_check(state: "AgentState") -> str:
    user_context = state.get("user_context") or {}
    restrictions = [
        _normalise_text(item).upper()
        for item in (user_context.get("dietaryRestrictions") or [])
        if _normalise_text(item)
    ]
    if not restrictions:
        return "- 用户未设置明确饮食限制。"

    metrics = _build_meal_metrics(state.get("segmentation_result"))
    labels = [_normalise_text(label).lower() for label in metrics["labels"]]
    category_hits = {
        name for name, matched in dict(metrics["category_hits"]).items() if matched
    }

    conflicts: list[str] = []
    for restriction in restrictions:
        rule = RESTRICTION_RULES.get(restriction)
        if not rule:
            continue
        categories = set(rule.get("categories") or [])
        keywords = {str(keyword).lower() for keyword in (rule.get("keywords") or set())}
        if categories and (categories & category_hits):
            conflicts.append(str(rule["message"]))
            continue
        if keywords and any(any(keyword in label for keyword in keywords) for label in labels):
            conflicts.append(str(rule["message"]))

    lines = [f"- 用户饮食限制：{'、'.join(restrictions)}"]
    if conflicts:
        lines.extend(f"- {message}" for message in conflicts[:2])
    else:
        lines.append("- 当前餐次未发现明显与既有饮食限制直接冲突的食物线索。")
    return "\n".join(lines)


def _build_body_condition_summary(state: "AgentState") -> str:
    user_context = state.get("user_context") or {}
    age = _as_float(user_context.get("age"), 0.0)
    height_cm = _as_float(user_context.get("heightCm"), 0.0)
    weight_kg = _as_float(user_context.get("weightKg"), 0.0)
    gender = _normalise_text(user_context.get("gender") or "").upper()
    activity_level = _normalise_text(user_context.get("activityLevel") or "").upper()
    metrics = _build_meal_metrics(state.get("segmentation_result"))
    totals = metrics["totals"]
    total_kcal = float(totals["calories_kcal"])
    protein_g = float(totals["protein_g"])
    fiber_g = float(totals["fiber_g"])
    carb_g = float(totals["carbs_g"])
    goal = _normalise_text(user_context.get("healthGoal") or "GENERAL_HEALTH").upper()

    if age <= 0 and height_cm <= 0 and weight_kg <= 0 and not gender and not activity_level:
        return "- 未提供稳定的身体情况数据，请避免做过度个体化推断。"

    lines: list[str] = []
    if age > 0:
        lines.append(f"- 年龄：{age:.0f} 岁")
    if gender:
        lines.append(f"- 性别：{_gender_display(gender)}")
    if height_cm > 0:
        lines.append(f"- 身高：{height_cm:.0f} cm")
    if weight_kg > 0:
        lines.append(f"- 体重：{weight_kg:.1f} kg")
    if activity_level:
        lines.append(f"- 活动水平：{_activity_level_display(activity_level)}")

    if height_cm > 0 and weight_kg > 0:
        height_m = height_cm / 100.0
        bmi = weight_kg / (height_m * height_m)
        if bmi < 18.5:
            bmi_status = "偏瘦"
        elif bmi < 24.0:
            bmi_status = "正常范围"
        elif bmi < 28.0:
            bmi_status = "超重"
        else:
            bmi_status = "肥胖风险偏高"
        lines.append(f"- BMI 约 {bmi:.1f}，体型状态：{bmi_status}")

        if goal == "WEIGHT_LOSS" and bmi >= 24.0:
            lines.append("- 体型状态与减脂目标方向一致，建议把重点放在稳定热量缺口而不是极端节食。")
        elif goal == "MUSCLE_GAIN" and bmi < 18.5:
            lines.append("- 当前体型偏瘦，增肌目标下更应关注蛋白和总能量是否充足。")
        elif goal == "MAINTENANCE" and 18.5 <= bmi < 24.0:
            lines.append("- 当前体型大致在正常范围，建议维持规律饮食与结构平衡。")

    if age >= 45:
        if protein_g < 30:
            lines.append(
                f"- 结合当前年龄阶段，本餐蛋白约 {protein_g:.1f}g，保留肌肉和恢复支持偏弱。"
            )
        if fiber_g < 8:
            lines.append("- 当前年龄阶段更需要关注控糖稳定性和肠道健康，本餐纤维偏少。")
    elif 0 < age < 25 and goal == "MUSCLE_GAIN" and protein_g < 28:
        lines.append("- 以增肌为目标时，当前年龄阶段可更积极补足蛋白和训练后恢复营养。")

    if activity_level == "HIGH":
        if protein_g < 28:
            lines.append(
                f"- 日常活动量较高，但本餐蛋白约 {protein_g:.1f}g，可能不足以支撑恢复。"
            )
        if carb_g < 60:
            lines.append("- 日常活动量较高时，本餐优质碳水偏少，训练后补能可能不足。")
    elif activity_level == "LOW":
        if total_kcal > 0:
            lines.append("- 日常活动量偏低时，更需要警惕本餐热量和精制碳水带来的盈余。")
    elif activity_level == "MEDIUM" and total_kcal > 0 and protein_g < 25:
        lines.append("- 中等活动量下，本餐蛋白仍偏少，后续餐次建议补足优质蛋白。")

    return "\n".join(lines)


def _extract_history_basis_lines(user_memory: str) -> list[str]:
    lines: list[str] = []
    for raw_line in (user_memory or "").splitlines():
        line = raw_line.strip()
        if not line.startswith("-"):
            continue
        normalized = line.lstrip("- ")
        if normalized.startswith("最近完成记录里最常出现的餐次"):
            lines.append(normalized)
        elif normalized.startswith("历史建议高频主题"):
            lines.append(normalized)
        elif normalized.startswith("最近 ") and "已完成" in normalized:
            lines.append(normalized)
    return lines[:2]


def _build_personalization_basis(state: "AgentState", user_memory: str) -> str:
    user_context = state.get("user_context") or {}
    goal = _normalise_text(user_context.get("healthGoal") or "GENERAL_HEALTH").upper()
    daily_target = _as_float(user_context.get("dailyCalorieTarget"), 0.0)
    meal_type = _normalise_text(state.get("meal_type") or "")
    age = _as_float(user_context.get("age"), 0.0)
    height_cm = _as_float(user_context.get("heightCm"), 0.0)
    weight_kg = _as_float(user_context.get("weightKg"), 0.0)
    gender = _normalise_text(user_context.get("gender") or "").upper()
    activity_level = _normalise_text(user_context.get("activityLevel") or "").upper()
    restrictions = [
        _restriction_display(item)
        for item in (user_context.get("dietaryRestrictions") or [])
        if _normalise_text(item)
    ]

    lines: list[str] = []
    goal_line = f"目标：{_goal_display(goal)}"
    if daily_target > 0:
        goal_line += f"；每日热量目标 {daily_target:.0f} kcal"
        meal_bounds = _meal_ratio_bounds(daily_target, meal_type)
        if meal_bounds:
            lower, upper = meal_bounds
            goal_line += f"；{_meal_type_display(meal_type)}参考区间 {lower:.0f}-{upper:.0f} kcal"
    lines.append(goal_line)

    body_parts: list[str] = []
    if age > 0:
        body_parts.append(f"{age:.0f} 岁")
    if gender:
        body_parts.append(_gender_display(gender))
    if activity_level:
        body_parts.append(_activity_level_display(activity_level))
    if height_cm > 0 and weight_kg > 0:
        bmi = weight_kg / ((height_cm / 100.0) ** 2)
        body_parts.append(f"BMI 约 {bmi:.1f}")
    if body_parts:
        lines.append("身体情况：" + "，".join(body_parts))

    if age >= 45:
        lines.append("年龄因素：当前阶段更应关注蛋白质分配、纤维摄入和血糖稳定性。")
    if activity_level == "HIGH":
        lines.append("活动量因素：日常活动量较高，本次建议会更强调恢复所需的蛋白和优质碳水。")
    elif activity_level == "LOW":
        lines.append("活动量因素：日常活动量偏低，本次建议会更警惕热量盈余与精制碳水。")

    if restrictions:
        lines.append("饮食限制：" + "、".join(restrictions))

    lines.extend(_extract_history_basis_lines(user_memory))
    lines = [line for line in lines if line.strip()]
    if not lines:
        return ""
    return "个性化参考依据：\n" + "\n".join(f"- {line}" for line in lines[:5])


def _inject_personalization_basis(advice_report: str, personalization_basis: str) -> str:
    report = (advice_report or "").strip()
    basis = (personalization_basis or "").strip()
    if not basis:
        return report
    if report.startswith("个性化参考依据"):
        return report
    if not report:
        return basis
    return f"{basis}\n\n{report}"

ADVICE_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        (
            "你是一名注册营养师兼饮食教练，请输出中文、清晰、可执行的饮食建议。"
            "必须优先综合本餐营养画像、与用户目标的偏差、身体情况、饮食限制、最近饮食历史，再引用营养知识。"
            "避免医疗诊断语气，避免泛泛而谈，避免重复说‘注意均衡饮食’却不给具体动作。"
            "每个部分都尽量点名当前餐次中的具体食物、热量或营养指标；"
            "如果信息不足，要明确指出不确定性并给保守建议。"
            "若历史记录存在，请至少输出 1 条基于历史模式的提醒或调整。"
            "若提供了年龄、活动量、身高、体重、性别或BMI线索，请至少输出 1-2 条与这些因素相关的分析理由。"
            "输出严格按以下结构：\n"
            "1) 本餐评估：1-2句，必须同时指出一个优点和一个最需要调整的问题\n"
            "2) 风险点：2-3条，每条都要解释其与用户目标或限制的关系\n"
            "3) 下一餐建议：2-3条，必须具体到增减什么食物或份量\n"
            "4) 今日管理建议：2条，优先结合历史习惯或本餐所在餐次给出\n"
            "5) 免责声明：1句（仅供饮食管理参考）"
        ),
    ),
    (
        "human",
        (
            "## Meal Type\n{meal_type}\n\n"
            "## Current Meal Profile\n{current_meal_profile}\n\n"
            "## Goal Alignment\n{goal_alignment}\n\n"
            "## Body Condition\n{body_condition}\n\n"
            "## Restriction Check\n{restriction_check}\n\n"
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
        label = _item_label(item)
        conf = item.get("confidence")
        if conf is None:
            conf = item.get("confidence_score", 0.0)
        weight = item.get("estimated_weight_g")
        if weight is None:
            weight = item.get("weight_g")
        nutrition = _item_nutrition(item)
        weight_str = f"{_as_float(weight):.0f}g" if weight else "weight unknown"
        macro_text = (
            f"{nutrition['calories_kcal']:.0f} kcal, 蛋白 {nutrition['protein_g']:.1f}g, "
            f"脂肪 {nutrition['fat_g']:.1f}g, 碳水 {nutrition['carbs_g']:.1f}g"
        )
        count = int(item.get("instance_count") or 1)
        count_text = f"，{count} 份实例" if count > 1 else ""
        lines.append(f"- {label} ({macro_text}, {weight_str}, confidence: {_as_float(conf):.0%}{count_text})")
    return "\n".join(lines)


async def generate_advice(state: "AgentState") -> dict:
    """
    Call the LLM to generate a personalised dietary advice report.
    """
    logger.info("Generating dietary advice for task_id=%s", state["task_id"])

    segmentation_summary = _build_segmentation_summary(state.get("segmentation_result"))
    current_meal_profile = _build_current_meal_profile(state)
    goal_alignment = _build_goal_alignment(state)
    body_condition = _build_body_condition_summary(state)
    restriction_check = _build_restriction_check(state)
    rag_context = _clip_context(
        state.get("rag_context") or "Not available.",
        int(_settings.llm_context_char_limit),
    )
    user_memory = _clip_context(
        state.get("user_memory") or "No history available.",
        int(_settings.llm_context_char_limit),
    )
    personalization_basis = _build_personalization_basis(
        state,
        state.get("user_memory") or "",
    )
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
        return {
            "advice_report": _inject_personalization_basis(fallback, personalization_basis),
            "workflow_trace": workflow_trace,
        }

    provider, api_key, base_url, model = _resolve_llm_config()

    if not api_key:
        advice_report = _build_rule_based_advice(state, f"{provider} 配置缺失")
        workflow_trace.append(
            f"generate_advice: LLM unavailable ({provider}), rule-based advice generated"
        )
        return {
            "advice_report": _inject_personalization_basis(advice_report, personalization_basis),
            "workflow_trace": workflow_trace,
        }

    try:
        started_at = time.perf_counter()
        llm = ChatOpenAI(
            model=model,
            temperature=_resolve_llm_temperature(provider, model),
            api_key=api_key,
            base_url=base_url or None,
            timeout=_resolve_llm_timeout_seconds(provider, model),
            max_tokens=int(_settings.llm_max_output_tokens),
        )
        chain = ADVICE_PROMPT | llm
        response = await chain.ainvoke({
            "meal_type": _meal_type_display(_normalise_text(state.get("meal_type") or "")),
            "current_meal_profile": current_meal_profile,
            "goal_alignment": goal_alignment,
            "body_condition": body_condition,
            "restriction_check": restriction_check,
            "segmentation_summary": segmentation_summary,
            "rag_context": rag_context,
            "user_memory": user_memory,
            "user_context": user_context_str,
        })
        advice_report = str(response.content or "").strip()
        if not advice_report:
            raise ValueError("LLM returned empty advice content")
        elapsed_ms = (time.perf_counter() - started_at) * 1000.0
        workflow_trace.append(
            "generate_advice: FULL workflow advice generated successfully "
            f"(provider={provider}, model={model}, elapsed_ms={elapsed_ms:.0f})"
        )
    except Exception as exc:
        logger.error("LLM advice generation failed: %s", exc)
        advice_report = _build_rule_based_advice(state, f"{provider} 调用失败")
        workflow_trace.append(
            f"generate_advice: LLM call failed ({provider}), fallback rule advice generated"
        )

    advice_report = _inject_personalization_basis(advice_report, personalization_basis)
    return {"advice_report": advice_report, "workflow_trace": workflow_trace}
