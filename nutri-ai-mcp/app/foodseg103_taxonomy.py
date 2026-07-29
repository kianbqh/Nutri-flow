"""Runtime FoodSeg103 taxonomy and nutrition-prior helpers."""

from __future__ import annotations


FOODSEG103_CLASS_NAMES = (
    "background",
    "candy",
    "egg tart",
    "french fries",
    "chocolate",
    "biscuit",
    "popcorn",
    "pudding",
    "ice cream",
    "cheese butter",
    "cake",
    "wine",
    "milkshake",
    "coffee",
    "juice",
    "milk",
    "tea",
    "almond",
    "red beans",
    "cashew",
    "dried cranberries",
    "soy",
    "walnut",
    "peanut",
    "egg",
    "apple",
    "date",
    "apricot",
    "avocado",
    "banana",
    "strawberry",
    "cherry",
    "blueberry",
    "raspberry",
    "mango",
    "olives",
    "peach",
    "lemon",
    "pear",
    "fig",
    "pineapple",
    "grape",
    "kiwi",
    "melon",
    "orange",
    "watermelon",
    "steak",
    "pork",
    "chicken duck",
    "sausage",
    "fried meat",
    "lamb",
    "sauce",
    "crab",
    "fish",
    "shellfish",
    "shrimp",
    "soup",
    "bread",
    "corn",
    "hamburg",
    "pizza",
    "hanamaki baozi",
    "wonton dumplings",
    "pasta",
    "noodles",
    "rice",
    "pie",
    "tofu",
    "eggplant",
    "potato",
    "garlic",
    "cauliflower",
    "tomato",
    "kelp",
    "seaweed",
    "spring onion",
    "rape",
    "ginger",
    "okra",
    "lettuce",
    "pumpkin",
    "cucumber",
    "white radish",
    "carrot",
    "asparagus",
    "bamboo shoots",
    "broccoli",
    "celery stick",
    "cilantro mint",
    "snow peas",
    "cabbage",
    "bean sprouts",
    "onion",
    "pepper",
    "green beans",
    "french beans",
    "king oyster mushroom",
    "shiitake",
    "enoki mushroom",
    "oyster mushroom",
    "white button mushroom",
    "salad",
    "other ingredients",
)

FOODSEG103_CLASSES = dict(enumerate(FOODSEG103_CLASS_NAMES))


def infer_profile(class_name: str) -> tuple[float, float, str, str]:
    name = class_name.lower()

    nuts = {"almond", "cashew", "walnut", "peanut"}
    meats = {
        "steak",
        "pork",
        "chicken duck",
        "sausage",
        "fried meat",
        "lamb",
        "fish",
        "shellfish",
        "shrimp",
        "crab",
    }
    staples = {
        "bread",
        "french fries",
        "pizza",
        "pasta",
        "noodles",
        "rice",
        "pie",
        "hamburg",
        "wonton dumplings",
        "hanamaki baozi",
        "potato",
        "corn",
    }
    dairy_sweets = {
        "candy",
        "chocolate",
        "biscuit",
        "pudding",
        "ice cream",
        "cake",
        "cheese butter",
        "egg tart",
        "milkshake",
    }
    drinks = {"wine", "coffee", "juice", "milk", "tea", "soup"}
    fruits = {
        "apple",
        "date",
        "apricot",
        "avocado",
        "banana",
        "strawberry",
        "cherry",
        "blueberry",
        "raspberry",
        "mango",
        "olives",
        "peach",
        "lemon",
        "pear",
        "fig",
        "pineapple",
        "grape",
        "kiwi",
        "melon",
        "orange",
        "watermelon",
    }
    vegetables = {
        "tofu",
        "eggplant",
        "garlic",
        "cauliflower",
        "tomato",
        "kelp",
        "seaweed",
        "spring onion",
        "rape",
        "ginger",
        "okra",
        "lettuce",
        "pumpkin",
        "cucumber",
        "white radish",
        "carrot",
        "asparagus",
        "bamboo shoots",
        "broccoli",
        "celery stick",
        "cilantro mint",
        "snow peas",
        "cabbage",
        "bean sprouts",
        "onion",
        "pepper",
        "green beans",
        "french beans",
        "king oyster mushroom",
        "shiitake",
        "enoki mushroom",
        "oyster mushroom",
        "white button mushroom",
        "salad",
        "soy",
        "red beans",
    }

    if name == "background":
        return 0.0, 0.0, "background", "high"
    if name in nuts:
        return 600.0, 25.0, "nut", "medium"
    if name in meats:
        return 220.0, 130.0, "protein", "medium"
    if name in staples:
        return 210.0, 160.0, "staple", "medium"
    if name in dairy_sweets:
        return 350.0, 110.0, "dessert", "medium"
    if name in drinks:
        return 45.0, 250.0, "liquid", "low"
    if name in fruits:
        return 60.0, 120.0, "fruit", "medium"
    if name in vegetables:
        return 35.0, 90.0, "vegetable", "medium"
    if name == "egg":
        return 155.0, 60.0, "protein", "high"
    if name == "sauce":
        return 180.0, 35.0, "condiment", "low"
    if name == "other ingredients":
        return 120.0, 100.0, "mixed", "low"
    return 120.0, 100.0, "mixed", "low"
