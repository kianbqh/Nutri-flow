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

import csv
import time
import logging
import base64
import io
import os
import re
from pathlib import Path
from typing import List, Tuple

import numpy as np
import cv2
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

    def __init__(self, num_classes: int = 104, input_size: int = 512) -> None:
        super().__init__()
        self.expected_input_size = int(input_size)
        try:
            import timm
            create_kwargs = {
                "pretrained": False,
                "features_only": True,
                "out_indices": (1, 2, 3),  # C2, C3, C4
            }
            try:
                self.backbone = timm.create_model(
                    "swin_tiny_patch4_window7_224",
                    img_size=self.expected_input_size,
                    **create_kwargs,
                )
            except TypeError:
                self.backbone = timm.create_model(
                    "swin_tiny_patch4_window7_224",
                    **create_kwargs,
                )

            backbone_img_size = getattr(self.backbone, "img_size", None)
            if backbone_img_size is not None:
                if isinstance(backbone_img_size, (tuple, list)) and len(backbone_img_size) >= 1:
                    self.expected_input_size = int(backbone_img_size[0])
                else:
                    self.expected_input_size = int(backbone_img_size)
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
        # Keep head names consistent with training checkpoints.
        self.cls_heads = nn.ModuleList([
            nn.Sequential(
                nn.Conv2d(fpn_channels, fpn_channels, 3, padding=1),
                nn.ReLU(),
                nn.Conv2d(fpn_channels, num_classes, 1),
            )
            for _ in range(3)
        ])
        self.mask_heads = nn.ModuleList([
            nn.Sequential(
                nn.Conv2d(fpn_channels, fpn_channels, 3, padding=1),
                nn.ReLU(),
                nn.Conv2d(fpn_channels, 1, 1),
            )
            for _ in range(3)
        ])

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        if self.backbone is not None:
            feats = self.backbone(x)
            # timm Swin features_only may return channel-last tensors (N, H, W, C).
            # Convert to channel-first so Conv2d lateral layers can consume them.
            fixed_feats = []
            for feat in feats:
                if feat.ndim == 4 and feat.shape[1] < feat.shape[-1]:
                    feat = feat.permute(0, 3, 1, 2).contiguous()
                fixed_feats.append(feat)
            feats = fixed_feats
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

        # Use the finest-scale head for current MVP post-processing.
        cls_logits = self.cls_heads[0](fused[0])
        mask_logits = self.mask_heads[0](fused[0])
        return cls_logits, mask_logits


# ─────────────────────────────────────────────────────────────────────────────
# Inference engine (singleton)
# ─────────────────────────────────────────────────────────────────────────────
_model: NutriSegModel | None = None
_model_version: str = "swin-t-bifpn-ca-v1-random-init"

try:
    from app.training.build_stage6_c1_mapping import FOODSEG103_CLASSES
except Exception:
    FOODSEG103_CLASSES = {0: "background"}


def _load_class_priors() -> dict[int, dict[str, float | str]]:
    priors: dict[int, dict[str, float | str]] = {}
    mapping_csv = (
        Path(__file__).resolve().parents[2]
        / "weights_by_category/foodseg103/stage6_c/food_class_to_nutrition.csv"
    )
    if mapping_csv.exists():
        try:
            with mapping_csv.open("r", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    class_id = int(row["class_id"])
                    priors[class_id] = {
                        "class_name": row["class_name"],
                        "kcal_100g": float(row["kcal_100g"]),
                        "default_portion_g": float(row["default_portion_g"]),
                        "density_group": row.get("density_group", "mixed"),
                    }
        except Exception as exc:
            logger.warning("Failed to load class prior CSV: %s", exc)

    if not priors:
        for class_id, class_name in FOODSEG103_CLASSES.items():
            priors[class_id] = {
                "class_name": class_name,
                "kcal_100g": 120.0,
                "default_portion_g": 100.0,
                "density_group": "mixed",
            }
    return priors


_CLASS_PRIORS = _load_class_priors()

_DISPLAY_NAME_ZH = {
    "background": "背景",
    "candy": "糖果",
    "egg tart": "蛋挞",
    "french fries": "炸薯条",
    "chocolate": "巧克力",
    "biscuit": "饼干",
    "popcorn": "爆米花",
    "pudding": "布丁",
    "ice cream": "冰淇淋",
    "cheese butter": "奶酪黄油",
    "cake": "蛋糕",
    "wine": "葡萄酒",
    "milkshake": "奶昔",
    "coffee": "咖啡",
    "juice": "果汁",
    "milk": "牛奶",
    "tea": "茶",
    "almond": "杏仁",
    "red beans": "红豆",
    "cashew": "腰果",
    "dried cranberries": "蔓越莓干",
    "soy": "黄豆",
    "walnut": "核桃",
    "peanut": "花生",
    "egg": "鸡蛋",
    "apple": "苹果",
    "date": "枣",
    "apricot": "杏子",
    "avocado": "牛油果",
    "banana": "香蕉",
    "strawberry": "草莓",
    "cherry": "樱桃",
    "blueberry": "蓝莓",
    "raspberry": "树莓",
    "mango": "芒果",
    "olives": "橄榄",
    "peach": "桃子",
    "lemon": "柠檬",
    "pear": "梨",
    "fig": "无花果",
    "pineapple": "菠萝",
    "grape": "葡萄",
    "kiwi": "猕猴桃",
    "melon": "甜瓜",
    "orange": "橙子",
    "watermelon": "西瓜",
    "steak": "牛排",
    "pork": "猪肉",
    "chicken duck": "鸡鸭肉",
    "sausage": "香肠",
    "fried meat": "炸肉",
    "lamb": "羊肉",
    "sauce": "酱料",
    "crab": "螃蟹",
    "fish": "鱼",
    "shellfish": "贝类",
    "shrimp": "虾",
    "soup": "汤",
    "bread": "面包",
    "corn": "玉米",
    "hamburg": "汉堡",
    "pizza": "披萨",
    "hanamaki baozi": "花卷包子",
    "wonton dumplings": "馄饨饺子",
    "pasta": "意面",
    "noodles": "面条",
    "rice": "米饭",
    "pie": "馅饼",
    "tofu": "豆腐",
    "eggplant": "茄子",
    "potato": "土豆",
    "garlic": "大蒜",
    "cauliflower": "菜花",
    "tomato": "番茄",
    "kelp": "海带",
    "seaweed": "海苔",
    "spring onion": "葱",
    "rape": "油菜",
    "ginger": "姜",
    "okra": "秋葵",
    "lettuce": "生菜",
    "pumpkin": "南瓜",
    "cucumber": "黄瓜",
    "white radish": "白萝卜",
    "carrot": "胡萝卜",
    "asparagus": "芦笋",
    "bamboo shoots": "竹笋",
    "broccoli": "西兰花",
    "celery stick": "芹菜",
    "cilantro mint": "香菜薄荷",
    "snow peas": "荷兰豆",
    "cabbage": "卷心菜",
    "bean sprouts": "豆芽",
    "onion": "洋葱",
    "pepper": "辣椒",
    "green beans": "四季豆",
    "french beans": "菜豆",
    "king oyster mushroom": "杏鲍菇",
    "shiitake": "香菇",
    "enoki mushroom": "金针菇",
    "oyster mushroom": "平菇",
    "white button mushroom": "白蘑菇",
    "salad": "沙拉",
    "other ingredients": "其他配料",
}


def _class_name(class_id: int) -> str:
    prior = _CLASS_PRIORS.get(class_id)
    if prior:
        return str(prior.get("class_name") or f"class_{class_id}")
    return FOODSEG103_CLASSES.get(class_id, f"class_{class_id}")


def _display_name_zh(class_id: int, class_name: str) -> str:
    key = class_name.strip().lower()
    if key in _DISPLAY_NAME_ZH:
        return _DISPLAY_NAME_ZH[key]
    # Unknown labels should still show the exact class name instead of numeric placeholders.
    return class_name


def _build_segmentation_preview_png_base64(
    input_image_224: np.ndarray,
    mask_binary_224: np.ndarray,
) -> str:
    """Render a red segmentation overlay preview and return PNG base64."""
    from PIL import Image

    base_img = Image.fromarray(input_image_224.astype(np.uint8)).convert("RGBA")
    overlay = np.zeros((mask_binary_224.shape[0], mask_binary_224.shape[1], 4), dtype=np.uint8)
    overlay[..., 0] = 255
    overlay[..., 3] = np.where(mask_binary_224, 110, 0).astype(np.uint8)
    overlay_img = Image.fromarray(overlay, mode="RGBA")
    blended = Image.alpha_composite(base_img, overlay_img).convert("RGB")

    buf = io.BytesIO()
    blended.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def _letterbox_to_square(image_array: np.ndarray, input_size: int) -> np.ndarray:
    """Resize with aspect ratio preserved and zero-pad to square input."""
    from PIL import Image

    src = Image.fromarray(image_array).convert("RGB")
    src_w, src_h = src.size
    if src_w <= 0 or src_h <= 0:
        return np.zeros((input_size, input_size, 3), dtype=np.uint8)

    scale = min(input_size / float(src_w), input_size / float(src_h))
    dst_w = max(1, int(round(src_w * scale)))
    dst_h = max(1, int(round(src_h * scale)))

    resized = src.resize((dst_w, dst_h), Image.LANCZOS)
    canvas = Image.new("RGB", (input_size, input_size), (0, 0, 0))
    off_x = (input_size - dst_w) // 2
    off_y = (input_size - dst_h) // 2
    canvas.paste(resized, (off_x, off_y))
    return np.array(canvas)


def _fallback_macro_100g(kcal_100g: float, density_group: str) -> dict[str, float]:
    ratios = {
        "protein": (0.45, 0.05, 0.50),
        "staple": (0.10, 0.75, 0.15),
        "vegetable": (0.25, 0.55, 0.20),
        "fruit": (0.05, 0.85, 0.10),
        "dessert": (0.05, 0.55, 0.40),
        "nut": (0.15, 0.15, 0.70),
        "liquid": (0.05, 0.90, 0.05),
        "condiment": (0.05, 0.45, 0.50),
        "mixed": (0.20, 0.50, 0.30),
        "background": (0.0, 0.0, 0.0),
    }
    p_ratio, c_ratio, f_ratio = ratios.get(density_group, ratios["mixed"])
    protein_g = round((kcal_100g * p_ratio) / 4.0, 2)
    carbs_g = round((kcal_100g * c_ratio) / 4.0, 2)
    fat_g = round((kcal_100g * f_ratio) / 9.0, 2)
    return {
        "protein_g": protein_g,
        "carbs_g": carbs_g,
        "fat_g": fat_g,
        "fiber_g": 1.0 if density_group in {"vegetable", "fruit", "staple", "mixed"} else 0.2,
    }


def _build_nutrition(class_id: int, class_name: str, estimated_weight_g: float | None) -> dict | None:
    if not estimated_weight_g:
        return None

    prior = _CLASS_PRIORS.get(class_id, {})
    kcal_100g = float(prior.get("kcal_100g", 120.0))
    density_group = str(prior.get("density_group", "mixed"))
    ratio = estimated_weight_g / 100.0

    if class_name in _NUTRITION_PER_100G:
        base = _NUTRITION_PER_100G[class_name]
        return {
            "calories_kcal": round(base["calories_kcal"] * ratio, 1),
            "protein_g": round(base["protein_g"] * ratio, 1),
            "fat_g": round(base["fat_g"] * ratio, 1),
            "carbs_g": round(base["carbs_g"] * ratio, 1),
            "fiber_g": round(base["fiber_g"] * ratio, 1),
        }

    macro_100g = _fallback_macro_100g(kcal_100g, density_group)
    return {
        "calories_kcal": round(kcal_100g * ratio, 1),
        "protein_g": round(macro_100g["protein_g"] * ratio, 1),
        "fat_g": round(macro_100g["fat_g"] * ratio, 1),
        "carbs_g": round(macro_100g["carbs_g"] * ratio, 1),
        "fiber_g": round(macro_100g["fiber_g"] * ratio, 1),
    }

# Per-class average portion weight in grams – used for pixel-area weight estimation.
_PORTION_WEIGHTS_G: dict[str, float] = {
    "background": 0.0, "rice": 180.0, "noodles": 200.0, "chicken": 150.0,
    "beef": 120.0, "pork": 130.0, "fish": 140.0, "tofu": 100.0,
    "broccoli": 80.0, "carrot": 70.0,
}

# FoodSeg103 class names (fallback to class_xx if missing)
_COCO_NAMES: list[str] = [
    _class_name(i) for i in range(max(_CLASS_PRIORS.keys()) + 1)
]

# Rough nutrition profile per 100g for MVP display.
_NUTRITION_PER_100G: dict[str, dict[str, float]] = {
    "rice": {"calories_kcal": 116.0, "protein_g": 2.6, "fat_g": 0.3, "carbs_g": 25.9, "fiber_g": 0.3},
    "noodles": {"calories_kcal": 138.0, "protein_g": 4.5, "fat_g": 2.1, "carbs_g": 24.8, "fiber_g": 1.2},
    "chicken": {"calories_kcal": 239.0, "protein_g": 27.0, "fat_g": 14.0, "carbs_g": 0.0, "fiber_g": 0.0},
    "beef": {"calories_kcal": 250.0, "protein_g": 26.0, "fat_g": 15.0, "carbs_g": 0.0, "fiber_g": 0.0},
    "pork": {"calories_kcal": 242.0, "protein_g": 27.0, "fat_g": 14.0, "carbs_g": 0.0, "fiber_g": 0.0},
    "fish": {"calories_kcal": 206.0, "protein_g": 22.0, "fat_g": 12.0, "carbs_g": 0.0, "fiber_g": 0.0},
    "tofu": {"calories_kcal": 76.0, "protein_g": 8.0, "fat_g": 4.8, "carbs_g": 1.9, "fiber_g": 0.3},
    "broccoli": {"calories_kcal": 34.0, "protein_g": 2.8, "fat_g": 0.4, "carbs_g": 6.6, "fiber_g": 2.6},
    "carrot": {"calories_kcal": 41.0, "protein_g": 0.9, "fat_g": 0.2, "carbs_g": 9.6, "fiber_g": 2.8},
}


def _encode_mask_rle(binary_mask: np.ndarray) -> str | None:
    """Encode a 2D binary mask as a simple row-major RLE string.

    The encoding always starts with the number of zero-valued pixels, then
    alternates zero-run / one-run counts. This keeps the format deterministic
    and easy to decode in Flutter without COCO-specific tooling.
    """
    flat = binary_mask.astype(np.uint8).reshape(-1)
    if flat.size == 0:
        return ""

    counts: list[int] = []
    current_value = 0
    run_length = 0
    for px in flat:
        value = int(px)
        if value == current_value:
            run_length += 1
        else:
            counts.append(run_length)
            run_length = 1
            current_value = value
    counts.append(run_length)
    return " ".join(map(str, counts))


def get_model() -> NutriSegModel:
    """Return the singleton model (lazy initialisation)."""
    global _model, _model_version
    if _model is None:
        logger.info("Initialising NutriSegModel...")
        checkpoint_path = os.getenv("NUTRI_SEG_CHECKPOINT", "").strip()
        default_classes = max(FOODSEG103_CLASSES.keys()) + 1 if FOODSEG103_CLASSES else 104
        target_classes = default_classes
        if checkpoint_path:
            ckpt = Path(checkpoint_path)
            if ckpt.exists():
                try:
                    state = torch.load(str(ckpt), map_location="cpu")
                    if isinstance(state, dict) and "model_state" in state:
                        state = state["model_state"]
                    if isinstance(state, dict):
                        head_w = state.get("cls_heads.0.2.weight")
                        if isinstance(head_w, torch.Tensor) and head_w.ndim == 4:
                            target_classes = int(head_w.shape[0])
                except Exception as exc:
                    logger.warning("Failed to inspect checkpoint %s: %s", ckpt, exc)
            else:
                logger.warning("NUTRI_SEG_CHECKPOINT does not exist: %s", ckpt)

        input_size = int(os.getenv("NUTRI_SEG_INPUT_SIZE", "512") or "512")
        input_size = max(224, min(1024, input_size))
        _model = NutriSegModel(num_classes=target_classes, input_size=input_size)

        if checkpoint_path:
            ckpt = Path(checkpoint_path)
            if ckpt.exists():
                try:
                    state = torch.load(str(ckpt), map_location="cpu")
                    if isinstance(state, dict) and "model_state" in state:
                        state = state["model_state"]
                    load_result = _model.load_state_dict(state, strict=False)
                    _model_version = f"swin-t-bifpn-ca-v1@{ckpt.name}"
                    logger.info(
                        "Loaded segmentation checkpoint: %s (missing=%d, unexpected=%d)",
                        ckpt,
                        len(load_result.missing_keys),
                        len(load_result.unexpected_keys),
                    )
                except Exception as exc:
                    logger.warning("Failed to load checkpoint %s: %s", ckpt, exc)
        _model.eval()
        logger.info("NutriSegModel ready (model_version=%s)", _model_version)
    return _model


def run_inference(
    image_array: np.ndarray,
    confidence_threshold: float = 0.5,
) -> Tuple[List[dict], float, str | None, str]:
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

    # Preprocess: letterbox to training resolution (default 512) -> normalize -> batch
    from PIL import Image
    import torchvision.transforms.functional as TF

    requested_size = int(os.getenv("NUTRI_SEG_INPUT_SIZE", "512") or "512")
    requested_size = max(224, min(1024, requested_size))
    model_input_size = int(getattr(model, "expected_input_size", requested_size))
    if model_input_size != requested_size:
        logger.warning(
            "NUTRI_SEG_INPUT_SIZE=%d differs from model expected size=%d; using model size",
            requested_size,
            model_input_size,
        )
    input_size = model_input_size

    def _to_normalized_tensor(square_img: np.ndarray) -> torch.Tensor:
        pil_img = Image.fromarray(square_img)
        ten = TF.to_tensor(pil_img).unsqueeze(0).to(device)
        mean = torch.tensor([0.485, 0.456, 0.406], device=device).view(1, 3, 1, 1)
        std = torch.tensor([0.229, 0.224, 0.225], device=device).view(1, 3, 1, 1)
        return (ten - mean) / std

    input_image_sq = _letterbox_to_square(image_array, input_size)
    tensor = _to_normalized_tensor(input_image_sq)

    t0 = time.perf_counter()
    with torch.no_grad():
        try:
            cls_logits, mask_logits = model(tensor)
        except AssertionError as exc:
            # timm Swin may still enforce 224 even when wrapped by features_only;
            # auto-adapt once to avoid returning 500 to callers.
            msg = str(exc)
            m = re.search(r"model\s*\((\d+)\)", msg)
            if m is None:
                raise
            fallback_size = int(m.group(1))
            if fallback_size <= 0 or fallback_size == input_size:
                raise
            logger.warning(
                "Input size mismatch detected (%d -> %d), retrying once",
                input_size,
                fallback_size,
            )
            setattr(model, "expected_input_size", fallback_size)
            input_size = fallback_size
            input_image_sq = _letterbox_to_square(image_array, input_size)
            tensor = _to_normalized_tensor(input_image_sq)
            cls_logits, mask_logits = model(tensor)
    inference_ms = (time.perf_counter() - t0) * 1000

    # Upsample mask logits back to model input resolution.
    mask_logits_up = torch.nn.functional.interpolate(
        mask_logits, size=(input_size, input_size), mode="bilinear", align_corners=False
    )
    foreground_mask = (torch.sigmoid(mask_logits_up[0, 0]) > 0.5).cpu().numpy().astype(bool)

    # Build per-pixel class prediction and per-pixel confidence map.
    cls_prob = torch.softmax(cls_logits[0], dim=0)  # (C, h, w)
    cls_idx = torch.argmax(cls_prob, dim=0)         # (h, w)
    cls_conf = torch.gather(cls_prob, 0, cls_idx.unsqueeze(0)).squeeze(0)  # (h, w)

    cls_idx_up = torch.nn.functional.interpolate(
        cls_idx.float().unsqueeze(0).unsqueeze(0),
        size=(input_size, input_size),
        mode="nearest",
    ).squeeze(0).squeeze(0).to(torch.int64).cpu().numpy()
    cls_conf_up = torch.nn.functional.interpolate(
        cls_conf.unsqueeze(0).unsqueeze(0),
        size=(input_size, input_size),
        mode="bilinear",
        align_corners=False,
    ).squeeze(0).squeeze(0).cpu().numpy()

    valid_mask = foreground_mask & (cls_idx_up != 0)
    segmentation_preview_png_base64 = _build_segmentation_preview_png_base64(input_image_sq, valid_mask)

    detections = []
    min_pixels = max(32, int(input_size * input_size * 0.0005))
    instance_threshold = min(confidence_threshold, 0.35)
    unique_classes = np.unique(cls_idx_up[valid_mask]) if np.any(valid_mask) else np.array([], dtype=np.int64)

    for class_id in unique_classes.tolist():
        class_mask = valid_mask & (cls_idx_up == int(class_id))
        if not np.any(class_mask):
            continue

        comp_count, comp_labels = cv2.connectedComponents(class_mask.astype(np.uint8), connectivity=8)
        for comp_id in range(1, int(comp_count)):
            comp_mask = comp_labels == comp_id
            area = int(comp_mask.sum())
            if area < min_pixels:
                continue

            score = float(np.mean(cls_conf_up[comp_mask]))
            if score < instance_threshold:
                continue

            ys, xs = np.where(comp_mask)
            if ys.size == 0 or xs.size == 0:
                continue

            x_min = float(xs.min())
            y_min = float(ys.min())
            x_max = float(xs.max() + 1)
            y_max = float(ys.max() + 1)

            class_name = _class_name(int(class_id))
            display_name = _display_name_zh(int(class_id), class_name)
            area_ratio = float(area) / float(comp_mask.size)
            prior = _CLASS_PRIORS.get(int(class_id), {})
            avg_portion_g = float(prior.get("default_portion_g", _PORTION_WEIGHTS_G.get(class_name, 100.0)))
            estimated_weight_g = round(area_ratio * avg_portion_g / 0.4, 1) if area_ratio > 0 else None
            nutrition = _build_nutrition(int(class_id), class_name, estimated_weight_g)

            detections.append({
                "class_id": int(class_id),
                "class_name": class_name,
                "display_name": display_name,
                "label": class_name,
                "confidence": round(score, 4),
                "bbox": [x_min, y_min, x_max, y_max],
                "mask_rle": _encode_mask_rle(comp_mask),
                "mask_shape": [int(comp_mask.shape[0]), int(comp_mask.shape[1])],
                "estimated_weight_g": estimated_weight_g,
                "nutrition": nutrition,
            })

    # Fallback: keep at least one non-background coarse result when no components survive.
    if not detections:
        pooled = cls_logits[0].mean(dim=[1, 2])
        probs = torch.softmax(pooled, dim=0).cpu().numpy()
        top_k_indices = np.argsort(probs)[::-1]
        non_bg_mass = float(max(1e-8, 1.0 - float(probs[0]) if probs.shape[0] > 0 else 1.0))
        fallback_idx = next((i for i in top_k_indices if i != 0), 1)
        fallback_raw = float(probs[fallback_idx])
        fallback_score = min(1.0, fallback_raw / non_bg_mass)
        fallback_label = _class_name(int(fallback_idx))
        fallback_display = _display_name_zh(int(fallback_idx), fallback_label)

        area_ratio = float(valid_mask.sum()) / float(valid_mask.size) if np.any(valid_mask) else float(foreground_mask.sum()) / float(foreground_mask.size)
        prior = _CLASS_PRIORS.get(int(fallback_idx), {})
        avg_portion_g = float(prior.get("default_portion_g", _PORTION_WEIGHTS_G.get(fallback_label, 100.0)))
        estimated_weight_g = round(area_ratio * avg_portion_g / 0.4, 1) if area_ratio > 0 else 100.0
        nutrition = _build_nutrition(int(fallback_idx), fallback_label, estimated_weight_g)

        coarse_mask = valid_mask if np.any(valid_mask) else foreground_mask
        detections.append({
            "class_id": int(fallback_idx),
            "class_name": fallback_label,
            "display_name": fallback_display,
            "label": fallback_label,
            "confidence": round(fallback_score, 4),
            "bbox": [0.0, 0.0, float(input_size), float(input_size)],
            "mask_rle": _encode_mask_rle(coarse_mask),
            "mask_shape": [int(coarse_mask.shape[0]), int(coarse_mask.shape[1])],
            "estimated_weight_g": estimated_weight_g,
            "nutrition": nutrition,
        })

    detections.sort(key=lambda d: (float(d.get("confidence", 0.0)), float((d.get("bbox") or [0, 0, 0, 0])[2] - (d.get("bbox") or [0, 0, 0, 0])[0])), reverse=True)

    return detections, inference_ms, segmentation_preview_png_base64, _model_version
