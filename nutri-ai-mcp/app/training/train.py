"""
Training script for Swin Transformer instance segmentation on COCO food datasets.

Usage:
    python -m app.training.train \\
        --dataset_dir /path/to/UNIMIB2016/images \\
        --train_ann /path/to/UNIMIB2016/annotations/train.json \\
        --val_ann /path/to/UNIMIB2016/annotations/val.json \\
        --output_dir ./weights \\
        --epochs 50 \\
        --batch_size 4 \\
        --img_size 512
"""

from __future__ import annotations

import logging
import json
import re
from pathlib import Path
from argparse import ArgumentParser
from datetime import datetime

import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
from torch.utils.tensorboard.writer import SummaryWriter

try:
    from .model_trainable import create_model_trainable
    from .data_loader import create_data_loaders
except ImportError:
    from model_trainable import create_model_trainable
    from data_loader import create_data_loaders

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
        """
        Args:
            logits: (N, C, H, W) – raw class logits
            targets: (N, H, W) – integer class indices
        """
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
        """
        Args:
            pred_masks: (N, 1, H, W) – predicted mask logits
            target_masks: (N, 1, H, W) – GT binary masks
        """
        pred = torch.sigmoid(pred_masks)
        target = target_masks.float()
        
        intersection = (pred * target).sum()
        union = pred.sum() + target.sum()
        
        dice = 2 * (intersection + self.smooth) / (union + self.smooth)
        return 1 - dice


def build_semantic_targets(
    batch,
    device: str,
    num_classes: int,
) -> tuple[torch.Tensor, torch.Tensor]:
    """
    Build per-image dense targets from instance masks.

    Returns:
        cls_targets: (B, H, W) in [0, num_classes-1], where 0 is background
        mask_targets: (B, 1, H, W) binary foreground mask
    """
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

    cls_targets = []
    mask_targets = []

    for masks, labels in zip(batch['masks'], batch['labels']):
        if masks.numel() == 0:
            h = w = 1
            if masks.ndim == 3:
                h, w = masks.shape[-2], masks.shape[-1]
            cls_t = torch.zeros((h, w), dtype=torch.long, device=device)
            mask_t = torch.zeros((1, h, w), dtype=torch.float32, device=device)
            cls_targets.append(cls_t)
            mask_targets.append(mask_t)
            continue

        masks = masks.to(device)
        labels = labels.to(device)
        h, w = masks.shape[-2], masks.shape[-1]

        cls_t = torch.zeros((h, w), dtype=torch.long, device=device)
        for idx in range(masks.shape[0]):
            inst_mask = masks[idx] > 0.5
            class_idx = int(labels[idx].item()) + 1  # reserve 0 for background
            class_idx = max(0, min(class_idx, num_classes - 1))
            cls_t[inst_mask] = class_idx

        mask_t = (masks.max(dim=0).values > 0.5).float().unsqueeze(0)
        cls_targets.append(cls_t)
        mask_targets.append(mask_t)

    return torch.stack(cls_targets, dim=0), torch.stack(mask_targets, dim=0)


def batch_miou(pred_logits: torch.Tensor, gt_labels: torch.Tensor, num_classes: int) -> float:
    """Compute mean IoU over foreground classes present in prediction or target."""
    pred = pred_logits.argmax(dim=1)
    if gt_labels.shape[-2:] != pred.shape[-2:]:
        gt_labels = F.interpolate(
            gt_labels.unsqueeze(1).float(),
            size=pred.shape[-2:],
            mode='nearest',
        ).squeeze(1).long()
    ious = []
    for cls in range(1, num_classes):
        pred_mask = pred == cls
        gt_mask = gt_labels == cls
        union = (pred_mask | gt_mask).sum().item()
        if union == 0:
            continue
        inter = (pred_mask & gt_mask).sum().item()
        ious.append(inter / union)
    if not ious:
        return 0.0
    return float(sum(ious) / len(ious))


def update_intersection_union(
    pred_logits: torch.Tensor,
    gt_labels: torch.Tensor,
    num_classes: int,
    intersections: torch.Tensor,
    unions: torch.Tensor,
) -> None:
    """Accumulate per-class intersection/union statistics for IoU."""
    pred = pred_logits.argmax(dim=1)
    if gt_labels.shape[-2:] != pred.shape[-2:]:
        gt_labels = F.interpolate(
            gt_labels.unsqueeze(1).float(),
            size=pred.shape[-2:],
            mode='nearest',
        ).squeeze(1).long()

    for cls in range(1, num_classes):
        pred_mask = pred == cls
        gt_mask = gt_labels == cls
        intersections[cls] += (pred_mask & gt_mask).sum().item()
        unions[cls] += (pred_mask | gt_mask).sum().item()


def train_one_epoch(
    model: nn.Module,
    train_loader,
    optimizer: optim.Optimizer,
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
    """Train for one epoch."""
    model.train()
    total_loss = 0.0
    processed_batches = 0
    
    for batch_idx, batch in enumerate(train_loader):
        if max_batches > 0 and batch_idx >= max_batches:
            break
        images = batch['images'].to(device)  # (B, 3, H, W)
        cls_targets, mask_targets = build_semantic_targets(
            batch,
            device=device,
            num_classes=num_classes,
        )
        
        # Forward pass
        outputs = model(images)
        cls_logits_list = outputs['cls_logits']
        mask_logits_list = outputs['mask_logits']  # list of (B, 1, H, W)

        loss_total = torch.zeros((), device=device)
        loss_cls_total = torch.zeros((), device=device)
        loss_mask_total = torch.zeros((), device=device)
        
        for level in range(len(mask_logits_list)):
            cls_logits = cls_logits_list[level]
            mask_logits = mask_logits_list[level]  # (B, 1, H, W)

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
        
        optimizer.zero_grad()
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
            images = batch['images'].to(device)
            cls_targets, mask_targets = build_semantic_targets(
                batch,
                device=device,
                num_classes=num_classes,
            )
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

    avg_loss = total_loss / max(processed_batches, 1)
    avg_miou = total_miou / max(processed_batches, 1)
    per_class_iou: dict[int, float] = {}
    for cls in range(1, num_classes):
        union = unions[cls].item()
        if union > 0:
            per_class_iou[cls] = float(intersections[cls].item() / union)
        else:
            per_class_iou[cls] = 0.0
    logger.info(f"Validation average loss: {avg_loss:.4f}, mIoU: {avg_miou:.4f}")
    return avg_loss, avg_miou, per_class_iou


def main():
    parser = ArgumentParser()
    parser.add_argument('--dataset_dir', type=Path, required=False, default=Path('.'))
    parser.add_argument('--train_ann', type=Path, required=False)
    parser.add_argument('--val_ann', type=Path, required=False)
    parser.add_argument('--dataset_type', type=str, default='coco', choices=['coco', 'foodseg103_hf'])
    parser.add_argument('--hf_dataset_dir', type=Path, required=False)
    parser.add_argument('--output_dir', type=Path, default=Path('weights'))
    parser.add_argument('--run_name', type=str, default='')
    parser.add_argument('--epochs', type=int, default=50)
    parser.add_argument('--batch_size', type=int, default=4)
    parser.add_argument('--lr', type=float, default=1e-3)
    parser.add_argument('--img_size', type=int, default=224)
    parser.add_argument('--num_classes', type=int, default=None)
    parser.add_argument('--backbone', type=str, default='swin_tiny_patch4_window7_224')
    parser.add_argument('--loss_cls_weight', type=float, default=1.0)
    parser.add_argument('--loss_mask_weight', type=float, default=1.0)
    parser.add_argument('--max_train_batches', type=int, default=0)
    parser.add_argument('--max_val_batches', type=int, default=0)
    parser.add_argument('--checkpoint_every', type=int, default=10)
    parser.add_argument('--resume_from', type=Path, default=None)
    parser.add_argument('--device', type=str, default='cuda' if torch.cuda.is_available() else 'cpu')
    
    args = parser.parse_args()

    if args.dataset_type == 'coco' and (args.train_ann is None or args.val_ann is None):
        raise ValueError("--train_ann and --val_ann are required when --dataset_type coco")
    if args.dataset_type == 'foodseg103_hf' and args.hf_dataset_dir is None:
        raise ValueError("--hf_dataset_dir is required when --dataset_type foodseg103_hf")

    if args.num_classes is None:
        args.num_classes = 104 if args.dataset_type == 'foodseg103_hf' else 74

    default_tag = (
        f"{args.dataset_type}_"
        f"{args.backbone}_img{args.img_size}_bs{args.batch_size}_"
        f"lr{args.lr:g}_c{args.num_classes}_"
        f"tb{args.max_train_batches if args.max_train_batches > 0 else 'full'}_"
        f"vb{args.max_val_batches if args.max_val_batches > 0 else 'full'}"
    )
    run_tag_raw = args.run_name.strip() if args.run_name.strip() else default_tag
    run_tag = re.sub(r'[^A-Za-z0-9._-]+', '-', run_tag_raw)
    
    # Setup
    run_dir = args.output_dir / run_tag
    run_dir.mkdir(parents=True, exist_ok=True)
    device = args.device
    
    logger.info(f"Using device: {device}")
    logger.info(f"Dataset: {args.dataset_dir}")
    logger.info(f"Train annotations: {args.train_ann}")
    logger.info(f"Val annotations: {args.val_ann}")
    logger.info(f"Dataset type: {args.dataset_type}")
    logger.info(f"HF dataset dir: {args.hf_dataset_dir}")
    logger.info(f"Backbone: {args.backbone}")
    logger.info(f"Run tag: {run_tag}")
    logger.info(f"Run dir: {run_dir}")
    logger.info(f"Checkpoint every: {args.checkpoint_every} epochs")
    if args.resume_from is not None:
        logger.info(f"Resume from: {args.resume_from}")
    
    # Model & data
    model = create_model_trainable(
        num_classes=args.num_classes,
        pretrained=True,
        backbone_name=args.backbone,
    )
    model.to(device)

    if args.resume_from is not None:
        if not args.resume_from.exists():
            raise FileNotFoundError(f"Resume checkpoint not found: {args.resume_from}")
        logger.info(f"Loading checkpoint from {args.resume_from}")
        state_dict = torch.load(args.resume_from, map_location=device)
        model.load_state_dict(state_dict)
        logger.info("Checkpoint loaded successfully")
    
    logger.info(f"Model created with {sum(p.numel() for p in model.parameters())} parameters")
    
    train_loader, val_loader = create_data_loaders(
        args.dataset_dir,
        args.train_ann,
        args.val_ann,
        img_size=args.img_size,
        batch_size=args.batch_size,
        num_workers=0,  # Windows compatibility
        dataset_type=args.dataset_type,
        hf_dataset_dir=args.hf_dataset_dir,
    )
    
    logger.info(f"Train loader: {len(train_loader)} batches")
    logger.info(f"Val loader: {len(val_loader)} batches")
    
    # Optimizer
    optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    
    # Losses
    focal_loss = FocalLoss()
    dice_loss = DiceLoss()
    
    # Tensorboard
    log_dir = run_dir / f'logs_{datetime.now().strftime("%Y%m%d_%H%M%S")}'
    writer = SummaryWriter(str(log_dir))
    logger.info(f"Tensorboard logs: {log_dir}")

    run_info_path = run_dir / 'run_info.json'
    with run_info_path.open('w', encoding='utf-8') as fp:
        json.dump(
            {
                'run_tag': run_tag,
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
    per_class_history_path = run_dir / 'per_class_iou_history.jsonl'
    
    for epoch in range(args.epochs):
        logger.info(f"=== Epoch {epoch+1}/{args.epochs} ===")
        
        global_step = train_one_epoch(
            model,
            train_loader,
            optimizer,
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

        with per_class_history_path.open('a', encoding='utf-8') as fp:
            fp.write(
                json.dumps(
                    {
                        'epoch': epoch + 1,
                        'val_loss': val_loss,
                        'val_mIoU': val_miou,
                        'per_class_iou': {str(k): v for k, v in per_class_iou.items()},
                    },
                    ensure_ascii=False,
                )
                + '\n'
            )

        scheduler.step()
        
        # Save checkpoint
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            checkpoint_path = run_dir / f'best_{run_tag}.pth'
            torch.save(model.state_dict(), checkpoint_path)
            logger.info(f"Saved best model to {checkpoint_path}")
        
        # Regular checkpoint
        if args.checkpoint_every > 0 and (epoch + 1) % args.checkpoint_every == 0:
            checkpoint_path = run_dir / f'model_{run_tag}_epoch_{epoch+1}.pth'
            torch.save(model.state_dict(), checkpoint_path)
            logger.info(f"Saved checkpoint to {checkpoint_path}")
    
    writer.close()
    logger.info("Training complete!")


if __name__ == '__main__':
    main()
