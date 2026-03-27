"""
Inference REST router.

POST /v1/segment  – download image from OSS URL, run Swin-based segmentation,
                    return structured results.
"""

from __future__ import annotations

import httpx
import numpy as np
from fastapi import APIRouter, HTTPException
from PIL import Image
import io

from app.models import SegmentationRequest, SegmentationResponse, FoodItem
from app.inference import run_inference

router = APIRouter()


@router.post("/segment", response_model=SegmentationResponse)
async def segment_meal_image(request: SegmentationRequest) -> SegmentationResponse:
    """
    Download the meal image from the provided pre-signed URL and run
    Swin Transformer food-instance segmentation.
    """
    # 1. Download image from OSS
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(str(request.image_url))
            resp.raise_for_status()
            image_bytes = resp.content
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Failed to fetch image: {exc}") from exc

    # 2. Decode to numpy array
    try:
        pil_img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        image_array = np.array(pil_img)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Invalid image data: {exc}") from exc

    # 3. Run inference
    raw_detections, inference_ms = run_inference(
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
        image_url=str(request.image_url),
        detected_items=food_items,
        total_calories_kcal=total_calories,
        inference_time_ms=round(inference_ms, 2),
    )
