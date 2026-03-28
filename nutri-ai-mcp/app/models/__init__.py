"""Pydantic request / response models for the inference API."""

from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel, HttpUrl, Field


class SegmentationRequest(BaseModel):
    """Input payload for the food segmentation endpoint."""

    image_url: HttpUrl = Field(
        ...,
        description="Pre-signed OSS/MinIO URL of the meal image to analyse.",
    )
    task_id: str = Field(
        ...,
        description="UUID of the originating analysis task (for traceability).",
    )
    confidence_threshold: float = Field(
        default=0.5,
        ge=0.0,
        le=1.0,
        description="Minimum confidence score for a detection to be included.",
    )


class FoodItem(BaseModel):
    """A single detected food instance."""

    label: str = Field(..., description="Food class label (e.g. 'rice', 'broccoli').")
    confidence: float = Field(..., ge=0.0, le=1.0)
    bbox: List[float] = Field(
        ...,
        min_length=4,
        max_length=4,
        description="Bounding box [x_min, y_min, x_max, y_max] in pixel coordinates.",
    )
    mask_rle: Optional[str] = Field(
        None,
        description="Run-length-encoded binary mask (COCO RLE format).",
    )
    estimated_weight_g: Optional[float] = Field(
        None,
        description="Estimated portion weight in grams (model-predicted).",
    )
    nutrition: Optional[NutritionInfo] = None


class NutritionInfo(BaseModel):
    """Per-item estimated nutrition (per 100 g, scaled by estimated_weight_g)."""

    calories_kcal: float
    protein_g: float
    fat_g: float
    carbs_g: float
    fiber_g: Optional[float] = None


# Resolve forward references
FoodItem.model_rebuild()


class SegmentationResponse(BaseModel):
    """Full response from the segmentation endpoint."""

    task_id: str
    image_url: str
    detected_items: List[FoodItem] = Field(default_factory=list)
    total_calories_kcal: float = Field(
        default=0.0,
        description="Sum of estimated calories across all detected items.",
    )
    inference_time_ms: float = Field(
        ...,
        description="End-to-end inference latency in milliseconds.",
    )
    model_version: str = Field(
        default="swin-t-bifpn-ca-v1",
        description="Identifier of the model checkpoint used.",
    )
