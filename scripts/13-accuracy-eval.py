#!/usr/bin/env -S uv --quiet run --script
"""Score answers from raw and rtk-compressed command output against known truth."""

# /// script
# requires-python = ">=3.10"
# dependencies = ["click>=8.1"]
# ///

import datetime
import functools
import importlib.util
import json
import logging
import os
import re
import statistics
import subprocess
import tempfile
from pathlib import Path

import click

log = logging.getLogger("accuracy-eval")

AUTHORS = ("Ada Lovelace", "Grace Hopper", "Linus Torvalds")
FAILED_TESTS = (7, 19, 33, 48, 61, 77, 102)
ERROR_CODES = {
    50: "E4021",
    130: "E5003",
    201: "E4021",
    300: "E7010",
    377: "E5003",
    450: "E4102",
}
UNTRACKED = ("notes-alpha.md", "notes-bravo.md", "notes-charlie.md", "notes-delta.md")
VARIANTS = ("baseline", "rtk")
COMMAND_ENV = {
    **os.environ,
    "NO_COLOR": "1",
    "GIT_PAGER": "cat",
    "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1",
}


@functools.cache
def load_token_benchmark():
    """Import the sibling token benchmark once for its shared LLM helpers."""
    spec = importlib.util.spec_from_file_location(
        "token_benchmark", Path(__file__).with_name("11-token-benchmark.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(cwd, *args, author=AUTHORS[0]):
    """Run git with a fixed identity and no signing."""
    email = author.split()[0].lower() + "@example.test"
    env = {
        **os.environ,
        "GIT_AUTHOR_NAME": author,
        "GIT_AUTHOR_EMAIL": email,
        "GIT_COMMITTER_NAME": author,
        "GIT_COMMITTER_EMAIL": email,
    }
    subprocess.run(
        ["git", "-c", "commit.gpgsign=false", *args],
        cwd=cwd,
        env=env,
        check=True,
        capture_output=True,
    )


def build_fixtures(root):
    """Create deterministic repositories and logs, and return cases with known answers."""
    history = root / "history"
    history.mkdir()
    git(history, "init", "-q")
    for index in range(120):
        author = AUTHORS[index % len(AUTHORS)]
        (history / f"file-{index % 5}.txt").write_text(f"revision {index}\n")
        git(history, "add", ".")
        git(history, "commit", "-q", "-m", f"change {index}", author=author)

    tests = root / "tests"
    tests.mkdir()
    functions = []
    for index in range(120):
        if index in FAILED_TESTS:
            functions.append(f"def test_regression_{index:03d}():\n    assert False\n")
        else:
            functions.append(f"def test_case_{index:03d}():\n    assert True\n")
    (tests / "test_fixture.py").write_text("\n".join(functions))

    lines = []
    for index in range(500):
        code = ERROR_CODES.get(index)
        if code:
            lines.append(
                f"2026-11-26T10:{index // 60:02d}:{index % 60:02d}Z ERROR request failed with {code}"
            )
        else:
            lines.append(
                f"2026-11-26T10:{index // 60:02d}:{index % 60:02d}Z INFO worker-{index % 4} processed batch {index}"
            )
    (root / "app.log").write_text("\n".join(lines) + "\n")

    workspace = root / "workspace"
    workspace.mkdir()
    for index in range(30):
        (workspace / f"module-{index:02d}.txt").write_text("v1\n")
    git(workspace, "init", "-q")
    git(workspace, "add", ".")
    git(workspace, "commit", "-q", "-m", "baseline")
    for index in range(9):
        (workspace / f"module-{index:02d}.txt").write_text("v2\n")
    for name in UNTRACKED:
        (workspace / name).write_text("draft\n")

    grace_commits = sum(
        1 for index in range(120) if AUTHORS[index % 3] == "Grace Hopper"
    )
    return [
        {
            "id": "git-log-authors",
            "argv": ["git", "log", "--stat"],
            "cwd": history,
            "exit_code": 0,
            "question": "How many commits were authored by Grace Hopper? Reply with only the integer.",
            "check": {"type": "int", "expected": grace_commits},
        },
        {
            "id": "pytest-failures",
            "argv": ["pytest", "-v", "--color=no", "test_fixture.py"],
            "cwd": tests,
            "exit_code": 1,
            "question": "Which tests failed? Reply only with a JSON array of the failing test names, sorted alphabetically.",
            "check": {
                "type": "json_list",
                "expected": [f"test_regression_{index:03d}" for index in FAILED_TESTS],
            },
        },
        {
            "id": "log-error-codes",
            "argv": ["cat", "app.log"],
            "cwd": root,
            "exit_code": 0,
            "question": "Which distinct error codes appear in the log? Reply only with a JSON array of the codes, sorted alphabetically.",
            "check": {
                "type": "json_list",
                "expected": sorted(set(ERROR_CODES.values())),
            },
        },
        {
            "id": "git-status-untracked",
            "argv": ["git", "status"],
            "cwd": workspace,
            "exit_code": 0,
            "question": "Which files are untracked? Reply only with a JSON array of the file names, sorted alphabetically.",
            "check": {"type": "json_list", "expected": sorted(UNTRACKED)},
        },
    ]


def run_variant(case, variant):
    """Return combined output of the raw or rtk-prefixed command."""
    argv = (["rtk"] if variant == "rtk" else []) + case["argv"]
    process = subprocess.run(
        argv,
        cwd=case["cwd"],
        env=COMMAND_ENV,
        text=True,
        capture_output=True,
        timeout=120,
    )
    if process.returncode != case["exit_code"]:
        raise RuntimeError(
            f"{case['id']}/{variant} exited {process.returncode}, expected {case['exit_code']}: "
            + process.stderr[-500:]
        )
    return process.stdout + process.stderr


def extract_json(answer):
    """Parse a JSON value, accepting an optional fenced code block."""
    match = re.search(r"```(?:json)?\s*(.*?)```", answer, re.DOTALL)
    text = match.group(1) if match else answer
    try:
        return json.loads(text.strip())
    except json.JSONDecodeError:
        return None


def extract_int(answer):
    """Return the integer on the last non-empty line of the answer, if any."""
    lines = [line.strip() for line in answer.splitlines() if line.strip()]
    if not lines or not lines[-1].lstrip("-").isdigit():
        return None
    return int(lines[-1])


def score(answer, check):
    """Return whether the answer matches the expected value, ignoring list order."""
    if check["type"] == "int":
        return extract_int(answer) == check["expected"]
    parsed = extract_json(answer)
    return isinstance(parsed, list) and sorted(map(str, parsed)) == sorted(
        check["expected"]
    )


def canonical(answer, check):
    """Return a comparable form of the answer, independent of correctness."""
    if check["type"] == "int":
        return answer.strip()
    parsed = extract_json(answer)
    if isinstance(parsed, list):
        return json.dumps(sorted(map(str, parsed)))
    return answer.strip()


def collect(cases, repetitions, endpoint, headers, model):
    """Ask every case against both variants, alternating order between repeats."""
    measurements = []
    for case in cases:
        outputs = {variant: run_variant(case, variant) for variant in VARIANTS}
        for repeat in range(1, repetitions + 1):
            order = VARIANTS if repeat % 2 else VARIANTS[::-1]
            for variant in order:
                counts, answer = load_token_benchmark().request_usage(
                    endpoint,
                    headers,
                    model,
                    [
                        {
                            "role": "user",
                            "content": outputs[variant] + "\n\n" + case["question"],
                        }
                    ],
                    max_tokens=256,
                )
                measurements.append(
                    {
                        "case": case["id"],
                        "variant": variant,
                        "repeat": repeat,
                        "output_bytes": len(outputs[variant].encode()),
                        "usage": counts,
                        "answer": answer,
                        "correct": score(answer, case["check"]),
                        "canonical": canonical(answer, case["check"]),
                    }
                )
                log.info(
                    "%s/%s/%s: correct=%s",
                    case["id"],
                    variant,
                    repeat,
                    measurements[-1]["correct"],
                )
    return measurements


def summarize(measurements):
    """Aggregate accuracy, token usage, and baseline-versus-rtk agreement."""
    summary = {}
    for variant in VARIANTS:
        rows = [m for m in measurements if m["variant"] == variant]
        summary[variant] = {
            "requests": len(rows),
            "correct": sum(m["correct"] for m in rows),
            "accuracy": round(sum(m["correct"] for m in rows) / len(rows), 3),
            "mean_input_tokens": round(
                statistics.mean(m["usage"]["input_tokens"] for m in rows), 1
            ),
            "mean_total_tokens": round(
                statistics.mean(sum(m["usage"].values()) for m in rows), 1
            ),
            "mean_output_bytes": round(
                statistics.mean(m["output_bytes"] for m in rows), 1
            ),
        }
    pairs = {}
    for m in measurements:
        pairs.setdefault((m["case"], m["repeat"]), {})[m["variant"]] = m
    agreeing = sum(
        1
        for pair in pairs.values()
        if pair["baseline"]["canonical"] == pair["rtk"]["canonical"]
    )
    summary["agreement"] = {"pairs": len(pairs), "agreeing": agreeing}
    return summary


def render_markdown(results):
    """Render the results as Markdown tables."""
    lines = [
        f"Model: `{results['model']}`, repetitions: {results['repetitions']}, generated: {results['generated_at']}",
        "",
        "| Variant | Accuracy | Mean input tokens | Mean total tokens | Mean output bytes |",
        "| --- | --- | --- | --- | --- |",
    ]
    for variant in VARIANTS:
        s = results["summary"][variant]
        lines.append(
            f"| {variant} | {s['correct']}/{s['requests']} ({s['accuracy']:.0%}) | "
            f"{s['mean_input_tokens']} | {s['mean_total_tokens']} | {s['mean_output_bytes']} |"
        )
    agreement = results["summary"]["agreement"]
    lines += [
        "",
        f"Baseline and rtk answers agree on {agreement['agreeing']}/{agreement['pairs']} paired requests.",
        "",
        "| Case | Baseline correct | rtk correct | Baseline answers | rtk answers |",
        "| --- | --- | --- | --- | --- |",
    ]
    for case in results["cases"]:
        rows = [m for m in results["measurements"] if m["case"] == case["id"]]
        base = [m for m in rows if m["variant"] == "baseline"]
        rtk = [m for m in rows if m["variant"] == "rtk"]
        lines.append(
            f"| {case['id']} | {sum(m['correct'] for m in base)}/{len(base)} | "
            f"{sum(m['correct'] for m in rtk)}/{len(rtk)} | "
            + ", ".join(sorted({m["canonical"] for m in base}))
            + " | "
            + ", ".join(sorted({m["canonical"] for m in rtk}))
            + " |"
        )
    return "\n".join(lines) + "\n"


@click.command()
@click.option(
    "--output",
    type=click.Path(dir_okay=False, path_type=Path),
    required=True,
    help="JSON results path; a Markdown summary is written next to it.",
)
@click.option(
    "--repetitions",
    type=click.IntRange(min=1),
    default=3,
    show_default=True,
    help="Paired requests per case and variant.",
)
@click.option("-v", "--verbose", is_flag=True, help="Log debug details.")
def main(output, repetitions, verbose):
    """Run the accuracy evaluation and write JSON and Markdown results."""
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )
    llm = load_token_benchmark().load_llm_settings()
    headers = {
        "x-api-key": llm["key"],
        "anthropic-version": "vertex-2023-10-16",
        **llm["headers"],
    }
    with tempfile.TemporaryDirectory() as tmp:
        cases = build_fixtures(Path(tmp))
        measurements = collect(
            cases, repetitions, llm["endpoint"], headers, llm["model"]
        )
    results = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "model": llm["model"],
        "repetitions": repetitions,
        "cases": [
            {key: value for key, value in case.items() if key not in ("cwd", "argv")}
            | {"command": " ".join(case["argv"])}
            for case in cases
        ],
        "measurements": measurements,
        "summary": summarize(measurements),
    }
    output.write_text(json.dumps(results, indent=2) + "\n")
    markdown = render_markdown(results)
    output.with_suffix(".md").write_text(markdown)
    click.echo(markdown)


if __name__ == "__main__":
    main()
