"""Test team prompt assembly, runtime budgets and final-check assertions."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class TeamDemoTests(unittest.TestCase):
    def test_final_checks_reject_lost_marker_and_successful_cross_tenant_clone(self):
        script = (ROOT / "scripts/10-team-demo.sh").read_text()
        marker_check = script[
            script.index('\ninfo "Suspend and resume') : script.index(
                '\ninfo "Credentials in a sandbox'
            )
        ]
        tenant_check = script[
            script.index('\ninfo "Tenant boundary:') : script.index(
                '\ninfo "Usage and accuracy'
            )
        ]
        harness = r"""
set -eu
info() { :; }
error() { printf '%s\n' "$*" >&2; }
sleep() { :; }
date() { printf '123\n'; }
render() { :; }
TEAM_RESOURCES=test
ax() {
  case "$*" in
    *"cat /workspace/marker") printf '%s\n' "$RESULT" ;;
    *"describe workspace beta-x") printf 'Phase: %s\n' "$RESULT" ;;
  esac
}
"""
        for check, value, expected_code in (
            (marker_check, "123", 0),
            (marker_check, "changed", 1),
            (tenant_check, "Failed", 0),
            (tenant_check, "Ready", 1),
        ):
            with self.subTest(value=value):
                result = subprocess.run(
                    ["bash", "-s"],
                    input=harness + check,
                    env={**os.environ, "RESULT": value},
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(result.returncode, expected_code, result.stderr)

    def test_mutation_deadline_is_scoped_and_retention_covers_both_budgets(self):
        script = (ROOT / "scripts/10-team-demo.sh").read_text()
        start = script.index("\nEPIC_TIMEOUT=")
        end = script.index("\nin_wave()", start)
        wait = script[
            script.index("\nstart_agents 2\n") : script.index("\nshow_outputs 2\n")
        ]
        result = subprocess.run(
            ["bash", "-s"],
            input="EPIC_TIMEOUT=10\nMUTATION_TIMEOUT=50\nunset HOLD_SECONDS\n"
            + script[start:end]
            + "\nstart_agents() { :; }\n"
            + 'wait_wave() { printf "%s:%s\\n" "$1" "$EPIC_TIMEOUT"; }\n'
            + "wait_wave 1\n"
            + wait
            + '\nwait_wave 3\nprintf "hold:%s\\n" "$HOLD_SECONDS"\n',
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "1:10",
                "2:50",
                "3:10",
                "hold:380",
            ],
        )

    def test_only_mutation_overrides_profile_and_reviewers_keep_their_rules(self):
        script = (ROOT / "scripts/10-team-demo.sh").read_text()
        start = script.index("start_agents() {")
        end = script.index("\n}\n", start) + 3
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / "tasks.jsonl"
            environment = {
                **os.environ,
                "HERE": str(ROOT),
                "TMPDIR": directory,
                "CAPTURE": str(capture),
                "OPENCODE_IMAGE": "example.test/agent@sha256:test",
                "MUTATION_MEMORY": "2Gi",
                "EXTRA_HEADERS_B64": "",
                "LLM_AUTH_MODE": "x-api-key",
            }
            harness = r"""
set -eu
ROLES=(
  "1|alpha|developer|epic:developer"
  "2|alpha|mutation|epic:mutation"
  "3|alpha|principal|epic:principal"
)
ax() {
  if [ "$1" = apply ]; then cat >> "$CAPTURE"; fi
}
render() {
  python3 -c 'import base64,json,os; print(json.dumps({
    "task": os.environ["TASK"],
    "profile": json.loads(os.environ["TASK_PROFILE"]),
    "prompt": base64.b64decode(os.environ["PROMPT_B64"]).decode()
  }))'
}
"""
            subprocess.run(
                ["bash", "-s"],
                input=harness
                + script[start:end]
                + "\nstart_agents 1\nstart_agents 2\nstart_agents 3\n",
                text=True,
                env=environment,
                check=True,
                capture_output=True,
            )
            developer, mutation, reviewer = (
                json.loads(line) for line in capture.read_text().splitlines()
            )
        self.assertEqual(developer["task"], "developer")
        self.assertEqual(developer["profile"], {})
        self.assertEqual(mutation["task"], "mutation")
        self.assertEqual(
            mutation["profile"],
            {
                "image": environment["OPENCODE_IMAGE"],
                "resources": {"limits": {"memory": "2Gi"}},
            },
        )
        self.assertIn("How the team works (builder roles)", mutation["prompt"])
        self.assertIn(
            (ROOT / "skills/evidence/SKILL.md").read_text(), developer["prompt"]
        )
        self.assertIn((ROOT / "tools/mutmut.md").read_text(), mutation["prompt"])
        self.assertNotIn("Tool contract: mutmut", developer["prompt"])
        self.assertEqual(reviewer["task"], "principal")
        self.assertEqual(reviewer["profile"], {})
        self.assertIn((ROOT / "agents/_reviewer.md").read_text(), reviewer["prompt"])
        self.assertNotIn("How the team works (builder roles)", reviewer["prompt"])


if __name__ == "__main__":
    unittest.main()
