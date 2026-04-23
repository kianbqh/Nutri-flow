"""Compute real class weights from FoodSeg103 training split.

Outputs a JSON file compatible with train_stage5a.py format.
"""
import json
from pathlib import Path
import torch
import numpy as np
from argparse import ArgumentParser

try:
    from data_loader import FoodSeg103HFDataset
except ImportError:
    from app.training.data_loader import FoodSeg103HFDataset

def compute_class_weights(
    dataset_dir: str,
    output_file: str = "class_distribution_real.json",
    min_weight: float = 0.5,
    max_weight: float = 6.0,
):
    """Compute per-class pixel counts and inverse frequency weights."""
    
    print(f"Loading FoodSeg103 dataset from {dataset_dir}...")
    dataset = FoodSeg103HFDataset(
        hf_dataset_dir=Path(dataset_dir),
        split='train',
        img_size=224,
        augment=False
    )
    print(f"Total samples: {len(dataset)}")
    
    class_counts = {}
    total_pixels = 0
    
    for i in range(len(dataset)):
        if (i + 1) % 500 == 0:
            print(f"  Processing {i + 1}/{len(dataset)}...")
        
        try:
            sample = dataset[i]
            seg_label = sample.get('semantic_label', None)
            if seg_label is None:
                seg_label = sample.get('semantic_labels', None)
            
            if seg_label is not None:
                if isinstance(seg_label, torch.Tensor):
                    seg_label = seg_label.detach().cpu().numpy()
                else:
                    seg_label = np.asarray(seg_label)
                
                unique_classes = np.unique(seg_label)
                for cls in unique_classes:
                    mask = (seg_label == cls)
                    count = np.sum(mask)
                    class_counts[int(cls)] = class_counts.get(int(cls), 0) + count
                    total_pixels += count
        except Exception as e:
            print(f"  Warning: error processing sample {i}: {e}")
            continue
    
    print(f"\nTotal pixels: {total_pixels}")
    print(f"Classes found: {len(class_counts)}")
    
    # Compute median-frequency balanced weights:
    # w_c = (median_freq / freq_c) ^ 0.5, then clip.
    freqs = []
    for cls_id in range(104):
        count = class_counts.get(cls_id, 0)
        if count > 0:
            freqs.append(float(count) / float(total_pixels))
    median_freq = float(np.median(freqs)) if freqs else 1.0

    # Compute class weights and clip to avoid extreme instability.
    class_weights = {}
    for cls_id in range(104):  # FoodSeg103 has 104 classes (0-103)
        count = class_counts.get(cls_id, 0)
        if count == 0:
            # For unseen classes, fallback to neutral weight.
            class_weights[cls_id] = 1.0
        else:
            freq = float(count) / float(total_pixels)
            weight = (median_freq / freq) ** 0.5
            class_weights[cls_id] = float(np.clip(weight, min_weight, max_weight))
    
    # Save results
    output_path = Path(output_file)
    with output_path.open('w') as f:
        json.dump({
            'class_counts': {str(k): int(v) for k, v in class_counts.items()},
            'class_weights': {str(k): v for k, v in class_weights.items()},
            'total_pixels': int(total_pixels),
            'num_classes': 104,
            'classes_with_pixels': len(class_counts)
        }, f, indent=2)
    
    print(f"\nSaved to {output_path}")
    
    # Print statistics
    sorted_counts = sorted([(k, v) for k, v in class_counts.items()], key=lambda x: x[1])
    
    print(f"\n{'='*70}")
    print("Class distribution (top 15 least frequent):")
    print(f"{'Class':<6} {'Pixels':>12} {'Freq %':>8} {'Weight':>12}")
    print("-" * 70)
    for cls_id, count in sorted_counts[:15]:
        freq = 100.0 * float(count) / float(total_pixels)
        weight = class_weights[cls_id]
        print(f"{cls_id:<6} {count:>12} {freq:>7.3f}% {weight:>12.4f}")
    
    print(f"\n{'='*70}")
    print("Class distribution (top 15 most frequent):")
    print(f"{'Class':<6} {'Pixels':>12} {'Freq %':>8} {'Weight':>12}")
    print("-" * 70)
    for cls_id, count in sorted_counts[-15:]:
        freq = 100.0 * float(count) / float(total_pixels)
        weight = class_weights[cls_id]
        print(f"{cls_id:<6} {count:>12} {freq:>7.3f}% {weight:>12.4f}")
    
    print(f"\n{'='*70}")
    print(f"Classes with 0 pixels in training: {104 - len(class_counts)}")
    print(f"Min weight (most frequent): {min(class_weights.values()):.6f}")
    print(f"Max weight (least frequent): {max(class_weights.values()):.6f}")
    print(f"Weight ratio (max/min): {max(class_weights.values()) / min(class_weights.values()):.2f}x")
    
    return class_weights

if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument('--hf_dataset_dir', type=str, required=True)
    parser.add_argument('--output_file', type=str, default='class_distribution_real.json')
    parser.add_argument('--min_weight', type=float, default=0.5)
    parser.add_argument('--max_weight', type=float, default=6.0)
    args = parser.parse_args()

    compute_class_weights(
        dataset_dir=args.hf_dataset_dir,
        output_file=args.output_file,
        min_weight=args.min_weight,
        max_weight=args.max_weight,
    )
