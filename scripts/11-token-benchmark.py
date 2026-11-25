#!/usr/bin/env python3
"""Measure paired context-token usage in one AX sandbox, without exposing keys."""

import argparse
import base64
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def command(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout


def request_usage(endpoint, headers, model, messages):
    request = urllib.request.Request(
        endpoint.rstrip("/") + "/messages",
        data=json.dumps(
            {"model": model, "max_tokens": 128, "temperature": 0, "messages": messages}
        ).encode(),
        headers={"content-type": "application/json", **headers},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"LLM request failed: HTTP {error.code}") from None
    usage = result["usage"]
    counts = {
        key: usage.get(key, 0)
        for key in (
            "input_tokens",
            "cache_read_input_tokens",
            "cache_creation_input_tokens",
            "output_tokens",
        )
    }
    if "input_tokens" not in usage or "output_tokens" not in usage or any(
        not isinstance(value, int) or value < 0 for value in counts.values()
    ):
        raise ValueError("Provider did not return valid token usage")
    answer = "".join(
        block["text"] for block in result["content"] if block["type"] == "text"
    ).strip()
    return counts, answer


def worker(repetitions):
    settings = json.loads(os.environ["BENCH_SETTINGS"])
    root = Path("/workspace/token-benchmark")
    root.mkdir()
    tests = root / "test_sample.py"
    tests.write_text(
        "\n\n".join(f"def test_pass_{i}():\n    assert True" for i in range(80))
        + "\n\n"
        + "\n\n".join(f"def test_fail_{i}():\n    assert False" for i in range(2))
        + "\n"
    )
    env = {
        **os.environ,
        "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1",
        "NO_COLOR": "1",
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "safe.directory",
        "GIT_CONFIG_VALUE_0": "/opt/demo-repo",
    }
    workloads = [
        (
            "git-log",
            "/opt/demo-repo",
            ["git", "log", "-10", "--stat"],
            "How many commits are shown? Reply with only the integer.",
            10,
            0,
        ),
        (
            "pytest",
            str(root),
            ["pytest", "-v", "--color=no", str(tests)],
            'How many tests passed and failed? Reply only with JSON: {"passed":N,"failed":N}.',
            {"passed": 80, "failed": 2},
            1,
        ),
    ]
    results = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "model": settings["model"],
        "repetitions": repetitions,
        "versions": {
            tool: command([tool, "--version"]).strip() for tool in ("rtk", "pytest")
        },
        "image_digest": settings["image_digest"],
        "architecture": os.uname().machine,
        "measurements": [],
    }
    headers = {
        "x-api-key": "placeholder",
        "anthropic-version": "vertex-2023-10-16",
        **settings["headers"],
    }
    for workload, cwd, args, question, expected, exit_code in workloads:
        outputs = {}
        for variant in ("baseline", "rtk"):
            process = subprocess.run(
                (["rtk"] if variant == "rtk" else []) + args,
                cwd=cwd,
                env=env,
                text=True,
                capture_output=True,
                timeout=120,
            )
            if process.returncode != exit_code:
                raise RuntimeError(
                    f"{workload}/{variant} exited {process.returncode}, expected {exit_code}: "
                    + process.stderr[-1000:]
                )
            outputs[variant] = process.stdout + process.stderr
        for repeat in range(1, repetitions + 1):
            order = ("baseline", "rtk") if repeat % 2 else ("rtk", "baseline")
            for variant in order:
                counts, answer = request_usage(
                    settings["endpoint"],
                    headers,
                    settings["model"],
                    [{"role": "user", "content": outputs[variant] + "\n\n" + question}],
                )
                try:
                    correct = json.loads(answer) == expected
                except json.JSONDecodeError:
                    correct = False
                results["measurements"].append(
                    {
                        "workload": workload,
                        "variant": variant,
                        "repeat": repeat,
                        "command_exit_code": exit_code,
                        "output_bytes": len(outputs[variant].encode()),
                        "usage": counts,
                        "correct": correct,
                        "answer": answer,
                    }
                )
                Path("/workspace/results.json").write_text(json.dumps(results, indent=2))
                print(f"{workload}/{variant}/{repeat}: correct={correct}", flush=True)
    results["headroom"] = settings["headroom"]
    if settings["headroom_status"] == "ready":
        records = [
            {"id": i, "status": "healthy", "description": "Routine health check succeeded"}
            for i in range(100)
        ]
        messages = [
            {"role": "user", "content": "Inspect these health checks."},
            {"role": "assistant", "content": json.dumps(records, indent=2)},
            {
                "role": "user",
                "content": "How many health-check records are in the previous message? Reply only with the integer.",
            },
        ]
        for repeat in range(1, repetitions + 1):
            order = ("direct", "headroom") if repeat % 2 else ("headroom", "direct")
            for variant in order:
                endpoint = (
                    settings["endpoint"]
                    if variant == "direct"
                    else "https://headroom.default.svc.cluster.local/v1"
                )
                counts, answer = request_usage(endpoint, headers, settings["model"], messages)
                results["measurements"].append(
                    {
                        "workload": "headroom-json",
                        "variant": variant,
                        "repeat": repeat,
                        "usage": counts,
                        "correct": answer == "100",
                        "answer": answer,
                    }
                )
                Path("/workspace/results.json").write_text(json.dumps(results, indent=2))
                print(f"headroom-json/{variant}/{repeat}: answer={answer}", flush=True)
    Path("/workspace/results.json").write_text(json.dumps(results, indent=2))


def run(args):
    root = Path(__file__).resolve().parent.parent
    loaded = subprocess.run(
        ["bash", "-c", 'set -a; source "$1"; env -0', "bash", str(root / ".env.opencode")],
        check=True,
        capture_output=True,
    )
    env = dict(
        entry.decode().split("=", 1) for entry in loaded.stdout.split(b"\0") if b"=" in entry
    )
    base = env.get("LITELLM_PROXY_API_BASE") or (
        "https://" + env["LLM_HOST"] + env.get("LLM_PATH", "/v1")
    )
    url = urllib.parse.urlsplit(base)
    if (
        url.scheme != "https"
        or not url.hostname
        or url.username
        or url.password
        or url.query
        or url.fragment
    ):
        raise ValueError("Expected an HTTPS base URL without credentials, query, or fragment")
    endpoint = base.rstrip("/")
    if not endpoint.endswith("/v1"):
        endpoint += "/v1"
    model = env.get("LLM_MODEL_ID") or env.get("LITELLM_PROXY_MODEL", "").removeprefix("anthropic/")
    key = env.get("LITELLM_PROXY_API_KEY") or env.get("LLM_API_KEY")
    if not key or not model:
        raise ValueError("Configure the local LLM API key and Anthropic model before running")
    headers = json.loads(
        env.get("CHANGELOG_LITELLM_HEADERS_JSON")
        or env.get("LLM_EXTRA_HEADERS_JSON")
        or env.get("LITELLM_EXTRA_HEADERS_JSON")
        or "{}"
    )
    if not isinstance(headers, dict) or not all(
        isinstance(k, str) and isinstance(v, str) for k, v in headers.items()
    ):
        raise ValueError("Extra headers must be a JSON object of strings")
    if any(k.lower() in ("authorization", "x-api-key") for k in headers):
        raise ValueError("Use the API-key variable, not extra headers, for credentials")
    ax = shutil.which("ax") or str(Path.home() / ".ax/bin/ax")
    name = f"token-benchmark-{uuid.uuid4().hex[:12]}"
    headroom_status = "not requested"
    headroom = {"status": headroom_status}
    if args.headroom:
        deployment = json.loads(command(["kubectl", "-n", "default", "get", "deploy", "headroom", "-o", "json"]))
        container = deployment["spec"]["template"]["spec"]["containers"][0]
        target = next(
            (v.get("value", "") for v in container.get("env", []) if v["name"] == "ANTHROPIC_TARGET_API_URL"),
            "",
        )
        headroom_status = "ready" if target.rstrip("/") in (endpoint, endpoint[:-3]) else "upstream mismatch; skipped"
        headroom = {
            "status": headroom_status,
            "mode": next(
                (v.get("value", "") for v in container.get("env", []) if v["name"] == "HEADROOM_MODE"),
                "default",
            ),
            "version": command([
                "kubectl", "-n", "default", "exec", "deploy/headroom", "--",
                "python", "-c",
                "from importlib.metadata import version; print(version('headroom-ai'))",
            ]).strip(),
        }
    settings = {
        "endpoint": endpoint,
        "model": model,
        "headers": headers,
        "headroom_status": headroom_status,
        "headroom": headroom,
        "image_digest": env["OPENCODE_IMAGE"].partition("@")[2] or "unpinned",
    }
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": name, "namespace": "default", "labels": {"ax.io/credential": "true"}},
        "stringData": {"api-key": key},
    }
    hostnames = [url.netloc]
    if headroom_status == "ready":
        hostnames.append("headroom.default.svc.cluster.local")
    gateway = {
        "apiVersion": "ax.io/v1alpha1", "kind": "Gateway",
        "metadata": {"name": name, "atespace": "default"},
        "spec": {"egress": [{"https": {
            "hostnames": hostnames,
            "effects": {"replaceHeaders": [{
                "header": "x-api-key",
                "credentialUri": f"ate-secret://k8s.io/default/default/{name}/api-key",
            }]},
        }}]},
    }
    workspace = {
        "apiVersion": "ax.io/v1alpha1", "kind": "Workspace",
        "metadata": {"name": name, "atespace": "default"},
        "spec": {"profile": {"image": env["OPENCODE_IMAGE"]}},
    }
    encoded = base64.b64encode(Path(__file__).read_bytes()).decode()
    task = {
        "apiVersion": "ax.io/v1alpha1", "kind": "Task",
        "metadata": {"name": name, "atespace": "default"},
        "spec": {
            "workspace": {"name": name}, "gateway": {"name": name},
            "commands": ["sh", "-c", f"mkdir -p /workspace; echo {encoded} | base64 -d > /workspace/benchmark.py; python3 /workspace/benchmark.py --worker --repetitions {args.repetitions} > /workspace/benchmark.log 2>&1; echo $? > /workspace/benchmark.exit; sleep 1800"],
            "env": [{"name": "BENCH_SETTINGS", "value": json.dumps(settings)}],
            "debug": True,
        },
    }
    resources = []
    try:
        command(["kubectl", "apply", "-f", "-"], input=json.dumps(secret))
        resources.append(["kubectl", "-n", "default", "delete", "secret", name])
        command([ax, "apply", "-f", "-"], input=json.dumps(gateway))
        resources.append([ax, "delete", "gateway", name])
        command([ax, "apply", "-f", "-"], input=json.dumps(workspace))
        resources.append([ax, "delete", "workspace", name])
        deadline = time.monotonic() + 180
        while not re.search(
            r"(?m)^\s*Phase:\s+Ready\s*$",
            command([ax, "describe", "workspace", name]),
        ):
            if time.monotonic() >= deadline:
                raise TimeoutError("Benchmark workspace did not become ready")
            time.sleep(3)
        command([ax, "apply", "-f", "-"], input=json.dumps(task))
        resources.append([ax, "delete", "task", name])
        command([ax, "resume", "task", name])
        deadline = time.monotonic() + 1200
        while time.monotonic() < deadline:
            check = subprocess.run(
                [ax, "ssh", name, "--", "cat", "/workspace/benchmark.exit"],
                text=True, capture_output=True,
            )
            if check.returncode == 0:
                if check.stdout.strip() != "0":
                    log = command([ax, "ssh", name, "--", "cat", "/workspace/benchmark.log"])
                    args.output.with_suffix(".log").write_text(log)
                    raise RuntimeError(f"Benchmark failed; diagnostics saved beside {args.output}")
                output = command([ax, "ssh", name, "--", "cat", "/workspace/results.json"])
                args.output.write_text(output)
                results = json.loads(output)
                print(f"Saved {len(results['measurements'])} measurements to {args.output}")
                print(f"Correct answers: {sum(m['correct'] for m in results['measurements'])}/{len(results['measurements'])}")
                print(f"Headroom: {results['headroom']['status']}")
                if not all(m["correct"] for m in results["measurements"]):
                    raise RuntimeError("Answer validation failed; do not treat these results as successful savings")
                return
            states = command([ax, "get", "tasks"]).splitlines()
            if any(row.split()[:3] == [name, "default", "Failed"] for row in states):
                raise RuntimeError("Benchmark sandbox failed before completion")
            time.sleep(5)
        raise TimeoutError("Benchmark timed out")
    finally:
        failed_cleanup = []
        for cleanup in reversed(resources):
            if subprocess.run(cleanup, capture_output=True).returncode:
                failed_cleanup.append(cleanup[-2])
        if failed_cleanup:
            raise RuntimeError(f"Cleanup failed for {name}: {', '.join(failed_cleanup)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--headroom", action="store_true")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    if arguments.repetitions < 1:
        parser.error("--repetitions must be positive")
    if arguments.worker:
        worker(arguments.repetitions)
    else:
        if arguments.output is None:
            parser.error("--output is required")
        run(arguments)
