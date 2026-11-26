"""Tests for the accuracy scorer in scripts/13-accuracy-eval.py."""

import runpy
import unittest
from pathlib import Path

_MODULE = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "scripts" / "13-accuracy-eval.py"),
    run_name="accuracy_eval",
)
score = _MODULE["score"]


class ScoreTest(unittest.TestCase):
    def test_int_uses_last_non_empty_line(self):
        check = {"type": "int", "expected": 40}
        self.assertTrue(score("Counting the commits...\n\n40\n", check))
        self.assertFalse(score("40 commits in total\n3", check))

    def test_int_rejects_non_numeric_answer(self):
        check = {"type": "int", "expected": 3}
        self.assertFalse(score("abc", check))

    def test_list_ignores_order_and_fences(self):
        check = {"type": "list", "expected": ["b.md", "a.md"]}
        self.assertTrue(score('```json\n["a.md", "b.md"]\n```', check))
        self.assertFalse(score('["a.md"]', check))


if __name__ == "__main__":
    unittest.main()
