"""
Inference REST router.

POST /v1/segment  – download image from OSS URL, run Swin-based segmentation,
                    return structured results.
"""

from __future__ import annotations

import base64
import binascii
import io
import logging

import httpx
import numpy as np
from fastapi import APIRouter, HTTPException
from PIL import Image

from app.models import SegmentationRequest, SegmentationResponse, FoodItem
from app.inference import run_inference

router = APIRouter()
logger = logging.getLogger(__name__)

_DOWNLOAD_TIMEOUT = httpx.Timeout(20.0, connect=5.0, read=20.0, write=20.0)
_DOWNLOAD_ATTEMPTS = 3


async def _resolve_image_bytes(request: SegmentationRequest) -> bytes:
    if request.image_base64:
        try:
            return base64.b64decode(request.image_base64, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise HTTPException(status_code=422, detail=f"Invalid image_base64 payload: {exc}") from exc

    last_exc: httpx.HTTPError | None = None
    for attempt in range(1, _DOWNLOAD_ATTEMPTS + 1):
        try:
            async with httpx.AsyncClient(timeout=_DOWNLOAD_TIMEOUT) as client:
                resp = await client.get(str(request.image_url))
                resp.raise_for_status()
                return resp.content
        except httpx.HTTPError as exc:
            last_exc = exc
            logger.warning(
                "Failed to fetch analysis image for task_id=%s attempt %d/%d: %s",
                request.task_id,
                attempt,
                _DOWNLOAD_ATTEMPTS,
                exc,
            )

    raise HTTPException(
        status_code=502,
        detail=f"Failed to fetch image after {_DOWNLOAD_ATTEMPTS} attempts: {last_exc}",
    ) from last_exc


@router.post("/segment", response_model=SegmentationResponse)
async def segment_meal_image(request: SegmentationRequest) -> SegmentationResponse:
    """
    Download the meal image from the provided pre-signed URL and run
    Swin Transformer food-instance segmentation.
    """
    # 1. Resolve image bytes from the inline payload first, then from OSS URL.
    image_bytes = await _resolve_image_bytes(request)

    # 2. Decode to numpy array – cap the long side at 1024 px BEFORE converting
    #    to numpy to avoid ballooning a 20 MB JPEG into hundreds of MB of RAM.
    #    The model input is 224×224 anyway, so nothing is lost.
    MAX_SIDE = 1024
    try:
        pil_img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        if pil_img.width > MAX_SIDE or pil_img.height > MAX_SIDE:
            pil_img.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
        image_array = np.array(pil_img)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Invalid image data: {exc}") from exc

    # 3. Run inference
    raw_detections, inference_ms, segmentation_preview_png_base64, model_version = run_inference(
        image_array=image_array,
        confidence_threshold=request.confidence_threshold,
    )

    # 4. Build response
    food_items = [FoodItem(**det) for det in raw_detections]
    total_calories = sum(
        (item.nutrition.calories_kcal if item.nutrition else 0.0) for item in food_items
    )

    return SegmentationResponse(
        task_id=request.task_id,
        image_url=str(request.image_url) if request.image_url else f"inline://{request.task_id}",
        detected_items=food_items,
        total_calories_kcal=total_calories,
        segmentation_preview_png_base64=segmentation_preview_png_base64,
        inference_time_ms=round(inference_ms, 2),
        model_version=model_version,
    )
