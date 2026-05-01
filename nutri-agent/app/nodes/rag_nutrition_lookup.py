"""
Node: rag_nutrition_lookup

Retrieves relevant nutritional knowledge from ChromaDB and local KB based on detected food items.

- If Chroma is available, queries the nutrition_knowledge collection for each detected label.
- If not, falls back to a local JSON/DICT knowledge base (可扩展为 nutrition_kb.json）。
- All results are concatenated for LLM context.
"""

from __future__ import annotations

import asyncio
import logging
import json
import os
from typing import TYPE_CHECKING, List

from pydantic_settings import BaseSettings, SettingsConfigDict

from app.chroma_http import query_text_records, upsert_text_records

if TYPE_CHECKING:
    from app.graph import AgentState
else:
    AgentState = dict

logger = logging.getLogger(__name__)


class ChromaRagSettings(BaseSettings):
    chroma_host: str = "localhost"
    chroma_port: int = 8100
    chroma_nutrition_collection: str = "nutrition_knowledge"
    chroma_enabled: bool = True
    chroma_nutrition_results: int = 5
    chroma_nutrition_bootstrap_on_startup: bool = True
    local_kb_path: str = os.path.join(os.path.dirname(__file__), "nutrition_kb.json")

    model_config = SettingsConfigDict(
        env_prefix="NUTRI_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


_settings = ChromaRagSettings()
_NUTRITION_BOOTSTRAPPED = False
_NUTRITION_BOOTSTRAP_LOCK = asyncio.Lock()


# ── Local fallback nutrition KB ───────────────────────────────────────────────

_DEFAULT_KB = {
    "rice": "米饭是碳水化合物的主要来源，建议适量摄入，搭配蔬菜和蛋白质。",
    "noodles": "面条富含碳水，建议搭配蛋白质和蔬菜，避免高油高盐。",
    "beef": "牛肉蛋白质丰富，注意脂肪摄入，优先选择瘦肉。",
    "chicken": "鸡肉为优质蛋白，建议清淡烹饪，去皮食用更健康。",
    "fish": "鱼类富含优质蛋白和Omega-3，建议清蒸或少油烹饪。",
    "egg": "鸡蛋营养全面，适量摄入有益健康。",
    "tofu": "豆腐为植物蛋白来源，低脂肪，适合素食者。",
    "broccoli": "西兰花富含纤维和维生素C，建议多样化搭配。",
    "tomato": "番茄含有丰富的番茄红素和维生素C。",
    "potato": "土豆富含淀粉，建议蒸煮为主，避免油炸。",
    "lettuce": "生菜热量低，富含纤维，适合减脂期食用。",
    "carrot": "胡萝卜含有β-胡萝卜素，有益视力健康。",
    "steak": "牛排蛋白高，脂肪含量视部位而异，适量为宜。",
    "pork": "猪肉脂肪较高，建议优先选择瘦肉部位。",
    "eggplant": "茄子富含纤维，吸油性强，建议少油烹饪。",
    "cabbage": "卷心菜富含维生素K和C，热量低。",
    "mushroom": "蘑菇蛋白质含量高，低热量，适合多种烹饪方式。",
    "salad": "沙拉富含多种维生素和纤维，注意酱料热量。",
    "pizza": "披萨能量密度高，建议控制分量并搭配蔬菜。",
    "milk": "牛奶富含钙和蛋白质，适量饮用有益骨骼健康。",
    "bread": "面包为碳水来源，注意糖分和油脂含量。",
    "shrimp": "虾富含蛋白质和微量元素，适量食用有益健康。",
    "apple": "苹果富含膳食纤维和维生素C，适合日常食用。",
    "banana": "香蕉富含钾，有助于维持电解质平衡。",
    "other": "建议主食适量、蛋白充足、蔬菜多样，避免高油高糖。"
}


def _load_local_kb() -> dict:
    path = _settings.local_kb_path
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as exc:
            logger.warning("Failed to load local nutrition_kb.json: %s", exc)
    return _DEFAULT_KB


def _build_nutrition_documents(kb: dict) -> List[dict]:
    docs: List[dict] = []
    for key, text in kb.items():
        label = str(key).strip().lower()
        if not label:
            continue
        document = f"{label}: {str(text).strip()}"
        docs.append(
            {
                "id": f"nutrition:{label}",
                "document": document,
                "metadata": {
                    "domain": "nutrition",
                    "label": label,
                    "lang": "zh-CN",
                },
            }
        )
    return docs


async def _bootstrap_nutrition_collection_if_needed() -> int:
    global _NUTRITION_BOOTSTRAPPED
    if not _settings.chroma_enabled or not _settings.chroma_nutrition_bootstrap_on_startup:
        return 0
    if _NUTRITION_BOOTSTRAPPED:
        return 0

    async with _NUTRITION_BOOTSTRAP_LOCK:
        if _NUTRITION_BOOTSTRAPPED:
            return 0
        kb = _load_local_kb()
        docs = _build_nutrition_documents(kb)
        upserted = await upsert_text_records(
            _settings.chroma_nutrition_collection,
            docs,
            metadata={"domain": "nutrition"},
        )
        _NUTRITION_BOOTSTRAPPED = True
        return upserted


async def rag_nutrition_lookup(state: "AgentState") -> dict:
    labels: List[str] = list(state.get("detected_labels") or [])
    workflow_trace = list(state.get("workflow_trace") or [])

    if not labels:
        workflow_trace.append("rag_nutrition_lookup: 未识别到类别，已跳过营养知识检索")
        return {"rag_context": "未识别到食物类别，暂无营养知识上下文。", "workflow_trace": workflow_trace}

    rag_contexts: List[str] = []
    sources: List[str] = []

    # Try Chroma first
    chroma_hit = False
    if _settings.chroma_enabled and labels:
        try:
            bootstrapped = await _bootstrap_nutrition_collection_if_needed()
            if bootstrapped > 0:
                sources.append(f"nutrition-kb init {bootstrapped} 条")
            query = "Nutritional information and health benefits of: " + ", ".join(labels)
            results = await query_text_records(
                _settings.chroma_nutrition_collection,
                query,
                n_results=_settings.chroma_nutrition_results,
                metadata={"domain": "nutrition"},
            )
            documents: List[str] = results.get("documents", [[]])[0]
            if documents:
                rag_contexts.extend([f"- {doc}" for doc in documents if doc])
                sources.append(f"Chroma {len(documents)} 条")
                chroma_hit = True
        except Exception as exc:
            logger.warning("Chroma nutrition lookup failed: %s", exc)

    # Fallback: local KB
    if not chroma_hit:
        kb = _load_local_kb()
        for label in labels:
            key = str(label).strip().lower()
            context = kb.get(key) or kb.get("other")
            rag_contexts.append(f"- {label}: {context}")
        sources.append(f"本地KB {len(labels)} 条")

    rag_context = "\n".join(rag_contexts) if rag_contexts else "未检索到营养知识。"
    if sources:
        workflow_trace.append(
            "rag_nutrition_lookup: retrieved "
            f"{len(rag_contexts)} nutrition passages for {len(labels)} labels "
            "(" + " + ".join(sources) + ")"
        )
    else:
        workflow_trace.append("rag_nutrition_lookup: nutrition KB unavailable, fallback context used")

    return {"rag_context": rag_context, "workflow_trace": workflow_trace}
