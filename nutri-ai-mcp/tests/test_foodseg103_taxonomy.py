from __future__ import annotations

import unittest

from app.foodseg103_taxonomy import FOODSEG103_CLASSES, infer_profile


class FoodSeg103TaxonomyTest(unittest.TestCase):
    def test_runtime_taxonomy_has_all_model_classes(self) -> None:
        self.assertEqual(104, len(FOODSEG103_CLASSES))
        self.assertEqual("background", FOODSEG103_CLASSES[0])
        self.assertEqual("chicken duck", FOODSEG103_CLASSES[48])
        self.assertEqual("fish", FOODSEG103_CLASSES[54])
        self.assertEqual("carrot", FOODSEG103_CLASSES[84])
        self.assertEqual("broccoli", FOODSEG103_CLASSES[87])
        self.assertEqual("other ingredients", FOODSEG103_CLASSES[103])

    def test_common_food_profiles_are_not_generic_fallbacks(self) -> None:
        self.assertEqual((220.0, 130.0, "protein", "medium"), infer_profile("fish"))
        self.assertEqual((35.0, 90.0, "vegetable", "medium"), infer_profile("broccoli"))


if __name__ == "__main__":
    unittest.main()
