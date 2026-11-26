"""Run script docstring examples without accessing the cluster or model provider."""

import doctest
import importlib.util
import io
import json
import runpy
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from click.testing import CliRunner

ROOT = Path(__file__).resolve().parents[1]


class ScriptEntryPointTests(unittest.TestCase):
    def test_issue_list_preserves_filter_order_and_request_credentials(self):
        module = runpy.run_path(str(ROOT / "scripts/issues.py"))
        response = [
            {"number": 7, "title": "Status"},
            {"number": 4, "title": "[role:quality] Tests"},
            {"number": 2, "title": "[role:developer] Implement"},
        ]
        environment = {
            "GIT_API": "https://example.test/api/v1",
            "GIT_USER": "demo-user",
            "GIT_PASS": "demo-pass",
        }
        with (
            patch("ssl.create_default_context"),
            patch(
                "urllib.request.urlopen",
                return_value=io.BytesIO(json.dumps(response).encode()),
            ) as urlopen,
        ):
            result = CliRunner(env=environment).invoke(
                module["cli"], ["list", "alpha/app"]
            )
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertEqual(result.output, "2|developer\n4|quality\n")
        request = urlopen.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "https://example.test/api/v1/repos/alpha/app/issues?type=issues&state=open&limit=50",
        )
        self.assertEqual(
            request.get_header("Authorization"), "Basic ZGVtby11c2VyOmRlbW8tcGFzcw=="
        )

    def test_mock_response_preserves_streaming_and_nonstreaming_contracts(self):
        module = runpy.run_path(str(ROOT / "resources/mock-llm/server.py"))
        handler_type = module["MockLLMHandler"]
        for streaming in (False, True):
            with self.subTest(streaming=streaming):
                payload = json.dumps(
                    {"model": "test-model", "stream": streaming}
                ).encode()
                handler = Mock(spec=handler_type)
                handler.path = "/v1/chat/completions"
                handler.headers = {
                    "Content-Length": str(len(payload)),
                    "Authorization": "demo-placeholder",
                }
                handler.rfile = io.BytesIO(payload)
                with patch("builtins.print"):
                    handler_type.do_POST(handler)
                args = handler._send.call_args.args
                self.assertEqual(args[0], 200)
                if streaming:
                    self.assertEqual(args[2], "text/event-stream")
                    self.assertTrue(args[1].endswith(b"data: [DONE]\n\n"))
                    first = json.loads(
                        args[1].decode().splitlines()[0].removeprefix("data: ")
                    )
                    message = first["choices"][0]["delta"]["content"]
                else:
                    body = json.loads(args[1])
                    self.assertEqual(body["model"], "test-model")
                    message = body["choices"][0]["message"]["content"]
                self.assertEqual(
                    message, "mock-llm received Authorization: demo-placeholder"
                )


def load_tests(loader, tests, pattern):
    """Include runtime docstrings in the existing unittest discovery command."""
    paths = sorted((ROOT / "scripts").glob("*.py")) + [
        ROOT / "resources/mock-llm/server.py",
        ROOT / "tests/replay_evidence.py",
        ROOT / "tests/verify_team_output.py",
    ]
    for path in paths:
        name = "doctest_" + path.stem.replace("-", "_")
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        tests.addTests(doctest.DocTestSuite(module))
    return tests
