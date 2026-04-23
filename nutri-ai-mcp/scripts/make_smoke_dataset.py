from pathlib import Path
import json
from PIL import Image

root = Path(r"G:/GraduationProj_Nutri-flow/Nutri-flow/nutri-ai-mcp/data/smoke")
img_dir = root / "images"
ann_dir = root / "annotations"
img_dir.mkdir(parents=True, exist_ok=True)
ann_dir.mkdir(parents=True, exist_ok=True)

img_path = img_dir / "smoke_001.jpg"
if not img_path.exists():
    Image.new("RGB", (256, 256), color=(30, 30, 30)).save(img_path)

coco = {
    "info": {"description": "smoke dataset"},
    "licenses": [],
    "images": [
        {"id": 1, "file_name": "smoke_001.jpg", "width": 256, "height": 256}
    ],
    "annotations": [],
    "categories": [
        {"id": i, "name": f"class_{i}", "supercategory": "food"} for i in range(1, 74)
    ]
}

for split in ["train", "val"]:
    with open(ann_dir / f"{split}.json", "w", encoding="utf-8") as f:
        json.dump(coco, f)

print(f"Smoke dataset ready at {root}")
