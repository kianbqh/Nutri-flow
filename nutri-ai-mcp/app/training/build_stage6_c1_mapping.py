from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


FOODSEG103_CLASSES = {
	0: "background",
	1: "candy",
	2: "egg tart",
	3: "french fries",
	4: "chocolate",
	5: "biscuit",
	6: "popcorn",
	7: "pudding",
	8: "ice cream",
	9: "cheese butter",
	10: "cake",
	11: "wine",
	12: "milkshake",
	13: "coffee",
	14: "juice",
	15: "milk",
	16: "tea",
	17: "almond",
	18: "red beans",
	19: "cashew",
	20: "dried cranberries",
	21: "soy",
	22: "walnut",
	23: "peanut",
	24: "egg",
	25: "apple",
	26: "date",
	27: "apricot",
	28: "avocado",
	29: "banana",
	30: "strawberry",
	31: "cherry",
	32: "blueberry",
	33: "raspberry",
	34: "mango",
	35: "olives",
	36: "peach",
	37: "lemon",
	38: "pear",
	39: "fig",
	40: "pineapple",
	41: "grape",
	42: "kiwi",
	43: "melon",
	44: "orange",
	45: "watermelon",
	46: "steak",
	47: "pork",
	48: "chicken duck",
	49: "sausage",
	50: "fried meat",
	51: "lamb",
	52: "sauce",
	53: "crab",
	54: "fish",
	55: "shellfish",
	56: "shrimp",
	57: "soup",
	58: "bread",
	59: "corn",
	60: "hamburg",
	61: "pizza",
	62: "hanamaki baozi",
	63: "wonton dumplings",
	64: "pasta",
	65: "noodles",
	66: "rice",
	67: "pie",
	68: "tofu",
	69: "eggplant",
	70: "potato",
	71: "garlic",
	72: "cauliflower",
	73: "tomato",
	74: "kelp",
	75: "seaweed",
	76: "spring onion",
	77: "rape",
	78: "ginger",
	79: "okra",
	80: "lettuce",
	81: "pumpkin",
	82: "cucumber",
	83: "white radish",
	84: "carrot",
	85: "asparagus",
	86: "bamboo shoots",
	87: "broccoli",
	88: "celery stick",
	89: "cilantro mint",
	90: "snow peas",
	91: "cabbage",
	92: "bean sprouts",
	93: "onion",
	94: "pepper",
	95: "green beans",
	96: "french beans",
	97: "king oyster mushroom",
	98: "shiitake",
	99: "enoki mushroom",
	100: "oyster mushroom",
	101: "white button mushroom",
	102: "salad",
	103: "other ingredients",
}


def infer_profile(class_name: str) -> tuple[float, float, str, str]:
	name = class_name.lower()

	nuts = {"almond", "cashew", "walnut", "peanut"}
	meats = {"steak", "pork", "chicken duck", "sausage", "fried meat", "lamb", "fish", "shellfish", "shrimp", "crab"}
	staples = {"bread", "pizza", "pasta", "noodles", "rice", "pie", "hamburg", "wonton dumplings", "hanamaki baozi", "potato", "corn"}
	dairy_sweets = {"candy", "chocolate", "biscuit", "pudding", "ice cream", "cake", "cheese butter", "egg tart", "milkshake"}
	drinks = {"wine", "coffee", "juice", "milk", "tea", "soup"}
	fruits = {"apple", "date", "apricot", "avocado", "banana", "strawberry", "cherry", "blueberry", "raspberry", "mango", "olives", "peach", "lemon", "pear", "fig", "pineapple", "grape", "kiwi", "melon", "orange", "watermelon"}
	vegetables = {
		"tofu", "eggplant", "garlic", "cauliflower", "tomato", "kelp", "seaweed", "spring onion", "rape",
		"ginger", "okra", "lettuce", "pumpkin", "cucumber", "white radish", "carrot", "asparagus", "bamboo shoots",
		"broccoli", "celery stick", "cilantro mint", "snow peas", "cabbage", "bean sprouts", "onion", "pepper",
		"green beans", "french beans", "king oyster mushroom", "shiitake", "enoki mushroom", "oyster mushroom",
		"white button mushroom", "salad", "soy", "red beans"
	}

	if name == "background":
		return 0.0, 0.0, "background", "high"
	if class_name in nuts:
		return 600.0, 25.0, "nut", "medium"
	if class_name in meats:
		return 220.0, 130.0, "protein", "medium"
	if class_name in staples:
		return 210.0, 160.0, "staple", "medium"
	if class_name in dairy_sweets:
		return 350.0, 110.0, "dessert", "medium"
	if class_name in drinks:
		return 45.0, 250.0, "liquid", "low"
	if class_name in fruits:
		return 60.0, 120.0, "fruit", "medium"
	if class_name in vegetables:
		return 35.0, 90.0, "vegetable", "medium"
	if class_name == "egg":
		return 155.0, 60.0, "protein", "high"
	if class_name == "sauce":
		return 180.0, 35.0, "condiment", "low"
	if class_name == "other ingredients":
		return 120.0, 100.0, "mixed", "low"
	return 120.0, 100.0, "mixed", "low"


def build_rows(source_text: str) -> list[dict[str, str | int | float]]:
	rows: list[dict[str, str | int | float]] = []
	for class_id in range(104):
		class_name = FOODSEG103_CLASSES[class_id]
		kcal_100g, portion_g, density_group, conf = infer_profile(class_name)
		rows.append(
			{
				"class_id": class_id,
				"class_name": class_name,
				"kcal_100g": kcal_100g,
				"source": source_text,
				"default_portion_g": portion_g,
				"density_group": density_group,
				"confidence_note": conf,
			}
		)
	return rows


def main() -> None:
	project_root = Path(__file__).resolve().parents[2]

	parser = argparse.ArgumentParser(description="Build Stage6-C1 nutrition prior mapping for FoodSeg103")
	parser.add_argument(
		"--output_csv",
		type=Path,
		default=project_root / "weights_by_category/foodseg103/stage6_c/food_class_to_nutrition.csv",
	)
	parser.add_argument(
		"--output_summary",
		type=Path,
		default=project_root / "weights_by_category/foodseg103/stage6_c/c1_mapping_summary.json",
	)
	args = parser.parse_args()

	source_text = "FoodSeg103 dataset card class taxonomy + heuristic kcal priors (v1)"
	rows = build_rows(source_text)

	args.output_csv.parent.mkdir(parents=True, exist_ok=True)
	args.output_summary.parent.mkdir(parents=True, exist_ok=True)

	fieldnames = [
		"class_id",
		"class_name",
		"kcal_100g",
		"source",
		"default_portion_g",
		"density_group",
		"confidence_note",
	]

	with args.output_csv.open("w", newline="", encoding="utf-8") as f:
		writer = csv.DictWriter(f, fieldnames=fieldnames)
		writer.writeheader()
		writer.writerows(rows)

	summary = {
		"num_rows": len(rows),
		"expected_rows": 104,
		"coverage_ok": len(rows) == 104,
		"source_non_empty_rows": sum(1 for r in rows if str(r["source"]).strip()),
		"output_csv": str(args.output_csv),
	}
	with args.output_summary.open("w", encoding="utf-8") as f:
		json.dump(summary, f, ensure_ascii=False, indent=2)

	print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
	main()
