"""
COCO instance segmentation dataset loader for food detection.

Supports UNIMIB2016 and other COCO-format food datasets.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import List, Dict, Any

import torch
import numpy as np
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler
import cv2
from pycocotools import coco
from datasets import load_from_disk

logger = logging.getLogger(__name__)


class COCOFoodDataset(Dataset):
    """Load COCO instance segmentation dataset for food recognition."""

    def __init__(
        self,
        img_dir: Path,
        ann_file: Path,
        img_size: int = 512,
        augment: bool = False,
    ):
        """
        Args:
            img_dir: directory containing images
            ann_file: COCO JSON annotation file
            img_size: target image size
            augment: enable data augmentation
        """
        self.img_dir = Path(img_dir)
        self.img_size = img_size
        self.augment = augment
        
        # Load COCO annotations
        logger.info(f"Loading COCO annotations from {ann_file}")
        self.coco = coco.COCO(str(ann_file))
        self.img_ids = list(self.coco.imgs.keys())
        
        logger.info(f"Loaded {len(self.img_ids)} images from {ann_file}")
        
        # Category mapping
        self.cat_ids = self.coco.getCatIds()
        self.cats = self.coco.loadCats(self.cat_ids)
        self.cat_id_to_idx = {cat['id']: idx for idx, cat in enumerate(self.cats)}
        
        logger.info(f"Classes: {len(self.cats)} (IDs: {self.cat_ids})")

    def __len__(self) -> int:
        return len(self.img_ids)

    def __getitem__(self, idx: int) -> Dict[str, Any]:
        img_id = self.img_ids[idx]
        
        # Load image
        img_info = self.coco.imgs[img_id]
        img_path = self.img_dir / img_info['file_name']
        image = cv2.imread(str(img_path))
        if image is None:
            logger.warning(f"Failed to load {img_path}, using black image")
            image = np.zeros((self.img_size, self.img_size, 3), dtype=np.uint8)
        else:
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        h, w = image.shape[:2]
        
        # Load annotations (masks + bbox + labels)
        ann_ids = self.coco.getAnnIds(imgIds=[img_id])
        anns = self.coco.loadAnns(ann_ids)
        
        # Parse annotations
        boxes = []  # (N, 4) – [x1, y1, x2, y2]
        masks = []  # (N, H, W) – binary masks
        labels = []  # (N,) – class indices
        
        for ann in anns:
            bbox = ann['bbox']  # [x, y, w, h]
            x1, y1, w_bbox, h_bbox = bbox
            x2, y2 = x1 + w_bbox, y1 + h_bbox
            boxes.append([x1, y1, x2, y2])
            
            # annToMask handles polygon and RLE segmentation formats.
            mask = self.coco.annToMask(ann)
            masks.append(mask)
            
            # Category
            cat_id = ann['category_id']
            cat_idx = self.cat_id_to_idx.get(cat_id, 0)
            labels.append(cat_idx)
        
        if len(boxes) == 0:
            # Empty image – return zeros
            boxes = np.zeros((0, 4), dtype=np.float32)
            masks = np.zeros((0, h, w), dtype=np.uint8)
            labels = np.zeros((0,), dtype=np.int32)
        else:
            boxes = np.array(boxes, dtype=np.float32)
            masks = np.array(masks, dtype=np.uint8)
            labels = np.array(labels, dtype=np.int32)
        
        # Resize image to target size
        image_resized = cv2.resize(image, (self.img_size, self.img_size))
        scale_x = self.img_size / max(w, 1)
        scale_y = self.img_size / max(h, 1)
        
        # Scale boxes
        boxes_resized = boxes.copy()
        if len(boxes_resized) > 0:
            boxes_resized[:, [0, 2]] *= scale_x
            boxes_resized[:, [1, 3]] *= scale_y
        
        # Resize masks
        masks_resized = []
        for mask in masks:
            mask_resized = cv2.resize(mask, (self.img_size, self.img_size), interpolation=cv2.INTER_NEAREST)
            masks_resized.append((mask_resized > 0).astype(np.uint8))
        
        if len(masks_resized) > 0:
            masks_resized = np.stack(masks_resized, axis=0)
        else:
            masks_resized = np.zeros((0, self.img_size, self.img_size), dtype=np.uint8)
        
        # Convert to torch tensors
        image_tensor = torch.from_numpy(image_resized).permute(2, 0, 1).float()  # (3, H, W)
        image_tensor /= 255.0  # Normalize to [0, 1]
        
        # Normalize with ImageNet mean/std
        mean = torch.tensor([0.485, 0.456, 0.406]).view(3, 1, 1)
        std = torch.tensor([0.229, 0.224, 0.225]).view(3, 1, 1)
        image_tensor = (image_tensor - mean) / std
        
        boxes_tensor = torch.from_numpy(boxes_resized).float()  # (N, 4)
        masks_tensor = torch.from_numpy(masks_resized).float()  # (N, H, W)
        labels_tensor = torch.from_numpy(labels).long()  # (N,)
        
        return {
            'image': image_tensor,
            'boxes': boxes_tensor,
            'masks': masks_tensor,
            'labels': labels_tensor,
            'img_id': img_id,
            'img_path': str(img_path),
        }


class FoodSeg103HFDataset(Dataset):
    """Load FoodSeg103 from a local HuggingFace save_to_disk directory with augmentation."""

    def __init__(self, hf_dataset_dir: Path, split: str, img_size: int = 224, augment: bool = False):
        self.hf_dataset_dir = Path(hf_dataset_dir)
        self.img_size = img_size
        self.augment = augment
        ds = load_from_disk(str(self.hf_dataset_dir))
        if split not in ds:
            raise ValueError(f"Split '{split}' not found in {self.hf_dataset_dir}")
        self.dataset = ds[split]
        logger.info("Loaded FoodSeg103 split=%s rows=%d augment=%s", split, len(self.dataset), augment)

    def __len__(self) -> int:
        return len(self.dataset)

    def __getitem__(self, idx: int) -> Dict[str, Any]:
        sample = self.dataset[idx]
        image = np.array(sample['image'].convert('RGB'))
        semantic = np.array(sample['label'], dtype=np.int64)

        # Data augmentation for training
        if self.augment:
            image, semantic = self._augment(image, semantic)
        
        # Standard resize
        image = cv2.resize(image, (self.img_size, self.img_size), interpolation=cv2.INTER_LINEAR)
        semantic = cv2.resize(semantic, (self.img_size, self.img_size), interpolation=cv2.INTER_NEAREST)

        # Convert to tensor and normalize
        image_tensor = torch.from_numpy(image).permute(2, 0, 1).float() / 255.0
        mean = torch.tensor([0.485, 0.456, 0.406]).view(3, 1, 1)
        std = torch.tensor([0.229, 0.224, 0.225]).view(3, 1, 1)
        image_tensor = (image_tensor - mean) / std

        semantic_tensor = torch.from_numpy(semantic).long()

        return {
            'image': image_tensor,
            'semantic_label': semantic_tensor,
            'boxes': torch.zeros((0, 4), dtype=torch.float32),
            'masks': torch.zeros((0, self.img_size, self.img_size), dtype=torch.float32),
            'labels': torch.zeros((0,), dtype=torch.long),
            'img_id': sample.get('id', idx),
            'img_path': f"foodseg103:{sample.get('id', idx)}",
        }
    
    def _augment(self, image: np.ndarray, semantic: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Apply data augmentation for training."""
        h, w = image.shape[:2]
        
        # Random horizontal flip (50% chance)
        if np.random.rand() > 0.5:
            image = cv2.flip(image, 1)
            semantic = cv2.flip(semantic, 1)
        
        # Random color jitter (simulate restaurant lighting variations)
        if np.random.rand() > 0.5:
            brightness = np.random.uniform(0.8, 1.2)
            contrast = np.random.uniform(0.8, 1.2)
            saturation = np.random.uniform(0.8, 1.2)
            
            image = (image.astype(np.float32) * brightness).clip(0, 255).astype(np.uint8)
            image = cv2.convertScaleAbs(image, alpha=contrast, beta=0)
            
            hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV).astype(np.float32)
            hsv[:, :, 1] = (hsv[:, :, 1] * saturation).clip(0, 255)
            image = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2RGB)
        
        # Random rotation (small angles to preserve semantic labels)
        if np.random.rand() > 0.7:
            angle = np.random.uniform(-15, 15)
            center = (w // 2, h // 2)
            matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
            image = cv2.warpAffine(image, matrix, (w, h), borderMode=cv2.BORDER_REFLECT)
            semantic = cv2.warpAffine(semantic, matrix, (w, h), borderMode=cv2.BORDER_REFLECT, flags=cv2.INTER_NEAREST)
        
        return image, semantic


def create_weighted_sampler_internal(dataset, label_counts: dict) -> tuple:
    """Create WeightedRandomSampler for class imbalance."""
    weights = []
    for i in range(len(dataset)):
        try:
            sample = dataset[i]
            semantic_label = sample.get('semantic_label') or sample.get('semantic_labels')
            if semantic_label is not None:
                unique_classes = torch.unique(semantic_label)
                weight = sum(label_counts.get(int(c), 1.0) for c in unique_classes) / len(unique_classes)
                weights.append(weight)
            else:
                weights.append(1.0)
        except:
            weights.append(1.0)
    
    weights_tensor = torch.tensor(weights, dtype=torch.float64)
    sampler = WeightedRandomSampler(weights, len(weights), replacement=True)
    return sampler, weights_tensor


def collate_fn(batch: List[Dict]) -> Dict[str, Any]:
    """Custom collate for variable-sized bboxes and masks."""
    images = torch.stack([item['image'] for item in batch], dim=0)
    
    # Store non-batched tensors as lists (variable size)
    boxes_list = [item['boxes'] for item in batch]
    masks_list = [item['masks'] for item in batch]
    labels_list = [item['labels'] for item in batch]
    semantic_labels = None
    if all('semantic_label' in item for item in batch):
        semantic_labels = torch.stack([item['semantic_label'] for item in batch], dim=0)
    
    return {
        'images': images,
        'boxes': boxes_list,
        'masks': masks_list,
        'labels': labels_list,
        'semantic_labels': semantic_labels,
        'img_ids': [item['img_id'] for item in batch],
        'img_paths': [item['img_path'] for item in batch],
    }


def create_data_loaders(
    dataset_dir: Path,
    train_ann: Path | None,
    val_ann: Path | None,
    img_size: int = 224,
    batch_size: int = 4,
    num_workers: int = 0,
    dataset_type: str = 'coco',
    hf_dataset_dir: Path | None = None,
    use_weighted_sampler: bool = False,
) -> tuple[DataLoader, DataLoader]:
    """Create train and validation data loaders with optional WeightedRandomSampler."""

    if dataset_type == 'foodseg103_hf':
        if hf_dataset_dir is None:
            raise ValueError("hf_dataset_dir is required for dataset_type='foodseg103_hf'")
        train_dataset = FoodSeg103HFDataset(hf_dataset_dir=hf_dataset_dir, split='train', img_size=img_size, augment=True)
        val_dataset = FoodSeg103HFDataset(hf_dataset_dir=hf_dataset_dir, split='validation', img_size=img_size, augment=False)
    else:
        if train_ann is None or val_ann is None:
            raise ValueError("train_ann and val_ann are required for dataset_type='coco'")
        train_dataset = COCOFoodDataset(
            img_dir=dataset_dir,
            ann_file=train_ann,
            img_size=img_size,
            augment=True,
        )

        val_dataset = COCOFoodDataset(
            img_dir=dataset_dir,
            ann_file=val_ann,
            img_size=img_size,
            augment=False,
        )
    
    # Use WeightedRandomSampler if requested
    train_sampler = None
    train_shuffle = True
    if use_weighted_sampler:
        try:
            from train_stage4 import compute_class_weights
            label_counts = compute_class_weights(train_dataset, num_samples=500)
            train_sampler, _ = create_weighted_sampler_internal(train_dataset, label_counts)
            train_shuffle = False
            logger.info("Using WeightedRandomSampler for training")
        except Exception as e:
            logger.warning(f"Failed to create WeightedRandomSampler: {e}")
    
    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        sampler=train_sampler,
        shuffle=train_shuffle,
        num_workers=num_workers,
        collate_fn=collate_fn,
    )
    
    val_loader = DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=num_workers,
        collate_fn=collate_fn,
    )
    
    return train_loader, val_loader
