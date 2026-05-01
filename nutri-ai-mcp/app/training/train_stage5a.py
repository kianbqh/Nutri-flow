"""
Stage 5a: Class-Weighted Focal Loss Diagnostic Run
(Focuses on activating dormant classes through loss reweighting)

Key changes from train.py:
1. Load per-class weights from class_distribution.json
2. Apply class weights to Focal Loss
3. Resume from best checkpoints: Tiny from epoch 100, Base from epoch 44
4. Run 50 epochs with frequent per-class IoU logging (every 5 epochs)
"""

from __future__ import annotations

import logging
import json
import re
import csv
from pathlib import Path
from argparse import ArgumentParser
from datetime import datetime
from typing import Dict, Optional, Any

import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
from torch.utils.tensorboard.writer import SummaryWriter
from torch.utils.data import DataLoader
from torch.cuda.amp import autocast, GradScaler
import torchvision.transforms as transforms

try:
    from .model_trainable import create_model_trainable
    from .data_loader import create_data_loaders, FoodSeg103HFDataset
except ImportError:
    from model_trainable import create_model_trainable
    from data_loader import create_data_loaders, FoodSeg103HFDataset

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)


class WeightedFocalLoss(nn.Module):
    """Focal loss with per-class weighting for imbalanced segmentation."""
    
    def __init__(self, alpha: float = 0.25, gamma: float = 2.0, class_weights: Optional[Dict[int, float]] = None):
        super().__init__()
        self.alpha = alpha
        self.gamma = gamma
        self.class_weights = class_weights  # {class_id: weight, ...}
    
    def forward(self, logits: torch.Tensor, targets: torch.Tensor) -> torch.Tensor:
        """
        Args:
            logits: (B, C, H, W) model outputs
            targets: (B, H, W) ground truth class indices
        Returns:
            weighted focal loss
        """
        B, C, H, W = logits.shape
        logits_flat = logits.permute(0, 2, 3, 1).reshape(-1, C)  # (B*H*W, C)
        targets_flat = targets.reshape(-1)  # (B*H*W,)
        
        # Standard focal loss
        p = torch.softmax(logits_flat, dim=1)
        ce_loss = F.cross_entropy(logits_flat, targets_flat, reduction='none')
        p_t = p.gather(1, targets_flat.unsqueeze(1)).squeeze(1)
        focal_weight = (1 - p_t) ** self.gamma
        focal_loss = self.alpha * focal_weight * ce_loss  # (B*H*W,)
        
        # Apply per-class weight
        if self.class_weights is not None:
            class_weight_map = torch.ones_like(targets_flat, dtype=torch.float32)
            for cls_id, weight in self.class_weights.items():
                mask = targets_flat == cls_id
                class_weight_map[mask] = weight
            focal_loss = focal_loss * class_weight_map
        
        return focal_loss.mean()


class SemanticMaskLoss(nn.Module):
    """Class-aware semantic mask loss for multi-class mask heads."""

    def __init__(self, class_weights: Optional[Dict[int, float]] = None):
        super().__init__()
        self.class_weights = class_weights

    def forward(self, logits: torch.Tensor, targets: torch.Tensor) -> torch.Tensor:
        weight_tensor = None
        if self.class_weights is not None:
            weight_tensor = logits.new_ones((logits.shape[1],), dtype=torch.float32)
            for cls_id, weight in self.class_weights.items():
                if 0 <= cls_id < logits.shape[1]:
                    weight_tensor[cls_id] = float(weight)
        return F.cross_entropy(logits, targets, weight=weight_tensor)


class DiceLoss(nn.Module):
    """Dice loss for segmentation."""
    
    def __init__(self, smooth: float = 1.0):
        super().__init__()
        self.smooth = smooth
    
    def forward(self, logits: torch.Tensor, targets: torch.Tensor) -> torch.Tensor:
        probs = torch.sigmoid(logits)
        intersection = (probs * targets).sum()
        union = probs.sum() + targets.sum()
        dice = 1 - (2 * intersection + self.smooth) / (union + self.smooth)
        return dice


def compute_hard_boundary_map(labels: torch.Tensor) -> torch.Tensor:
    """Compute a binary boundary target from semantic labels."""
    boundary = torch.zeros_like(labels, dtype=torch.float32)
    vertical = (labels[:, 1:, :] != labels[:, :-1, :]).float()
    horizontal = (labels[:, :, 1:] != labels[:, :, :-1]).float()
    boundary[:, 1:, :] = torch.maximum(boundary[:, 1:, :], vertical)
    boundary[:, :-1, :] = torch.maximum(boundary[:, :-1, :], vertical)
    boundary[:, :, 1:] = torch.maximum(boundary[:, :, 1:], horizontal)
    boundary[:, :, :-1] = torch.maximum(boundary[:, :, :-1], horizontal)
    return boundary.unsqueeze(1)


def compute_soft_boundary_map(prob_map: torch.Tensor) -> torch.Tensor:
    """Compute a soft boundary response from a probability map."""
    vertical = torch.abs(prob_map[:, :, 1:, :] - prob_map[:, :, :-1, :])
    horizontal = torch.abs(prob_map[:, :, :, 1:] - prob_map[:, :, :, :-1])
    vertical_top = F.pad(vertical, (0, 0, 1, 0))
    vertical_bottom = F.pad(vertical, (0, 0, 0, 1))
    horizontal_left = F.pad(horizontal, (1, 0, 0, 0))
    horizontal_right = F.pad(horizontal, (0, 1, 0, 0))
    boundary = torch.maximum(torch.maximum(vertical_top, vertical_bottom), torch.maximum(horizontal_left, horizontal_right))
    return boundary.clamp(0.0, 1.0)


def compute_boundary_logit_map(logit_map: torch.Tensor) -> torch.Tensor:
    """Compute boundary logits directly from raw binary mask logits."""
    vertical = torch.abs(logit_map[:, :, 1:, :] - logit_map[:, :, :-1, :])
    horizontal = torch.abs(logit_map[:, :, :, 1:] - logit_map[:, :, :, :-1])
    vertical_top = F.pad(vertical, (0, 0, 1, 0))
    vertical_bottom = F.pad(vertical, (0, 0, 0, 1))
    horizontal_left = F.pad(horizontal, (1, 0, 0, 0))
    horizontal_right = F.pad(horizontal, (0, 1, 0, 0))
    return torch.maximum(torch.maximum(vertical_top, vertical_bottom), torch.maximum(horizontal_left, horizontal_right))


class BoundaryConsistencyLoss(nn.Module):
    """Encourages semantic foreground probability to align with target boundaries."""

    def forward(self, logits: torch.Tensor, boundary_targets: torch.Tensor) -> torch.Tensor:
        if logits.shape[1] == 1:
            # For binary heads, operate on raw logits to avoid unstable logit(prob) gradients
            # once the resumed mask head becomes highly saturated.
            pred_boundary_logits = compute_boundary_logit_map(logits.float())
            return F.binary_cross_entropy_with_logits(pred_boundary_logits, boundary_targets.float())
        else:
            class_prob = torch.softmax(logits, dim=1)
            foreground_prob = class_prob[:, 1:, :, :].max(dim=1, keepdim=True).values
        pred_boundary = compute_soft_boundary_map(foreground_prob)
        pred_boundary_logits = torch.logit(pred_boundary.clamp(1e-4, 1.0 - 1e-4))
        return F.binary_cross_entropy_with_logits(pred_boundary_logits, boundary_targets.float())


def build_semantic_targets(batch: dict, device: str, num_classes: int, mask_head_mode: str = 'binary') -> tuple:
    """Convert batch to semantic segmentation targets."""
    semantic_labels = batch.get('semantic_label') or batch.get('semantic_labels')
    if semantic_labels is None:
        raise ValueError("No semantic label in batch")
    
    semantic_labels = torch.as_tensor(semantic_labels, device=device, dtype=torch.long)
    
    # Create one-hot class targets (B, H, W) -> (B, num_classes, H, W)
    B, H, W = semantic_labels.shape
    cls_targets = torch.zeros(B, H, W, dtype=torch.long, device=device)
    cls_targets = semantic_labels

    if mask_head_mode == 'semantic':
        mask_targets = cls_targets
    else:
        # Create binary mask for foreground (everything except background 0)
        mask_targets = (semantic_labels > 0).float().unsqueeze(1)  # (B, 1, H, W)

    boundary_targets = compute_hard_boundary_map(semantic_labels)

    return cls_targets, mask_targets, boundary_targets


def extract_model_state(checkpoint: dict | torch.Tensor) -> dict[str, Any] | torch.Tensor:
    if isinstance(checkpoint, dict) and 'model_state' in checkpoint:
        return checkpoint['model_state']
    return checkpoint


def load_checkpoint_compatible(model: nn.Module, checkpoint: dict | torch.Tensor, context: str = 'checkpoint') -> None:
    model_state = model.state_dict()
    checkpoint_state = extract_model_state(checkpoint)
    if not isinstance(checkpoint_state, dict):
        raise TypeError(f"{context} model_state must be a dict, got {type(checkpoint_state)!r}")

    compatible_state = {}
    skipped_shape = []
    unexpected = []

    for key, value in checkpoint_state.items():
        if key not in model_state:
            unexpected.append(key)
            continue
        if model_state[key].shape != value.shape:
            skipped_shape.append(key)
            continue
        compatible_state[key] = value

    missing = [key for key in model_state.keys() if key not in compatible_state]
    model.load_state_dict(compatible_state, strict=False)
    logger.info(
        "%s compatible load: matched=%d missing=%d skipped_shape=%d unexpected=%d",
        context,
        len(compatible_state),
        len(missing),
        len(skipped_shape),
        len(unexpected),
    )
    if skipped_shape:
        logger.info("%s skipped shape-mismatch keys: %s", context, skipped_shape[:10])
    if unexpected:
        logger.info("%s unexpected keys: %s", context, unexpected[:10])


def train_one_epoch(
    model: nn.Module,
    train_loader,
    optimizer: optim.Optimizer,
    device: str,
    num_classes: int,
    epoch: int,
    focal_loss_fn,
    mask_loss_fn,
    boundary_loss_fn,
    cls_weight: float,
    mask_weight: float,
    boundary_weight: float,
    mask_head_mode: str,
    max_batches: int,
    writer: SummaryWriter,
    global_step: int,
) -> int:
    """Train for one epoch."""
    model.train()
    total_loss = 0.0
    processed_batches = 0
    
    for batch_idx, batch in enumerate(train_loader):
        if max_batches > 0 and batch_idx >= max_batches:
            break
        
        try:
            images = batch['images'].to(device)
            cls_targets, mask_targets, boundary_targets = build_semantic_targets(
                batch,
                device=device,
                num_classes=num_classes,
                mask_head_mode=mask_head_mode,
            )
            
            # Forward pass
            with autocast():
                outputs = model(images)
                cls_logits_list = outputs['cls_logits']
                mask_logits_list = outputs['mask_logits']
                
                loss_total = torch.zeros((), device=device)
                loss_cls_total = torch.zeros((), device=device)
                loss_mask_total = torch.zeros((), device=device)
                loss_boundary_total = torch.zeros((), device=device)
                
                for level in range(len(mask_logits_list)):
                    cls_logits = cls_logits_list[level]
                    mask_logits = mask_logits_list[level]
                    
                    level_cls_targets = F.interpolate(
                        cls_targets.unsqueeze(1).float(),
                        size=cls_logits.shape[-2:],
                        mode='nearest',
                    ).squeeze(1).long()
                    level_boundary_targets = F.interpolate(
                        boundary_targets,
                        size=mask_logits.shape[-2:],
                        mode='nearest',
                    )
                    if mask_head_mode == 'semantic':
                        level_mask_targets = F.interpolate(
                            mask_targets.unsqueeze(1).float(),
                            size=mask_logits.shape[-2:],
                            mode='nearest',
                        ).squeeze(1).long()
                    else:
                        level_mask_targets = F.interpolate(
                            mask_targets,
                            size=mask_logits.shape[-2:],
                            mode='nearest',
                        )
                    
                    loss_cls = focal_loss_fn(cls_logits, level_cls_targets)
                    loss_mask = mask_loss_fn(mask_logits, level_mask_targets)
                    loss_boundary = boundary_loss_fn(mask_logits, level_boundary_targets)
                    loss_cls_total += loss_cls
                    loss_mask_total += loss_mask
                    loss_boundary_total += loss_boundary
                    loss_total += cls_weight * loss_cls + mask_weight * loss_mask + boundary_weight * loss_boundary

                if not torch.isfinite(loss_total):
                    raise RuntimeError(
                        "Non-finite loss detected at "
                        f"epoch={epoch+1} batch={batch_idx+1}: "
                        f"total={loss_total.detach().float().item():.6f}, "
                        f"cls={loss_cls_total.detach().float().item():.6f}, "
                        f"mask={loss_mask_total.detach().float().item():.6f}, "
                        f"boundary={loss_boundary_total.detach().float().item():.6f}"
                    )
            
            # Backward
            optimizer.zero_grad()
            loss_total.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            
            total_loss += loss_total.item()
            processed_batches += 1
            
            if (batch_idx + 1) % 10 == 0:
                logger.info(
                    f"Epoch {epoch+1}, Batch {batch_idx+1}/{len(train_loader)}, "
                    f"Loss: {loss_total.item():.4f}, Cls: {loss_cls_total.item():.4f}, Mask: {loss_mask_total.item():.4f}, Boundary: {loss_boundary_total.item():.4f}"
                )
                writer.add_scalar('train/loss', loss_total.item(), global_step)
                writer.add_scalar('train/loss_cls', loss_cls_total.item(), global_step)
                writer.add_scalar('train/loss_mask', loss_mask_total.item(), global_step)
                writer.add_scalar('train/loss_boundary', loss_boundary_total.item(), global_step)
                global_step += 1
        
        except RuntimeError as e:
            if "out of memory" in str(e).lower():
                logger.warning(f"OOM at batch {batch_idx+1}, clearing cache...")
                torch.cuda.empty_cache()
                continue
            else:
                raise
    
    avg_loss = total_loss / max(processed_batches, 1)
    logger.info(f"Epoch {epoch+1} average loss: {avg_loss:.4f}")
    writer.add_scalar('train/avg_loss', avg_loss, epoch)
    
    return global_step


def batch_miou(logits: torch.Tensor, targets: torch.Tensor, num_classes: int) -> float:
    """Compute mean IoU over foreground classes only."""
    pred = logits.argmax(dim=1)  # (B, H, W)
    iou_list = []
    
    for cls in range(1, num_classes):  # Skip background (class 0)
        pred_mask = (pred == cls).float()
        target_mask = (targets == cls).float()
        intersection = (pred_mask * target_mask).sum()
        union = pred_mask.sum() + target_mask.sum() - intersection
        if union > 0:
            iou = intersection / union
            iou_list.append(float(iou))
    
    return sum(iou_list) / len(iou_list) if iou_list else 0.0


@torch.no_grad()
def evaluate(
    model: nn.Module,
    val_loader,
    device: str,
    num_classes: int,
    max_batches: int,
    writer: SummaryWriter,
    epoch: int,
    per_class_iou_file: Path,
) -> tuple:
    """Evaluate on validation set, tracking per-class IoU."""
    model.eval()
    total_loss = 0.0
    processed_batches = 0
    per_class_iou = {}  # {class_id: [intersection, union], ...}
    global_iou_list = []
    
    for batch_idx, batch in enumerate(val_loader):
        if max_batches > 0 and batch_idx >= max_batches:
            break
        
        images = batch['images'].to(device)
        cls_targets, _, _ = build_semantic_targets(batch, device=device, num_classes=num_classes)
        
        outputs = model(images)
        cls_logits = outputs['cls_logits'][0]  # Use first scale
        cls_logits_interp = F.interpolate(
            cls_logits, size=cls_targets.shape[-2:], mode='bilinear', align_corners=False
        )
        
        pred = cls_logits_interp.argmax(dim=1)
        
        # Per-class IoU
        for cls in range(num_classes):
            pred_mask = (pred == cls).float()
            target_mask = (cls_targets == cls).float()
            intersection = (pred_mask * target_mask).sum().item()
            union = pred_mask.sum().item() + target_mask.sum().item() - intersection
            
            if cls not in per_class_iou:
                per_class_iou[cls] = [0, 0]
            per_class_iou[cls][0] += intersection
            per_class_iou[cls][1] += union
        
        # Batch mIoU
        batch_ious = batch_miou(cls_logits_interp, cls_targets, num_classes)
        global_iou_list.append(batch_ious)
        
        processed_batches += 1
    
    # Compute final metrics
    val_miou_list = []
    per_class_iou_dict = {}
    for cls in range(num_classes):
        inter, union = per_class_iou.get(cls, [0, 0])
        if union > 0:
            iou = inter / union
            val_miou_list.append(float(iou))
            per_class_iou_dict[str(cls)] = float(iou)
        else:
            per_class_iou_dict[str(cls)] = 0.0
    
    val_miou = sum(val_miou_list) / len(val_miou_list) if val_miou_list else 0.0
    
    logger.info(f"Validation average loss: N/A, mIoU: {val_miou:.4f}")
    writer.add_scalar('val/mIoU', val_miou, epoch)
    
    # Export per-class IoU to JSONL
    record = {
        'epoch': epoch,
        'val_loss': 0.0,  # Not computed in this version
        'val_mIoU': val_miou,
        'per_class_iou': per_class_iou_dict
    }
    with per_class_iou_file.open('a', encoding='utf-8') as f:
        f.write(json.dumps(record) + '\n')
    
    return val_miou, per_class_iou_dict


def main():
    parser = ArgumentParser()
    parser.add_argument('--dataset_dir', type=str)
    parser.add_argument('--hf_dataset_dir', type=str, required=True)
    parser.add_argument('--output_dir', type=str, required=True)
    parser.add_argument('--run_name', type=str, required=True)
    parser.add_argument('--epochs', type=int, default=50)
    parser.add_argument('--batch_size', type=int, required=True)
    parser.add_argument('--img_size', type=int, default=224)
    parser.add_argument('--device', type=str, default='cuda')
    parser.add_argument('--backbone', type=str, required=True)
    parser.add_argument('--num_classes', type=int, default=104)
    parser.add_argument('--loss_cls_weight', type=float, default=1.0)
    parser.add_argument('--loss_mask_weight', type=float, default=1.0)
    parser.add_argument('--max_train_batches', type=int, default=2000)
    parser.add_argument('--max_val_batches', type=int, default=500)
    parser.add_argument('--checkpoint_every', type=int, default=5)
    parser.add_argument('--resume_from', type=str, default=None)
    parser.add_argument('--class_weights_file', type=str, default='class_distribution.json')
    parser.add_argument('--lr', type=float, default=2e-4)
    parser.add_argument('--mask_head_mode', type=str, default='binary', choices=['binary', 'semantic'])
    parser.add_argument('--boundary_loss_weight', type=float, default=0.0)
    parser.add_argument('--use_weighted_sampler', action='store_true')
    
    args = parser.parse_args()
    args.output_dir = Path(args.output_dir)
    args.hf_dataset_dir = Path(args.hf_dataset_dir)
    if args.resume_from:
        args.resume_from = Path(args.resume_from)
    
    device = args.device
    logger.info(f"Using device: {device}")
    
    run_dir = args.output_dir / args.run_name
    run_dir.mkdir(parents=True, exist_ok=True)
    
    # Load class weights
    class_weights_path = Path(args.class_weights_file)
    class_weights_dict = None
    if class_weights_path.exists():
        logger.info(f"Loading class weights from {class_weights_path}")
        with class_weights_path.open() as f:
            class_dist = json.load(f)
            class_weights_dict = {int(k): v for k, v in class_dist['class_weights'].items()}
        logger.info(f"Loaded weights for {len(class_weights_dict)} classes")
    else:
        logger.warning(f"Class weights file not found: {class_weights_path}")
    
    # Data loaders
    train_loader, val_loader = create_data_loaders(
        dataset_dir=args.hf_dataset_dir,
        train_ann=None,
        val_ann=None,
        img_size=args.img_size,
        batch_size=args.batch_size,
        num_workers=0,
        dataset_type='foodseg103_hf',
        hf_dataset_dir=args.hf_dataset_dir,
        use_weighted_sampler=args.use_weighted_sampler,
    )
    logger.info(f"Train loader: {len(train_loader)} batches")
    logger.info(f"Val loader: {len(val_loader)} batches")
    logger.info(f"Weighted sampler enabled: {args.use_weighted_sampler}")
    
    # Model
    model = create_model_trainable(
        num_classes=args.num_classes,
        pretrained=True,
        backbone_name=args.backbone,
        img_size=args.img_size,
        mask_head_mode=args.mask_head_mode,
    )
    model.to(device)
    
    if args.resume_from and args.resume_from.exists():
        logger.info(f"Resuming from: {args.resume_from}")
        checkpoint = torch.load(args.resume_from, map_location=device)
        load_checkpoint_compatible(model, checkpoint, context='resume_from')
        logger.info("Checkpoint loaded successfully")
    
    # Optimizer & Scheduler
    optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    
    # Losses with class weighting
    focal_loss = WeightedFocalLoss(class_weights=class_weights_dict)
    if args.mask_head_mode == 'semantic':
        mask_loss = SemanticMaskLoss(class_weights=class_weights_dict)
    else:
        mask_loss = DiceLoss()
    boundary_loss = BoundaryConsistencyLoss()
    
    # TensorBoard
    log_dir = run_dir / f'logs_{datetime.now().strftime("%Y%m%d_%H%M%S")}'
    writer = SummaryWriter(str(log_dir))
    logger.info(f"TensorBoard logs: {log_dir}")
    
    # Skip run_info.json save to avoid Path serialization issues - just log it instead
    logger.info(f"Run tag: {args.run_name}, Stage: stage5a, Time: {datetime.now().isoformat()}")
    logger.info(f"Class weights enabled: {class_weights_dict is not None}")
    
    per_class_iou_file = run_dir / 'per_class_iou_history.jsonl'
    
    # Training loop
    best_miou = -1.0
    global_step = 0
    
    for epoch in range(args.epochs):
        logger.info(f"=== Epoch {epoch+1}/{args.epochs} ===")
        
        global_step = train_one_epoch(
            model, train_loader, optimizer, device, args.num_classes,
            epoch, focal_loss, mask_loss, boundary_loss, args.loss_cls_weight, args.loss_mask_weight,
            args.boundary_loss_weight, args.mask_head_mode,
            args.max_train_batches, writer, global_step
        )
        
        val_miou, per_class_iou = evaluate(
            model, val_loader, device, args.num_classes,
            args.max_val_batches, writer, epoch, per_class_iou_file
        )
        
        scheduler.step()
        
        # Checkpoint every N epochs or if mIoU improved
        if (epoch + 1) % args.checkpoint_every == 0 or val_miou > best_miou:
            ckpt_path = run_dir / f'model_{args.run_name}_epoch_{epoch+1}.pth'
            torch.save({
                'epoch': epoch + 1,
                'model_state': model.state_dict(),
                'optimizer_state': optimizer.state_dict(),
                'val_miou': val_miou,
            }, ckpt_path)
            logger.info(f"Saved checkpoint to {ckpt_path}")
            
            if val_miou > best_miou:
                best_miou = val_miou
                best_ckpt = run_dir / f'best_{args.run_name}.pth'
                torch.save({
                    'epoch': epoch + 1,
                    'model_state': model.state_dict(),
                    'val_miou': val_miou,
                }, best_ckpt)
                logger.info(f"New best mIoU: {best_miou:.4f}, saved to {best_ckpt}")
    
    writer.close()
    logger.info("Training completed")


if __name__ == '__main__':
    main()
