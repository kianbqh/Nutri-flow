"""
Download and prepare UNIMIB2016 food instance segmentation dataset.

UNIMIB2016 contains ~1000 images with pixel-level food instance segmentation annotations.
Source: http://www.ivl.disco.unimib.it/activities/food-recognition/unimib2016/

Usage:
    python download_dataset.py --output_dir /path/to/UNIMIB2016
"""

from __future__ import annotations

import logging
import json
import urllib.request
import urllib.error
import tarfile
from pathlib import Path
from argparse import ArgumentParser

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Dataset URLs (example – adjust based on actual UNIMIB2016 location)
UNIMIB2016_URL = "http://www.ivl.disco.unimib.it/activities/food-recognition/unimib2016/UEC-FOOD256.tar.gz"


def download_file(url: str, output_path: Path, chunk_size: int = 8192) -> bool:
    """Download a file with progress reporting."""
    try:
        logger.info(f"Downloading {url}")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with urllib.request.urlopen(url) as response:
            total_size = int(response.headers.get('content-length', 0))
            downloaded = 0
            
            with open(output_path, 'wb') as f:
                while True:
                    chunk = response.read(chunk_size)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    
                    if total_size > 0:
                        percent = (downloaded / total_size) * 100
                        logger.info(f"Progress: {percent:.1f}% ({downloaded}/{total_size} bytes)")
        
        logger.info(f"Downloaded to {output_path}")
        return True
    except urllib.error.URLError as e:
        logger.error(f"Failed to download {url}: {e}")
        return False


def extract_tar_gz(tar_path: Path, output_dir: Path) -> bool:
    """Extract tar.gz file."""
    try:
        logger.info(f"Extracting {tar_path} to {output_dir}")
        with tarfile.open(tar_path, 'r:gz') as tar:
            tar.extractall(path=output_dir)
        logger.info("Extraction complete")
        return True
    except Exception as e:
        logger.error(f"Failed to extract: {e}")
        return False


def create_minimal_coco_annotations(img_dir: Path) -> dict:
    """
    Create minimal COCO-format annotations for UNIMIB2016.
    
    In practice, you'd need to:
    1. Parse the original UNIMIB2016 annotation format
    2. Convert masks to RLE encoding
    3. Create proper COCO JSON categories and images
    
    This is a placeholder that creates an empty COCO structure.
    """
    coco_data = {
        "info": {
            "description": "UNIMIB2016 Food Instance Segmentation",
            "version": "1.0",
            "year": 2016,
        },
        "licenses": [
            {
                "id": 1,
                "name": "Creative Commons Attribution 4.0",
                "url": "https://creativecommons.org/licenses/by/4.0/"
            }
        ],
        "images": [],
        "annotations": [],
        "categories": [
            {"id": i, "name": f"food_class_{i}", "supercategory": "food"}
            for i in range(1, 74)  # 73 food classes
        ]
    }
    
    logger.info("Created COCO template with 73 food classes")
    return coco_data


def main():
    parser = ArgumentParser()
    parser.add_argument(
        '--output_dir',
        type=Path,
        default=Path('./data/UNIMIB2016'),
        help='Output directory for dataset'
    )
    parser.add_argument(
        '--no_download',
        action='store_true',
        help='Skip download (assume dataset already exists)'
    )
    
    args = parser.parse_args()
    output_dir = args.output_dir
    
    logger.info(f"Dataset output directory: {output_dir}")
    
    # Create directory structure
    img_dir = output_dir / 'images'
    ann_dir = output_dir / 'annotations'
    img_dir.mkdir(parents=True, exist_ok=True)
    ann_dir.mkdir(parents=True, exist_ok=True)
    
    # Download (optional)
    if not args.no_download:
        tar_path = output_dir / 'UNIMIB2016.tar.gz'
        if not tar_path.exists():
            success = download_file(UNIMIB2016_URL, tar_path)
            if not success:
                logger.warning("Download failed. Proceeding with manual setup...")
        
        if tar_path.exists():
            extract_tar_gz(tar_path, output_dir)
    
    # Create COCO annotations template
    coco_template = create_minimal_coco_annotations(img_dir)
    
    # Save train/val/test splits (placeholder)
    for split in ['train', 'val', 'test']:
        ann_file = ann_dir / f'{split}.json'
        with open(ann_file, 'w') as f:
            json.dump(coco_template, f, indent=2)
        logger.info(f"Created {ann_file}")
    
    logger.info(f"""
=== Dataset Setup Complete ===
Images directory: {img_dir}
Annotations directory: {ann_dir}

Next steps:
1. Place UNIMIB2016 images in: {img_dir}
2. Create COCO format annotations in: {ann_dir}
3. Run training:
   python -m app.training.train \\
       --dataset_dir {img_dir} \\
       --train_ann {ann_dir}/train.json \\
       --val_ann {ann_dir}/val.json \\
       --epochs 50 \\
       --batch_size 4
    """)


if __name__ == '__main__':
    main()
