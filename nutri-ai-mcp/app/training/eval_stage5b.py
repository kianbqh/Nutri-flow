"""Stage5B full-validation evaluator for finished checkpoints.

This script performs evaluation only (no training) and writes:
- summary JSON
- per-class IoU JSONL (single record)
"""

from __future__ import annotations

import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from pathlib import Path

import torch
from torch.utils.tensorboard.writer import SummaryWriter

try:
    from train_stage5a import evaluate, load_checkpoint_compatible
    from model_trainable import create_model_trainable
    from data_loader import create_data_loaders
except ImportError:
    from app.training.train_stage5a import evaluate, load_checkpoint_compatible
    from app.training.model_trainable import create_model_trainable
    from app.training.data_loader import create_data_loaders


logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument('--hf_dataset_dir', type=str, required=True)
    parser.add_argument('--output_dir', type=str, required=True)
    parser.add_argument('--run_name', type=str, required=True)
    parser.add_argument('--backbone', type=str, required=True)
    parser.add_argument('--num_classes', type=int, default=104)
    parser.add_argument('--checkpoint', type=str, required=True)
    parser.add_argument('--batch_size', type=int, required=True)
    parser.add_argument('--img_size', type=int, default=224)
    parser.add_argument('--device', type=str, default='cuda')
    parser.add_argument('--max_val_batches', type=int, default=0, help='0 means full validation set')
    parser.add_argument('--mask_head_mode', type=str, default='binary', choices=['binary', 'semantic'])
    args = parser.parse_args()

    device = args.device
    run_dir = Path(args.output_dir) / args.run_name
    run_dir.mkdir(parents=True, exist_ok=True)

    logger.info('=== Stage5B Full Validation ===')
    logger.info('Run name: %s', args.run_name)
    logger.info('Backbone: %s', args.backbone)
    logger.info('Checkpoint: %s', args.checkpoint)

    _, val_loader = create_data_loaders(
        dataset_dir=Path(args.hf_dataset_dir),
        train_ann=None,
        val_ann=None,
        img_size=args.img_size,
        batch_size=args.batch_size,
        num_workers=0,
        dataset_type='foodseg103_hf',
        hf_dataset_dir=Path(args.hf_dataset_dir),
    )
    logger.info('Val loader batches: %d', len(val_loader))

    model = create_model_trainable(
        num_classes=args.num_classes,
        pretrained=True,
        backbone_name=args.backbone,
        img_size=args.img_size,
        mask_head_mode=args.mask_head_mode,
    )
    model.to(device)

    ckpt = torch.load(args.checkpoint, map_location=device)
    load_checkpoint_compatible(model, ckpt, context='eval_checkpoint')
    logger.info('Checkpoint loaded successfully')

    log_dir = run_dir / f"logs_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    writer = SummaryWriter(str(log_dir))
    per_class_file = run_dir / 'per_class_iou_history.jsonl'

    val_miou, per_class_iou = evaluate(
        model=model,
        val_loader=val_loader,
        device=device,
        num_classes=args.num_classes,
        max_batches=args.max_val_batches,
        writer=writer,
        epoch=0,
        per_class_iou_file=per_class_file,
    )
    writer.close()

    non_bg = [float(v) for k, v in per_class_iou.items() if int(k) != 0]
    nonzero_non_bg = sum(1 for v in non_bg if v > 0.0)

    summary = {
        'stage': 'stage5b',
        'run_name': args.run_name,
        'timestamp': datetime.now().isoformat(),
        'checkpoint': args.checkpoint,
        'backbone': args.backbone,
        'batch_size': args.batch_size,
        'max_val_batches': args.max_val_batches,
        'val_mIoU': float(val_miou),
        'nonzero_non_bg_classes': int(nonzero_non_bg),
        'num_non_bg_classes': len(non_bg),
        'full_val': args.max_val_batches == 0,
    }

    summary_path = run_dir / 'eval_summary.json'
    with summary_path.open('w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2)

    logger.info('Saved eval summary to %s', summary_path)
    logger.info('Stage5B result mIoU=%.4f nonzero_non_bg=%d', val_miou, nonzero_non_bg)


if __name__ == '__main__':
    main()
