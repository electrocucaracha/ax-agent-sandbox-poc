"""Test instruction admission, proposal boundaries and safe promotion."""

import copy
import json
import runpy
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = runpy.run_path(str(ROOT / "scripts/12-self-improve.py"))


class SelfImprovementTests(unittest.TestCase):
    def setUp(self):
        self.suite = {
            "target": "agents/mutation.md",
            "context": "Reply with JSON.",
            "cases": [
                {
                    "id": "t",
                    "split": "train",
                    "input": "training",
                    "expected": {"ok": True},
                },
                {
                    "id": "h",
                    "split": "holdout",
                    "input": "hidden",
                    "expected": {"ok": True},
                },
            ],
        }

    def rows(self, train, holdout):
        return [
            {"id": "t", "repeat": 1, "split": "train", "correct": train},
            {"id": "h", "repeat": 1, "split": "holdout", "correct": holdout},
        ]

    def test_gate_requires_holdout_gain_and_no_paired_regression(self):
        gate = MODULE["gate"]
        self.assertTrue(
            gate(self.rows(False, False), self.rows(True, True))["eligible"]
        )
        self.assertTrue(gate(self.rows(True, False), self.rows(True, True))["eligible"])
        self.assertFalse(
            gate(self.rows(False, True), self.rows(True, True))["eligible"]
        )
        self.assertFalse(
            gate(self.rows(False, True), self.rows(True, False))["eligible"]
        )
        baseline = self.rows(False, False) + [
            {"id": "safety", "repeat": 1, "split": "holdout", "correct": True},
            {"id": "another", "repeat": 1, "split": "holdout", "correct": False},
        ]
        candidate = self.rows(True, True) + [
            {"id": "safety", "repeat": 1, "split": "holdout", "correct": False},
            {"id": "another", "repeat": 1, "split": "holdout", "correct": True},
        ]
        self.assertFalse(gate(baseline, candidate)["eligible"])
        with self.assertRaises(ValueError):
            gate(self.rows(False, False), self.rows(True, True)[:1])

    def test_invalid_suites_and_boolean_number_answers_are_rejected(self):
        validate = MODULE["validate_suite"]
        for mutate in (
            lambda s: s.update(target="../agents/mutation.md"),
            lambda s: s["cases"][1].update(input="training"),
            lambda s: s["cases"][1].update(split="train"),
            lambda s: s["cases"][1].update(id="t"),
            lambda s: s["cases"][1].update(expected=None),
        ):
            suite = copy.deepcopy(self.suite)
            mutate(suite)
            with self.subTest(suite=suite), self.assertRaises(ValueError):
                validate(suite)
        self.assertFalse(MODULE["exact_answer"]('{"ok":1}', {"ok": True}))
        self.assertFalse(MODULE["exact_answer"]('{"ok":true,"extra":1}', {"ok": True}))

    def test_proposer_never_receives_holdout_and_passing_addition_is_retained(self):
        requests = []
        usage = {"input_tokens": 1, "output_tokens": 1}

        def request(endpoint, headers, model, messages, max_tokens, system):
            text = messages[0]["content"]
            requests.append(text)
            if "Training feedback:" in text:
                self.assertNotIn("hidden", text)
                return usage, '{"addition":"Clarify the decision."}'
            return usage, json.dumps({"ok": "Clarify the decision." in text})

        report = MODULE["optimize"](
            {
                "suite": self.suite,
                "definition": "# Existing constraints\n",
                "settings": {
                    "endpoint": "https://example.test/v1",
                    "headers": {},
                    "model": "test",
                    "image_digest": "test",
                },
                "iterations": 1,
                "repetitions": 1,
            },
            request,
        )
        self.assertTrue(report["eligible"])
        self.assertEqual(len(requests), 5)
        self.assertEqual(
            report["iterations"][0]["gate"]["gains"], {"train": 1, "holdout": 1}
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory).resolve() / "target.md"
            original = "# Existing constraints\n"
            path.write_text(original)
            self.assertTrue(MODULE["promote"](path, original, report))
            self.assertTrue(path.read_text().startswith(original))
            path.write_text("concurrent change")
            with self.assertRaises(RuntimeError):
                MODULE["promote"](path, original, report)

    def test_invalid_proposal_never_changes_incumbent(self):
        for addition in (
            "not json",
            '{"addition":42}',
            json.dumps({"addition": "x" * 2001}),
        ):

            def request(endpoint, headers, model, messages, max_tokens, system):
                return {}, (
                    addition
                    if "Training feedback:" in messages[0]["content"]
                    else '{"ok":true}'
                )

            report = MODULE["optimize"](
                {
                    "suite": self.suite,
                    "definition": "Original\n",
                    "settings": {
                        "endpoint": "https://example.test",
                        "headers": {},
                        "model": "test",
                        "image_digest": "test",
                    },
                    "iterations": 1,
                    "repetitions": 1,
                },
                request,
            )
            self.assertFalse(report["eligible"])
            self.assertEqual(report["candidate_definition"], "Original\n")
            self.assertIn("rejection", report["iterations"][0])

    def test_target_rejects_symlink_components(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "actual").mkdir()
            (root / "actual/role.md").write_text("Original")
            (root / "agents").symlink_to(root / "actual", target_is_directory=True)
            with self.assertRaises(ValueError):
                MODULE["target_path"](root, "agents/role.md")


if __name__ == "__main__":
    unittest.main()
