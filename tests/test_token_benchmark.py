import io
import json
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch
from urllib.error import HTTPError


request_usage = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "scripts/11-token-benchmark.py")
)["request_usage"]


class TokenUsageTests(unittest.TestCase):
    def request(self, usage):
        response = {
            "usage": usage,
            "content": [{"type": "text", "text": "10"}],
        }
        with patch(
            "urllib.request.urlopen",
            return_value=io.BytesIO(json.dumps(response).encode()),
        ):
            return request_usage(
                "https://example.test/v1",
                {"x-api-key": "placeholder"},
                "test-model",
                [{"role": "user", "content": "Count commits."}],
            )

    def test_preserves_cache_usage_separately(self):
        usage, answer = self.request({
            "input_tokens": 10,
            "cache_read_input_tokens": 20,
            "cache_creation_input_tokens": 30,
            "output_tokens": 2,
        })
        self.assertEqual(sum(usage.values()), 62)
        self.assertEqual(answer, "10")

    def test_rejects_missing_or_invalid_usage(self):
        for usage in (
            {"input_tokens": 10},
            {"output_tokens": 2},
            {"input_tokens": -1, "output_tokens": 2},
            {"input_tokens": "10", "output_tokens": 2},
        ):
            with self.subTest(usage=usage), self.assertRaises(ValueError):
                self.request(usage)

    def test_http_failure_does_not_expose_provider_body(self):
        error = HTTPError(
            "https://example.test/v1/messages",
            401,
            "sensitive provider message",
            {},
            io.BytesIO(b"sensitive provider body"),
        )
        with patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, "^LLM request failed: HTTP 401$"):
                request_usage("https://example.test/v1", {}, "test-model", [])


if __name__ == "__main__":
    unittest.main()
