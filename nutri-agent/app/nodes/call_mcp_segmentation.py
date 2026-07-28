"""
Node: call_mcp_segmentation

Calls the nutri-ai-mcp segmentation service to obtain food-instance results.
"""

from __future__ import annotations

import asyncio
import base64
import importlib.util
from io import BytesIO
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import urlparse

import httpx
import numpy as np
from PIL import Image
from pydantic_settings import BaseSettings

if TYPE_CHECKING:
    from app.graph import AgentState
else:
    AgentState = dict

logger = logging.getLogger(__name__)


class McpSettings(BaseSettings):
    mcp_server_url: str = "http://127.0.0.1:18001"
    mcp_project_dir: str = str(Path(__file__).resolve().parents[3] / "nutri-ai-mcp")
    mcp_checkpoint: str = str(
        Path(__file__).resolve().parents[3]
        / "nutri-ai-mcp/weights_by_category/foodseg103/stage7s1/stage7s1_tiny_img512_mask135_cls095_phaseA_12ep/best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth"
    )
    mcp_input_size: str = "512"

    class Config:
        env_prefix = "NUTRI_"


_settings = McpSettings()


def _as_float(value: object, default: float = 0.0) -> float:
    try:
        return float(value)  # type: ignore[arg-type]
    except Exception:
        return default


def _aggregate_detected_items_by_class(detected_instances: list[dict]) -> list[dict]:
    grouped: dict[str, dict] = {}
    for item in detected_instances:
        class_id = item.get("class_id")
        class_name = str(item.get("class_name") or item.get("label") or "unknown")
        key = f"{class_id}|{class_name.lower()}"

        nutrition = item.get("nutrition") or {}
        if key not in grouped:
            grouped[key] = {
                "class_id": class_id,
                "class_name": class_name,
                "display_name": item.get("display_name") or class_name,
                "label": item.get("label") or class_name,
                "confidence": _as_float(item.get("confidence"), 0.0),
                "estimated_weight_g": _as_float(item.get("estimated_weight_g"), 0.0),
                "nutrition": {
                    "calories_kcal": _as_float(nutrition.get("calories_kcal"), 0.0),
                    "protein_g": _as_float(nutrition.get("protein_g"), 0.0),
                    "fat_g": _as_float(nutrition.get("fat_g"), 0.0),
                    "carbs_g": _as_float(nutrition.get("carbs_g"), 0.0),
                    "fiber_g": _as_float(nutrition.get("fiber_g"), 0.0),
                },
                "instance_count": 1,
            }
            continue

        target = grouped[key]
        target["instance_count"] = int(target.get("instance_count", 1)) + 1
        target["confidence"] = max(_as_float(target.get("confidence"), 0.0), _as_float(item.get("confidence"), 0.0))
        target["estimated_weight_g"] = _as_float(target.get("estimated_weight_g"), 0.0) + _as_float(item.get("estimated_weight_g"), 0.0)
        target_nutrition = target.get("nutrition") or {}
        target_nutrition["calories_kcal"] = _as_float(target_nutrition.get("calories_kcal"), 0.0) + _as_float(nutrition.get("calories_kcal"), 0.0)
        target_nutrition["protein_g"] = _as_float(target_nutrition.get("protein_g"), 0.0) + _as_float(nutrition.get("protein_g"), 0.0)
        target_nutrition["fat_g"] = _as_float(target_nutrition.get("fat_g"), 0.0) + _as_float(nutrition.get("fat_g"), 0.0)
        target_nutrition["carbs_g"] = _as_float(target_nutrition.get("carbs_g"), 0.0) + _as_float(nutrition.get("carbs_g"), 0.0)
        target_nutrition["fiber_g"] = _as_float(target_nutrition.get("fiber_g"), 0.0) + _as_float(nutrition.get("fiber_g"), 0.0)
        target["nutrition"] = target_nutrition

    grouped_items = list(grouped.values())
    grouped_items.sort(
        key=lambda x: (
            _as_float((x.get("nutrition") or {}).get("calories_kcal"), 0.0),
            _as_float(x.get("confidence"), 0.0),
        ),
        reverse=True,
    )
    return grouped_items


def _is_local_mcp_url() -> bool:
    url = _settings.mcp_server_url.lower()
    return "localhost" in url or "127.0.0.1" in url


def _looks_connection_error(exc: Exception) -> bool:
    if isinstance(exc, (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout)):
        return True
    msg = str(exc).lower()
    return "connection" in msg or "connect" in msg or "refused" in msg


def _looks_retryable_http_error(exc: Exception) -> bool:
    if isinstance(exc, httpx.HTTPStatusError) and exc.response is not None:
        return exc.response.status_code >= 500
    msg = str(exc).lower()
    return any(code in msg for code in ("502", "503", "504"))


async def _is_mcp_healthy() -> bool:
    try:
        async with httpx.AsyncClient(timeout=3.0, trust_env=False) as client:
            resp = await client.get(f"{_settings.mcp_server_url}/health")
            return resp.status_code == 200
    except Exception:
        return False


def _spawn_local_mcp_server() -> bool:
    project_dir = Path(_settings.mcp_project_dir).resolve()
    if not project_dir.exists():
        logger.error("Local segmentation project dir not found: %s", project_dir)
        return False

    parsed = urlparse(_settings.mcp_server_url)
    port = parsed.port or (443 if parsed.scheme == "https" else 80)

    env = os.environ.copy()
    if _settings.mcp_checkpoint:
        env.setdefault("NUTRI_SEG_CHECKPOINT", _settings.mcp_checkpoint)
    env.setdefault("NUTRI_SEG_INPUT_SIZE", _settings.mcp_input_size)

    cmd = [
        sys.executable,
        "-m",
        "uvicorn",
        "main:app",
        "--host",
        "0.0.0.0",
        "--port",
        str(port),
    ]

    popen_kwargs = {
        "cwd": str(project_dir),
        "env": env,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
    }
    if os.name == "nt":
        popen_kwargs["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP

    try:
        subprocess.Popen(cmd, **popen_kwargs)
        return True
    except Exception as exc:
        logger.error("Failed to spawn local segmentation server: %s", exc)
        return False


async def _ensure_mcp_available() -> bool:
    if await _is_mcp_healthy():
        return True
    if not _is_local_mcp_url():
        return False
    if not _spawn_local_mcp_server():
        return False

    for _ in range(20):
        await asyncio.sleep(0.8)
        if await _is_mcp_healthy():
            return True
    return False


def _load_local_inference_runner(project_dir: Path):
    inference_file = project_dir / "app" / "inference" / "__init__.py"
    if not inference_file.exists():
        raise FileNotFoundError(f"Local inference module not found: {inference_file}")

    module_name = "nutri_ai_local_inference"
    spec = importlib.util.spec_from_file_location(module_name, str(inference_file))
    if spec is None or spec.loader is None:
        raise RuntimeError("Failed to create module spec for local inference")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    run_inference = getattr(module, "run_inference", None)
    if run_inference is None:
        raise RuntimeError("run_inference not found in local inference module")
    return run_inference


async def _run_local_segmentation_fallback(
    task_id: str,
    image_url: str,
    image_base64: str | None,
    confidence_threshold: float,
) -> dict:
    project_dir = Path(_settings.mcp_project_dir).resolve()
    if _settings.mcp_checkpoint:
        os.environ["NUTRI_SEG_CHECKPOINT"] = _settings.mcp_checkpoint
    if _settings.mcp_input_size:
        os.environ["NUTRI_SEG_INPUT_SIZE"] = str(_settings.mcp_input_size)
    run_inference = _load_local_inference_runner(project_dir)

    if image_base64:
        image_bytes = base64.b64decode(image_base64)
    else:
        async with httpx.AsyncClient(timeout=30.0, trust_env=False) as client:
            img_resp = await client.get(image_url)
            img_resp.raise_for_status()
            image_bytes = img_resp.content

    img = Image.open(BytesIO(image_bytes)).convert("RGB")
    image_array = np.array(img)
    detected_items, inference_ms, preview_b64, model_version = run_inference(
        image_array,
        float(confidence_threshold),
    )

    total_calories = 0.0
    for item in detected_items:
        nutrition = item.get("nutrition") or {}
        try:
            total_calories += float(nutrition.get("calories_kcal", 0.0))
        except Exception:
            pass

    return {
        "task_id": task_id,
        "detected_items": detected_items,
        "inference_time_ms": float(inference_ms),
        "total_calories_kcal": round(total_calories, 1),
        "segmentation_preview_png_base64": preview_b64,
        "model_version": str(model_version),
    }


async def call_mcp_segmentation(state: "AgentState") -> dict:
    """
    Invoke the segmentation endpoint on nutri-ai-mcp.

    The service also exposes an MCP tool, but the production path uses the
    REST endpoint because it supports inline base64 images and simpler retries.
    """
    task_id: str = state["task_id"]
    image_url: str = state["image_url"]
    image_base64: str | None = state.get("image_base64")
    user_context: dict = state.get("user_context") or {}
    confidence_threshold: float = user_context.get("confidence_threshold", 0.5)
    workflow_trace = list(state.get("workflow_trace") or [])

    logger.info("Calling segmentation service for task_id=%s", task_id)

    payload = {
        "task_id": task_id,
        "confidence_threshold": confidence_threshold,
    }
    if image_url:
        payload["image_url"] = image_url
    if image_base64:
        payload["image_base64"] = image_base64

    segmentation_result = None
    last_exc: Exception | None = None
    healed = False

    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=60.0, trust_env=False) as client:
                resp = await client.post(
                    f"{_settings.mcp_server_url}/v1/segment",
                    json=payload,
                    headers={"Content-Type": "application/json"},
                )
                resp.raise_for_status()
                content = resp.json()
                segmentation_result = {
                    "task_id": content.get("task_id", task_id),
                    "detected_items": content.get("detected_items", []),
                    "inference_time_ms": content.get("inference_time_ms", 0.0),
                    "total_calories_kcal": content.get("total_calories_kcal", 0.0),
                    "segmentation_preview_png_base64": content.get("segmentation_preview_png_base64"),
                    "model_version": content.get("model_version", "unknown"),
                }
                break
        except Exception as exc:
            last_exc = exc
            if attempt == 0 and _looks_connection_error(exc):
                logger.warning("Segmentation service unreachable, attempting self-heal start ...")
                healed = await _ensure_mcp_available()
                if healed:
                    logger.warning("Segmentation service self-heal succeeded; retrying once")
                    continue
            break

    if segmentation_result is None:
        exc = last_exc or RuntimeError("Segmentation service unknown failure")
        used_local_fallback = False
        if _looks_connection_error(exc) or _looks_retryable_http_error(exc):
            try:
                logger.warning("Segmentation service failed; trying direct local inference fallback")
                segmentation_result = await _run_local_segmentation_fallback(
                    task_id=task_id,
                    image_url=image_url,
                    image_base64=image_base64,
                    confidence_threshold=confidence_threshold,
                )
                used_local_fallback = True
            except Exception as local_exc:
                logger.error("Local inference fallback failed: %s", local_exc)
                exc = local_exc

        if used_local_fallback:
            workflow_trace.append("call_mcp_segmentation: 分割服务异常，已切换本地推理兜底并恢复")
        else:
            logger.error("Segmentation call failed: %s", exc)
            err = str(exc)
            if "502" in err:
                err = "分割服务网关异常（502），已尝试兜底但未恢复，请检查推理服务日志"
            elif "Connection" in err or "connect" in err:
                err = "分割服务不可达，请检查 nutri-ai-mcp 服务状态"
            segmentation_result = {"error": err, "detected_items": []}
    elif healed:
        workflow_trace.append("call_mcp_segmentation: 分割服务异常后已自动拉起并恢复")

    detected_instances = list(segmentation_result.get("detected_items", []) or [])
    grouped_items = _aggregate_detected_items_by_class(detected_instances)
    segmentation_result["detected_instances"] = detected_instances
    segmentation_result["detected_items"] = grouped_items

    labels: list[str] = []
    for item in detected_instances:
        label = (
            item.get("label")
            or item.get("class_name")
            or item.get("display_name")
            or ""
        )
        if label:
            labels.append(str(label))

    workflow_mode = "FULL" if labels else "CALORIE_ONLY"
    if labels:
        workflow_trace.append(
            f"call_mcp_segmentation: 已识别 {len(labels)} 个类别，进入完整分析流程"
        )
    else:
        workflow_trace.append(
            "call_mcp_segmentation: 未识别到有效类别或分割失败，切换到仅热量估算流程"
        )

    return {
        "segmentation_result": segmentation_result,
        "detected_labels": labels,
        "workflow_mode": workflow_mode,
        "workflow_trace": workflow_trace,
    }
