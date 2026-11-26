"""Test replay metric parsing, regressions and unsupported success claims."""

import json
import runpy
import unittest
from pathlib import Path

MODULE = runpy.run_path(str(Path(__file__).resolve().parent / "replay_evidence.py"))


class EvidenceReplayTests(unittest.TestCase):
    def test_token_events_preserve_cache_counts_and_reject_missing_metrics(self):
        usage, unparsed = MODULE["opencode_usage"](
            json.dumps(
                {
                    "type": "step_finish",
                    "part": {
                        "tokens": {
                            "input": 20,
                            "output": 4,
                            "cache": {"read": 9, "write": 3},
                        }
                    },
                }
            )
        )
        self.assertEqual(
            usage,
            {
                "input_tokens": 20,
                "output_tokens": 4,
                "cache_read_input_tokens": 9,
                "cache_creation_input_tokens": 3,
            },
        )
        self.assertEqual(unparsed, 0)
        with self.assertRaises(ValueError):
            MODULE["opencode_usage"]('{"type":"text"}')

    def test_summary_exposes_regressions_unsupported_claims_and_missing_usage(self):
        case = {"id": "a", "dataset": "fresh", "expected": {"claim_verified": False}}
        rows = [
            MODULE["observation"](
                case,
                "original",
                1,
                '{"claim_verified":false}',
                2,
                {
                    "input_tokens": 10,
                    "output_tokens": 2,
                    "cache_read_input_tokens": 0,
                    "cache_creation_input_tokens": 0,
                },
            ),
            MODULE["observation"](
                case, "improved", 1, '{"claim_verified":true}', 1, None
            ),
        ]
        summary = MODULE["summarize"](rows)
        self.assertEqual(summary["paired"]["losses"], 1)
        self.assertEqual(summary["improved"]["unsupported_success_claims"], 1)
        self.assertEqual(summary["improved"]["usage_missing"], 1)
        self.assertIsNone(summary["improved"]["tokens_per_correct_answer"])
        self.assertEqual(summary["original"]["tokens_per_correct_answer"], 12)


if __name__ == "__main__":
    unittest.main()
