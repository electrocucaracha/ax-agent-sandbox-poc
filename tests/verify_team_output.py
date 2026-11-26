#!/usr/bin/env python3
"""Independently run seed and combined developer/quality tests inside a demo task."""

import json
import os
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path


def command(args, cwd=None):
    """Return successful command output, retaining failure diagnostics locally."""
    process = subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=180)
    if process.returncode:
        Path("/workspace/independent-verification.log").write_text(
            process.stdout + process.stderr
        )
        raise RuntimeError(f"{args[0]} failed with exit {process.returncode}")
    return process.stdout.strip()


def verify():
    """Run unmodified seed and combined suites and preserve nonzero exits.

    A successful verifier invocation means evidence collection completed,
    not that either underlying pytest suite passed.
    """
    source = Path("/workspace/repo")
    remote = command(["git", "remote", "get-url", "origin"], cwd=source)
    report = {
        "scope": "Independent seed and combined developer/quality pytest suites",
        "suites": {},
    }
    for variant in ("seed", "combined"):
        directory = Path("/workspace") / (
            "independent-" + variant + "-" + uuid.uuid4().hex[:8]
        )
        command(["git", "clone", "--shared", str(source), str(directory)])
        command(["git", "remote", "add", "team", remote], cwd=directory)
        if variant == "seed":
            command(
                [
                    "git",
                    "-c",
                    "http.extraHeader=Authorization: token placeholder",
                    "fetch",
                    "team",
                    "main:refs/remotes/team/main",
                ],
                cwd=directory,
            )
            command(["git", "checkout", "-b", "seed", "team/main"], cwd=directory)
            report["seed_commit"] = command(["git", "rev-parse", "HEAD"], cwd=directory)
        else:
            command(
                [
                    "git",
                    "-c",
                    "http.extraHeader=Authorization: token placeholder",
                    "fetch",
                    "team",
                    "epic/developer:refs/remotes/team/developer",
                    "epic/quality:refs/remotes/team/quality",
                ],
                cwd=directory,
            )
            report["developer_commit"] = command(
                ["git", "rev-parse", "team/developer"], cwd=directory
            )
            report["quality_commit"] = command(
                ["git", "rev-parse", "team/quality"], cwd=directory
            )
            command(
                ["git", "checkout", "-b", "combined", "team/developer"], cwd=directory
            )
            command(
                [
                    "git",
                    "-c",
                    "user.name=validator",
                    "-c",
                    "user.email=validator@example.com",
                    "merge",
                    "--no-commit",
                    "--no-ff",
                    "team/quality",
                ],
                cwd=directory,
            )
        xml = Path("/workspace") / (variant + "-pytest.xml")
        start = time.monotonic()
        args = [
            "python3",
            "-m",
            "pytest",
            "-q",
            "-p",
            "no:randomly",
            "--color=no",
            f"--junitxml={xml}",
        ]
        try:
            process = subprocess.run(
                args,
                cwd=directory,
                env={
                    **os.environ,
                    "PYTHONPATH": str(directory / "src"),
                    "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1",
                },
                text=True,
                capture_output=True,
                timeout=180,
            )
            code = process.returncode
            Path("/workspace/" + variant + "-pytest.log").write_text(
                process.stdout + process.stderr
            )
        except subprocess.TimeoutExpired:
            code = 124
        row = {"exit_code": code, "seconds": round(time.monotonic() - start, 3)}
        if xml.is_file():
            cases = list(ET.parse(xml).getroot().iter("testcase"))
            row.update(
                {
                    "tests": len(cases),
                    "failed": sum(case.find("failure") is not None for case in cases),
                    "errors": sum(case.find("error") is not None for case in cases),
                    "skipped": sum(case.find("skipped") is not None for case in cases),
                }
            )
            row["passed"] = (
                row["tests"] - row["failed"] - row["errors"] - row["skipped"]
            )
        else:
            row["blocker"] = "No JUnit report was produced"
        report["suites"][variant] = row
        Path("/workspace/independent-verification.json").write_text(
            json.dumps(report, indent=2) + "\n"
        )
    report["quality_gate_verified"] = all(
        row["exit_code"] == 0 and "tests" in row for row in report["suites"].values()
    )
    Path("/workspace/independent-verification.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )


if __name__ == "__main__":
    verify()
