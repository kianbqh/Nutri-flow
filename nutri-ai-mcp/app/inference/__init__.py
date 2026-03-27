"""
Swin Transformer + BiFPN + Coordinate Attention inference pipeline.

Architecture highlights
-----------------------
* Backbone  : Swin-Tiny (timm) – hierarchical shifted-window attention.
* Neck      : BiFPN – bi-directional feature pyramid for multi-scale fusion.
* Head      : Mask R-CNN style instance-segmentation head.
* Attention : Coordinate Attention injected into BiFPN lateral connections.

This module is intentionally decoupled from FastAPI / MCP layers so that it
can be unit-tested independently and swapped out for a heavier model variant.
"""

from __future__ import annotations

import time
import logging
from typing import List, Tuple

import numpy as np
import torch
import torch.nn as nn

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Coordinate Attention (CA) block
# Reference: Hou et al., "Coordinate Attention for Efficient Mobile Network Design"
# ─────────────────────────────────────────────────────────────────────────────
class CoordinateAttention(nn.Module):
    """Injects spatial coordinate information into channel attention."""

    def __init__(self, in_channels: int, reduction: int = 32) -> None:
        super().__init__()
        mid = max(8, in_channels // reduction)
        self.pool_h = nn.AdaptiveAvgPool2d((None, 1))
        self.pool_w = nn.AdaptiveAvgPool2d((1, None))
        self.conv1 = nn.Conv2d(in_channels, mid, kernel_size=1, bias=False)
        self.bn1 = nn.BatchNorm2d(mid)
        self.act = nn.Hardswish()
        self.conv_h = nn.Conv2d(mid, in_channels, kernel_size=1, bias=False)
        self.conv_w = nn.Conv2d(mid, in_channels, kernel_size=1, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        n, c, h, w = x.shape
        x_h = self.pool_h(x)          # (N, C, H, 1)
        x_w = self.pool_w(x).permute(0, 1, 3, 2)  # (N, C, W, 1)
        y = torch.cat([x_h, x_w], dim=2)           # (N, C, H+W, 1)
        y = self.act(self.bn1(self.conv1(y)))
        x_h, x_w = torch.split(y, [h, w], dim=2)
        x_w = x_w.permute(0, 1, 3, 2)
        a_h = torch.sigmoid(self.conv_h(x_h))
        a_w = torch.sigmoid(self.conv_w(x_w))
        return x * a_h * a_w


# ─────────────────────────────────────────────────────────────────────────────
# BiFPN node (single level fusion)
# ─────────────────────────────────────────────────────────────────────────────
class BiFPNNode(nn.Module):
    """Weighted bi-directional feature fusion for two input feature maps."""

    def __init__(self, channels: int) -> None:
        super().__init__()
        self.w1 = nn.Parameter(torch.ones(2, dtype=torch.float32))
        self.w2 = nn.Parameter(torch.ones(3, dtype=torch.float32))
        self.conv = nn.Sequential(
            nn.Conv2d(channels, channels, 3, padding=1, groups=channels, bias=False),
            nn.Conv2d(channels, channels, 1, bias=False),
            nn.BatchNorm2d(channels),
            nn.SiLU(),
        )
        self.ca = CoordinateAttention(channels)

    def forward(
        self,
        feat_in: torch.Tensor,
        feat_td: torch.Tensor,
        feat_out: torch.Tensor | None = None,
    ) -> torch.Tensor:
        eps = 1e-4
        if feat_out is None:
            w = torch.relu(self.w1)
            out = (w[0] * feat_in + w[1] * feat_td) / (w.sum() + eps)
        else:
            w = torch.relu(self.w2)
            out = (w[0] * feat_in + w[1] * feat_td + w[2] * feat_out) / (w.sum() + eps)
        return self.ca(self.conv(out))


# ─────────────────────────────────────────────────────────────────────────────
# Full segmentation model
# ─────────────────────────────────────────────────────────────────────────────
class NutriSegModel(nn.Module):
    """
    Swin-Tiny backbone + BiFPN neck + lightweight mask head.

    In production, load pretrained weights via:
        model.load_state_dict(torch.load("weights/nutri_seg_v1.pth"))
    """

    def __init__(self, num_classes: int = 80) -> None:
        super().__init__()
        try:
            import timm
            self.backbone = timm.create_model(
                "swin_tiny_patch4_window7_224",
                pretrained=False,
                features_only=True,
                out_indices=(1, 2, 3),  # C2, C3, C4
            )
            feature_channels = self.backbone.feature_info.channels()
        except ImportError:
            logger.warning("timm not installed – using placeholder backbone")
            self.backbone = None
            feature_channels = [192, 384, 768]

        fpn_channels = 256
        self.lateral_convs = nn.ModuleList([
            nn.Conv2d(c, fpn_channels, 1) for c in feature_channels
        ])
        self.bifpn_nodes = nn.ModuleList([BiFPNNode(fpn_channels) for _ in range(3)])
        self.cls_head = nn.Conv2d(fpn_channels, num_classes, 1)
        self.mask_head = nn.Sequential(
            nn.Conv2d(fpn_channels, 128, 3, padding=1),
            nn.ReLU(),
            nn.Conv2d(128, 1, 1),
        )

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        if self.backbone is not None:
            feats = self.backbone(x)
        else:
            # Placeholder: produce random feature maps for scaffolding tests
            feats = [torch.randn(x.size(0), c, x.size(2) // s, x.size(3) // s)
                     for c, s in zip([192, 384, 768], [8, 16, 32])]

        laterals = [conv(f) for conv, f in zip(self.lateral_convs, feats)]
        # Top-down pass
        td = laterals[-1]
        fused = [td]
        for i in range(len(laterals) - 2, -1, -1):
            td_up = nn.functional.interpolate(td, size=laterals[i].shape[-2:], mode="nearest")
            td = self.bifpn_nodes[i](laterals[i], td_up)
            fused.insert(0, td)

        cls_logits = self.cls_head(fused[0])
        mask_logits = self.mask_head(fused[0])
        return cls_logits, mask_logits


# ─────────────────────────────────────────────────────────────────────────────
# Inference engine (singleton)
# ─────────────────────────────────────────────────────────────────────────────
_model: NutriSegModel | None = None


def get_model() -> NutriSegModel:
    """Return the singleton model (lazy initialisation)."""
    global _model
    if _model is None:
        logger.info("Initialising NutriSegModel...")
        _model = NutriSegModel(num_classes=80)
        _model.eval()
        logger.info("NutriSegModel ready (weights: random – load .pth for production)")
    return _model


def run_inference(
    image_array: np.ndarray,
    confidence_threshold: float = 0.5,
) -> Tuple[List[dict], float]:
    """
    Run food-segmentation inference on a pre-processed image array.

    Parameters
    ----------
    image_array:
        RGB image as uint8 numpy array shape (H, W, 3).
    confidence_threshold:
        Minimum score to include a detection.

    Returns
    -------
    detections:
        List of dicts with keys: label, confidence, bbox, mask_rle.
    inference_ms:
        Wall-clock inference time in milliseconds.
    """
    model = get_model()
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)

    # Preprocess: resize → normalise → batch
    from PIL import Image
    import torchvision.transforms.functional as TF

    pil_img = Image.fromarray(image_array).resize((224, 224))
    tensor = TF.to_tensor(pil_img).unsqueeze(0).to(device)
    mean = torch.tensor([0.485, 0.456, 0.406], device=device).view(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225], device=device).view(1, 3, 1, 1)
    tensor = (tensor - mean) / std

    t0 = time.perf_counter()
    with torch.no_grad():
        cls_logits, mask_logits = model(tensor)
    inference_ms = (time.perf_counter() - t0) * 1000

    # Post-process: take top-k detections from the first spatial position (scaffold)
    probs = torch.softmax(cls_logits[0, :, 0, 0], dim=0).cpu().numpy()
    top_k = int((probs > confidence_threshold).sum())

    # COCO class names placeholder (first 10 for brevity)
    coco_names = [
        "background", "rice", "noodles", "chicken", "beef", "pork",
        "fish", "tofu", "broccoli", "carrot",
    ]

    detections = []
    for idx in np.argsort(probs)[::-1][:top_k]:
        score = float(probs[idx])
        if score < confidence_threshold:
            break
        label = coco_names[idx] if idx < len(coco_names) else f"class_{idx}"
        detections.append({
            "label": label,
            "confidence": round(score, 4),
            "bbox": [0.0, 0.0, 224.0, 224.0],  # placeholder full-image bbox
            "mask_rle": None,
            "estimated_weight_g": None,
        })

    return detections, inference_ms
