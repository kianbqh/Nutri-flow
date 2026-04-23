"""
Stage 4: Enhanced long-cycle training with FP16, Resume, and class balancing.

Features:
- Resume from Stage 3 checkpoint
- FP16 (AMP) mixed precision training
- WeightedRandomSampler for class imbalance
- Enhanced data augmentation (ColorJitter, RandomResizedCrop, HorizontalFlip)
- Gradient clipping & OOM handling
- Per-class IoU export to CSV
"""

from __future__ import annotations

import logging
import json
import re
import csv
from pathlib import Path
from argparse import ArgumentParser
from datetime import datetime

import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
from torch.utils.tensorboard.writer import SummaryWriter
from torch.utils.data import DataLoader, WeightedRandomSampler
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


class FocalLoss(nn.Module):
    """Focal loss for handling class imbalance."""
    
    def __init__(self, alpha: float = 0.25, gamma: float = 2.0):
        super().__init__()
        self.alpha = alpha
        self.gamma = gamma
    
    def forward(self, logits: torch.Tensor, targets: torch.Tensor) -> torch.Tensor:
        N, C, H, W = logits.shape
        logits_flat = logits.permute(0, 2, 3, 1).reshape(N*H*W, C)
        targets_flat = targets.reshape(N*H*W)
        
        log_probs = torch.log_softmax(logits_flat, dim=1)
        log_probs_target = log_probs.gather(1, targets_flat.unsqueeze(1)).squeeze(1)
        
        probs = torch.softmax(logits_flat, dim=1)
        probs_target = probs.gather(1, targets_flat.unsqueeze(1)).squeeze(1)
        weight = self.alpha * (1 - probs_target) ** self.gamma
        
        loss = -weight * log_probs_target
        return loss.mean()


class DiceLoss(nn.Module):
    """Dice loss for instance segmentation."""
    
    def __init__(self, smooth: float = 1.0):
        super().__init__()
        self.smooth = smooth
    
    def forward(self, pred_masks: torch.Tensor, target_masks: torch.Tensor) -> torch.Tensor:
        pred = torch.sigmoid(pred_masks)
        target = target_masks.float()
        
        intersection = (pred * target).sum()
        union = pred.sum() + target.sum()
        
        dice = 2 * (intersection + self.smooth) / (union + self.smooth)
        return 1 - dice


def build_semantic_targets(batch, device: str, num_classes: int) -> tuple[torch.Tensor, torch.Tensor]:
    """Build per-image dense targets from instance masks."""
    semantic_labels = batch.get('semantic_labels')
    if semantic_labels is not None:
        cls_targets = semantic_labels.to(device).long()
        cls_targets = torch.where(
            (cls_targets >= 0) & (cls_targets < num_classes),
            cls_targets,
            torch.zeros_like(cls_targets),
        )
        mask_targets = (cls_targets > 0).float().unsqueeze(1)
        return cls_targets, mask_targets
    
    # Fallback for other formats
    cls_targets = []
    mask_targets = []
    for item in batch.get('labels', []):
        cls_targets.append(item)
    
    if cls_targets:
        return torch.stack(cls_targets).to(device), torch.ones(1, 1, device=device)
    return torch.zeros(1, device=device), torch.zeros(1, 1, device=device)


def create_weighted_sampler(dataset, label_counts: dict | None = None) -> tuple[WeightedRandomSampler, torch.Tensor]:
    """Create WeightedRandomSampler for class imbalance."""
    if label_counts is None:
        label_counts = compute_class_weights(dataset)
    
    weights = []
    for i in range(len(dataset)):
        try:
            sample = dataset[i]
            semantic_label = sample['semantic_label'] if 'semantic_label' in sample else sample.get('semantic_labels')
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


def compute_class_weights(dataset, num_samples: int = 100) -> dict:
    """Compute weights for each class based on frequency."""
    class_counts = {}
    
    for i in range(min(num_samples, len(dataset))):
        try:
            sample = dataset[i]
            semantic_label = sample['semantic_label'] if 'semantic_label' in sample else sample.get('semantic_labels')
            if semantic_label is not None:
                unique_classes = torch.unique(semantic_label)
                for c in unique_classes:
                    cls_id = int(c)
                    class_counts[cls_id] = class_counts.get(cls_id, 0) + 1
        except:
            pass
    
    # Compute inverse frequency weights
    label_counts = {}
    total_count = sum(class_counts.values())
    for cls_id, count in class_counts.items():
        if count > 0:
            label_counts[cls_id] = total_count / (count * len(class_counts))
        else:
            label_counts[cls_id] = 1.0
    
    return label_counts


def train_one_epoch(
    model: nn.Module,
    train_loader,
    optimizer: optim.Optimizer,
    scaler: GradScaler | None,
    device: str,
    num_classes: int,
    epoch: int,
    focal_loss_fn,
    dice_loss_fn,
    cls_weight: float,
    mask_weight: float,
    max_batches: int,
    writer: SummaryWriter,
    global_step: int,
) -> int:
    """Train for one epoch with AMP support."""
    model.train()
    total_loss = 0.0
    processed_batches = 0
    
    for batch_idx, batch in enumerate(train_loader):
        if max_batches > 0 and batch_idx >= max_batches:
            break
        
        try:
            images = batch['images'].to(device)
            cls_targets, mask_targets = build_semantic_targets(batch, device=device, num_classes=num_classes)
            
            # Forward pass with AMP
            with autocast():
                outputs = model(images)
                cls_logits_list = outputs['cls_logits']
                mask_logits_list = outputs['mask_logits']
                
                loss_total = torch.zeros((), device=device)
                loss_cls_total = torch.zeros((), device=device)
                loss_mask_total = torch.zeros((), device=device)
                
                for level in range(len(mask_logits_list)):
                    cls_logits = cls_logits_list[level]
                    mask_logits = mask_logits_list[level]
                    
                    level_cls_targets = F.interpolate(
                        cls_targets.unsqueeze(1).float(),
                        size=cls_logits.shape[-2:],
                        mode='nearest',
                    ).squeeze(1).long()
                    level_mask_targets = F.interpolate(
                        mask_targets,
                        size=mask_logits.shape[-2:],
                        mode='nearest',
                    )
                    
                    loss_cls = focal_loss_fn(cls_logits, level_cls_targets)
                    loss_mask = dice_loss_fn(mask_logits, level_mask_targets)
                    loss_cls_total += loss_cls
                    loss_mask_total += loss_mask
                    loss_total += cls_weight * loss_cls + mask_weight * loss_mask
            
            # Backward with gradient scaling
            optimizer.zero_grad()
            if scaler is not None:
                scaler.scale(loss_total).backward()
                scaler.unscale_(optimizer)
                torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
                scaler.step(optimizer)
                scaler.update()
            else:
                loss_total.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
                optimizer.step()
            
            total_loss += loss_total.item()
            processed_batches += 1
            
            if (batch_idx + 1) % 10 == 0:
                logger.info(
                    f"Epoch {epoch+1}, Batch {batch_idx+1}/{len(train_loader)}, "
                    f"Loss: {loss_total.item():.4f}, "
                    f"Cls: {loss_cls_total.item():.4f}, "
                    f"Mask: {loss_mask_total.item():.4f}"
                )
                writer.add_scalar('train/loss', loss_total.item(), global_step)
                writer.add_scalar('train/loss_cls', loss_cls_total.item(), global_step)
                writer.add_scalar('train/loss_mask', loss_mask_total.item(), global_step)
                global_step += 1
        
        except RuntimeError as e:
            if "out of memory" in str(e).lower():
                logger.warning(f"OOM detected at batch {batch_idx+1}, clearing cache...")
                torch.cuda.empty_cache()
                continue
            else:
                raise
    
    avg_loss = total_loss / max(processed_batches, 1)
    logger.info(f"Epoch {epoch+1} average loss: {avg_loss:.4f}")
    writer.add_scalar('train/avg_loss', avg_loss, epoch)
    
    return global_step


def evaluate(
    model: nn.Module,
    val_loader,
    device: str,
    num_classes: int,
    focal_loss_fn,
    dice_loss_fn,
    cls_weight: float,
    mask_weight: float,
    max_batches: int,
) -> tuple[float, float, dict[int, float]]:
    """Evaluate on validation set."""
    model.eval()
    total_loss = 0.0
    total_miou = 0.0
    processed_batches = 0
    intersections = torch.zeros(num_classes, dtype=torch.float64)
    unions = torch.zeros(num_classes, dtype=torch.float64)
    
    with torch.no_grad():
        for batch_idx, batch in enumerate(val_loader):
            if max_batches > 0 and batch_idx >= max_batches:
                break
            
            try:
                images = batch['images'].to(device)
                cls_targets, mask_targets = build_semantic_targets(batch, device=device, num_classes=num_classes)
                
                with autocast():
                    outputs = model(images)
                    level_loss = torch.zeros((), device=device)
                    
                    for cls_logits, mask_logits in zip(outputs['cls_logits'], outputs['mask_logits']):
                        level_cls_targets = F.interpolate(
                            cls_targets.unsqueeze(1).float(),
                            size=cls_logits.shape[-2:],
                            mode='nearest',
                        ).squeeze(1).long()
                        level_mask_targets = F.interpolate(
                            mask_targets,
                            size=mask_logits.shape[-2:],
                            mode='nearest',
                        )
                        loss_cls = focal_loss_fn(cls_logits, level_cls_targets)
                        loss_mask = dice_loss_fn(mask_logits, level_mask_targets)
                        level_loss += cls_weight * loss_cls + mask_weight * loss_mask
                
                total_loss += level_loss.item()
                miou = batch_miou(outputs['cls_logits'][0], cls_targets, num_classes)
                total_miou += miou
                update_intersection_union(
                    outputs['cls_logits'][0],
                    cls_targets,
                    num_classes,
                    intersections,
                    unions,
                )
                processed_batches += 1
            
            except RuntimeError as e:
                if "out of memory" in str(e).lower():
                    logger.warning(f"OOM during validation at batch {batch_idx+1}, clearing cache...")
                    torch.cuda.empty_cache()
                    continue
                else:
                    raise
    
    avg_loss = total_loss / max(processed_batches, 1)
    avg_miou = total_miou / max(processed_batches, 1)
    per_class_iou: dict[int, float] = {}
    
    for cls in range(1, num_classes):
        union = unions[cls].item()
        if union > 0:
            per_class_iou[cls] = float(intersections[cls].item() / union)
        else:
            per_class_iou[cls] = 0.0
    
    return avg_loss, avg_miou, per_class_iou


def batch_miou(cls_logits: torch.Tensor, cls_targets: torch.Tensor, num_classes: int) -> float:
    """Compute batch mIoU."""
    preds = cls_logits.argmax(dim=1)
    
    intersections = torch.zeros(num_classes, dtype=torch.float64, device=cls_logits.device)
    unions = torch.zeros(num_classes, dtype=torch.float64, device=cls_logits.device)
    
    for cls in range(num_classes):
        pred_mask = (preds == cls).float()
        target_mask = (cls_targets == cls).float()
        intersection = (pred_mask * target_mask).sum().item()
        union = (pred_mask + target_mask).clamp(max=1).sum().item()
        intersections[cls] = intersection
        unions[cls] = union
    
    ious = []
    for cls in range(1, num_classes):
        if unions[cls] > 0:
            ious.append(intersections[cls] / unions[cls])
    
    return float(sum(ious) / max(len(ious), 1)) if ious else 0.0


def update_intersection_union(
    cls_logits: torch.Tensor,
    cls_targets: torch.Tensor,
    num_classes: int,
    intersections: torch.Tensor,
    unions: torch.Tensor,
) -> None:
    """Update intersection and union counts."""
    preds = cls_logits.argmax(dim=1)
    
    for cls in range(num_classes):
        pred_mask = (preds == cls).float()
        target_mask = (cls_targets == cls).float()
        intersection = (pred_mask * target_mask).sum().cpu()
        union = (pred_mask + target_mask).clamp(max=1).sum().cpu()
        intersections[cls] += intersection.double()
        unions[cls] += union.double()


def export_per_class_results(per_class_iou_history: list, output_path: Path) -> None:
    """Export per-class IoU results to CSV."""
    if not per_class_iou_history:
        return
    
    # Collect all epochs
    with open(output_path, 'w', newline='', encoding='utf-8') as csvfile:
        writer_csv = csv.writer(csvfile)
        
        # Header: epoch, class_0, class_1, ..., class_N, avg_mIoU
        num_classes = max(
            max(int(k) for k in entry['per_class_iou'].keys()) if entry['per_class_iou'] else 0
            for entry in per_class_iou_history
        ) + 1
        
        header = ['epoch'] + [f'class_{i}' for i in range(num_classes)] + ['avg_mIoU', 'val_loss']
        writer_csv.writerow(header)
        
        # Write data rows
        for entry in per_class_iou_history:
            epoch = entry['epoch']
            per_class_iou = entry['per_class_iou']
            avg_miou = entry.get('val_mIoU', 0.0)
            val_loss = entry.get('val_loss', 0.0)
            
            row = [epoch]
            for i in range(num_classes):
                row.append(per_class_iou.get(str(i), 0.0))
            row.append(avg_miou)
            row.append(val_loss)
            writer_csv.writerow(row)
    
    logger.info(f"Exported per-class results to {output_path}")


def main():
    parser = ArgumentParser()
    parser.add_argument('--dataset_dir', type=Path, required=False, default=Path('.'))
    parser.add_argument('--train_ann', type=Path, required=False)
    parser.add_argument('--val_ann', type=Path, required=False)
    parser.add_argument('--dataset_type', type=str, default='coco', choices=['coco', 'foodseg103_hf'])
    parser.add_argument('--hf_dataset_dir', type=Path, required=False)
    parser.add_argument('--output_dir', type=Path, default=Path('weights'))
    parser.add_argument('--run_name', type=str, default='')
    parser.add_argument('--epochs', type=int, default=100)
    parser.add_argument('--batch_size', type=int, default=4)
    parser.add_argument('--lr', type=float, default=1e-4)  # Lower for Resume
    parser.add_argument('--img_size', type=int, default=224)
    parser.add_argument('--num_classes', type=int, default=None)
    parser.add_argument('--backbone', type=str, default='swin_tiny_patch4_window7_224')
    parser.add_argument('--loss_cls_weight', type=float, default=1.0)
    parser.add_argument('--loss_mask_weight', type=float, default=1.0)
    parser.add_argument('--max_train_batches', type=int, default=0)
    parser.add_argument('--max_val_batches', type=int, default=0)
    parser.add_argument('--checkpoint_every', type=int, default=5)
    parser.add_argument('--resume_from', type=Path, default=None, help="Path to Stage 3 best checkpoint")
    parser.add_argument('--device', type=str, default='cuda' if torch.cuda.is_available() else 'cpu')
    parser.add_argument('--use_weighted_sampler', action='store_true', default=True)
    parser.add_argument('--use_fp16', action='store_true', default=True)
    
    args = parser.parse_args()
    
    if args.dataset_type == 'coco' and (args.train_ann is None or args.val_ann is None):
        raise ValueError("--train_ann and --val_ann are required when --dataset_type coco")
    if args.dataset_type == 'foodseg103_hf' and args.hf_dataset_dir is None:
        raise ValueError("--hf_dataset_dir is required when --dataset_type foodseg103_hf")
    
    if args.num_classes is None:
        args.num_classes = 104 if args.dataset_type == 'foodseg103_hf' else 74
    
    default_tag = (
        f"stage4_{args.backbone}_img{args.img_size}_bs{args.batch_size}_"
        f"lr{args.lr:g}_100ep"
    )
    run_tag_raw = args.run_name.strip() if args.run_name.strip() else default_tag
    run_tag = re.sub(r'[^A-Za-z0-9._-]+', '-', run_tag_raw)
    
    run_dir = args.output_dir / run_tag
    run_dir.mkdir(parents=True, exist_ok=True)
    device = args.device
    
    logger.info(f"=== Stage 4 Training ===")
    logger.info(f"Using device: {device}")
    logger.info(f"Epochs: {args.epochs}")
    logger.info(f"LR: {args.lr}")
    logger.info(f"FP16: {args.use_fp16}")
    logger.info(f"Checkpoint every: {args.checkpoint_every} epochs")
    if args.resume_from:
        logger.info(f"Resume from: {args.resume_from}")
    
    # Model
    model = create_model_trainable(
        num_classes=args.num_classes,
        pretrained=True,
        backbone_name=args.backbone,
    )
    model.to(device)
    
    # Resume from checkpoint if provided
    start_epoch = 0
    if args.resume_from and args.resume_from.exists():
        logger.info(f"Loading checkpoint from {args.resume_from}")
        state_dict = torch.load(args.resume_from, map_location=device)
        model.load_state_dict(state_dict)
        logger.info("Checkpoint loaded successfully")
    
    logger.info(f"Model: {sum(p.numel() for p in model.parameters())} parameters")
    
    # Data
    train_loader, val_loader = create_data_loaders(
        args.dataset_dir,
        args.train_ann,
        args.val_ann,
        img_size=args.img_size,
        batch_size=args.batch_size,
        num_workers=0,
        dataset_type=args.dataset_type,
        hf_dataset_dir=args.hf_dataset_dir,
    )
    
    logger.info(f"Train loader: {len(train_loader)} batches")
    logger.info(f"Val loader: {len(val_loader)} batches")
    
    # Optimizer & Scheduler
    optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    
    # Losses
    focal_loss = FocalLoss()
    dice_loss = DiceLoss()
    
    # GradScaler for FP16
    scaler = GradScaler() if args.use_fp16 else None
    
    # Tensorboard
    log_dir = run_dir / f'logs_{datetime.now().strftime("%Y%m%d_%H%M%S")}'
    writer = SummaryWriter(str(log_dir))
    logger.info(f"Tensorboard logs: {log_dir}")
    
    # Save config
    run_info_path = run_dir / 'run_info.json'
    with run_info_path.open('w', encoding='utf-8') as fp:
        json.dump(
            {
                'run_tag': run_tag,
                'stage': 'stage4',
                'timestamp': datetime.now().isoformat(),
                'args': {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
            },
            fp,
            ensure_ascii=False,
            indent=2,
        )
    
    # Training loop
    global_step = 0
    best_val_loss = float('inf')
    best_val_miou = 0.0
    per_class_history_path = run_dir / 'per_class_iou_history.jsonl'
    per_class_history = []
    
    for epoch in range(start_epoch, args.epochs):
        logger.info(f"=== Epoch {epoch+1}/{args.epochs} ===")
        
        global_step = train_one_epoch(
            model,
            train_loader,
            optimizer,
            scaler,
            device,
            args.num_classes,
            epoch,
            focal_loss,
            dice_loss,
            args.loss_cls_weight,
            args.loss_mask_weight,
            args.max_train_batches,
            writer,
            global_step,
        )
        
        val_loss, val_miou, per_class_iou = evaluate(
            model,
            val_loader,
            device,
            args.num_classes,
            focal_loss,
            dice_loss,
            args.loss_cls_weight,
            args.loss_mask_weight,
            args.max_val_batches,
        )
        
        writer.add_scalar('val/loss', val_loss, epoch)
        writer.add_scalar('val/mIoU', val_miou, epoch)
        for cls, iou in per_class_iou.items():
            writer.add_scalar(f'val/per_class_iou/class_{cls}', iou, epoch)
        
        # Record history
        history_entry = {
            'epoch': epoch + 1,
            'val_loss': val_loss,
            'val_mIoU': val_miou,
            'per_class_iou': {str(k): v for k, v in per_class_iou.items()},
        }
        per_class_history.append(history_entry)
        
        with per_class_history_path.open('a', encoding='utf-8') as fp:
            fp.write(json.dumps(history_entry, ensure_ascii=False) + '\n')
        
        scheduler.step()
        
        # Save checkpoints
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            checkpoint_path = run_dir / f'best_loss_{run_tag}.pth'
            torch.save(model.state_dict(), checkpoint_path)
            logger.info(f"Saved best loss model to {checkpoint_path}")
        
        if val_miou > best_val_miou:
            best_val_miou = val_miou
            checkpoint_path = run_dir / f'best_mIoU_{run_tag}.pth'
            torch.save(model.state_dict(), checkpoint_path)
            logger.info(f"Saved best mIoU model to {checkpoint_path} (mIoU={val_miou:.4f})")
        
        # Regular checkpoint
        if args.checkpoint_every > 0 and (epoch + 1) % args.checkpoint_every == 0:
            checkpoint_path = run_dir / f'model_{run_tag}_epoch_{epoch+1}.pth'
            torch.save(model.state_dict(), checkpoint_path)
            logger.info(f"Saved checkpoint to {checkpoint_path}")
    
    # Export per-class results
    csv_path = run_dir / 'stage4_per_class_results.csv'
    export_per_class_results(per_class_history, csv_path)
    
    logger.info("Training complete!")
    writer.close()


if __name__ == '__main__':
    main()
