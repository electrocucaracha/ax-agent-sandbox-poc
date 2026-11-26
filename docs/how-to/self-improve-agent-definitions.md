# Self-improve agent, skill and tool definitions

The platform now has an **on-demand, evaluation-gated instruction improvement
loop**. It changes Markdown definitions, not model weights or executable tools.
It is a small conceptual adaptation of reflection, context curation and
held-out selection, not an installation of GEPA, DSPy, ACE or SkillOpt.

Read the [catalog review](../explanation/self-improvement-catalog.md) and
[measured findings](../explanation/self-improvement-findings.md) first.

## Prerequisites

- A running AX/Substrate cluster, `kubectl`, the AX CLI and Python 3.10 or newer.
- The existing ignored `.env.opencode`, with a digest-pinned `OPENCODE_IMAGE`,
  a real Anthropic-compatible model and its API key. See
  [real endpoint setup](use-real-llm-endpoint.md).
- The image must contain Python and, for `--runtime-smoke`, OpenCode.
- Permission to create a temporary Secret in Kubernetes namespace `default`
  and a Gateway, Workspace and Task in AX atespace `default`.
- Public or otherwise approved evaluation inputs. The model sees definitions,
  scenarios and training feedback; do not put confidential code or secrets in them.

The script uses the same endpoint/key/header variables as the token benchmark.
`LITELLM_PROXY_API_BASE` takes precedence over `LLM_HOST`/`LLM_PATH`;
`LITELLM_PROXY_API_KEY` takes precedence over `LLM_API_KEY`.
Only the gateway receives the real key. The worker sees `placeholder`.
Extra headers must not contain authorization or API-key headers.
The canned mock endpoint is rejected as improvement evidence.

## Run a proposal without changing a definition

From the repository root:

```sh
rtk proxy python3 scripts/12-self-improve.py \
  --suite evaluations/mutation-agent.json \
  --output /tmp/ax-mutation-review-01 \
  --iterations 1 --repetitions 2
```

The output directory must not already exist. Defaults are one iteration, two
repetitions and a 1,800-second worker deadline. Each iteration evaluates the
incumbent, asks for an additive clarification using training feedback, and
evaluates the candidate. Invalid or oversized proposals are explicitly rejected.

For a six-case suite, one iteration uses at most **25 direct model requests**:
12 incumbent evaluations, one proposal and 12 candidate evaluations.
An empty/invalid proposal uses fewer. Maximum iterations and repetitions are five
each; their combined worst-case request count must not exceed 250.
Evaluation responses have a 512-token cap and proposals a 1,024-token cap.
The optional OpenCode smoke is separately limited to 180 seconds.

## Evaluate and opt in to promotion

```sh
rtk proxy python3 scripts/12-self-improve.py \
  --suite evaluations/evidence-skill.json \
  --output /tmp/ax-evidence-release-01 \
  --runtime-smoke --promote
```

Promotion requires:

1. A strict increase in correct **holdout** answers.
2. No loss on any paired case/repetition, including training cases.
3. At most 2,000 UTF-8 bytes of additive text and a 32,000-byte target.
4. The source definition still matches the pre-run content.
5. A passing OpenCode smoke when `--runtime-smoke` is requested.

Common generated punctuation is normalized before evaluating the candidate.
Original instructions cannot be deleted by the optimizer. A successful promotion
atomically replaces only the selected definition; it creates no commit or PR.
Keep normal code review before shipping a changed image or running a production
team. `--promote` is an explicit opt-in to automatic admission under these
bounded gates, **not** a guarantee against every harmful instruction.

A rejected candidate exits successfully if the experiment completed: inspect
`eligible` and `promoted` rather than interpreting exit zero as a quality gain.
Provider, launch, timeout, cleanup and requested-smoke failures exit nonzero.

## Inspect the evidence

Each run saves:

| File                                        | Meaning                                                                   |
| ------------------------------------------- | ------------------------------------------------------------------------- |
| `original.md`                               | Definition before optimization                                            |
| `suite.json`                                | Frozen case and expected-answer snapshot                                  |
| `provenance.json`                           | Harness and provider-adapter content hashes                               |
| `candidate.md`                              | Best admitted incumbent; unchanged original if all proposals fail         |
| `report.json`                               | Every baseline/candidate answer, usage, proposal and gate decision        |
| `requests.jsonl`                            | Raw direct-response/usage trace, including completed calls before failure |
| `cleanup.json`                              | Exact resource name, deletion outcome and trace collection status         |
| `worker.log`, `smoke.log`, `diagnostic.log` | Local diagnostics when applicable                                         |

Rejected proposals remain in `report.json`; `candidate.md` does not contain a
rejected candidate. Diagnostics are ignored by Git and may contain private
runtime details: review/redact them before sharing. The portable reports omit
endpoint URLs and credentials.

Directories and hashes are provenance aids, **not** an access-controlled,
signed, append-only admission ledger. Preserve run artifacts in reviewed
storage if auditability matters.

Temporary resources have a unique `self-improve-...` name. The script deletes
only resources it attempted to create, in reverse order. It does not scale the
worker pool, replace existing gateways or reset demo repositories.
If cleanup fails, use the exact name in `cleanup.json`; do not delete resources
by a broad prefix. No background service is left running.

## Add a task suite

Use the format of [the mutation suite](../../evaluations/mutation-agent.json):

```json
{
  "target": "agents/mutation.md",
  "context": "Return exactly {\"ready\":true|false}.",
  "cases": [
    {
      "id": "baseline-fails",
      "split": "train",
      "input": "The combined baseline fails. Is mutation ready?",
      "expected": { "ready": false }
    },
    {
      "id": "baseline-passes",
      "split": "holdout",
      "input": "The combined baseline passes; scope is configured. Is mutation ready?",
      "expected": { "ready": true }
    }
  ]
}
```

Targets must be existing non-symlink Markdown files matching `agents/<role>.md`,
`skills/<name>/SKILL.md` or `tools/<name>.md`. Shared `_builder`/`_reviewer`
rules, image policy, evaluator code, tests and executable scripts are not targets.
The suite requires both splits, unique case IDs, distinct input texts and
nonempty expected JSON objects.

Author expected answers independently. Include safety and failure cases,
ownership restrictions, timeouts, setup failures and realistic success cases.
Freeze the suite before optimizing; do not weaken expected answers after seeing
failures. Raw JSON shape matters: extra fields, numeric substitutes for booleans,
Markdown fences and incorrect values fail.

The proposer receives **training observations only**. Holdout cases and answers
are excluded from its messages. They are development holdouts, not a permanently
blind benchmark: repeated experiments and human inspection can overfit them.
Validate releases with new, independently authored tasks as well.

## Use the improved definitions

[The team runner](../../scripts/10-team-demo.sh) already loads role files from
`agents/`. It now also appends [the evidence skill](../../skills/evidence/SKILL.md)
to all model-backed prompts, and [the mutmut tool contract](../../tools/mutmut.md)
only to the mutation role. Script-only tasks are unchanged.
These host-side definitions are attached per task, so their promotion does not
require an image rebuild. Run the team normally after reviewing changes.

The three supplied suites cover the mutation role, evidence skill and mutmut
tool-use instructions. New skills/tool descriptions need an explicit consumer
in the relevant task prompt; merely adding an arbitrary file does not activate it.

## Replay the admitted evidence skill without optimizing

Use the fixed before/after replay to distinguish repeatability from a new
optimization result:

```sh
rtk proxy python3 tests/replay_evidence.py \
  --output /tmp/ax-evidence-replay-01 --repetitions 3
```

The replay compares the original snapshot with the admitted 2026-11-26 evidence
skill. It refuses to run if the current skill no longer matches that release.
It does not propose additions, promote a definition, reset team repositories
or scale the shared worker pool.

The replay performs:

- 72 direct model requests: the six historical cases and six new cases,
  three repetitions, both original and improved definitions.
- 12 actual OpenCode file-writing tasks: each new scenario under each definition.
- Alternating variant order, fresh OpenCode homes, exact JSON assertions and
  input-file integrity checks.
- Collection of answer accuracy, unsupported success claims, format failures,
  request/task latency and separate input/output/cache token counts.

The new cases in [the replay manifest](../../evaluations/evidence-replay.json)
are validation-only; they are not an optimizer training suite.
Both variants receive the same scenario and output contract.
The scenario descriptions are controlled fixtures, not fresh executions of the
underlying tenant or persistence checks.
Those checks belong to the separate full team run.

Inspect `report.json` and `cleanup.json` in the output directory.
`historical_direct_summary` measures repeatability,
`fresh_direct_summary` measures transfer to the new fixtures,
and `opencode_summary` measures actual agent file-writing behavior.
Missing OpenCode token events are reported as missing, not as zero usage.
An experiment can complete without establishing a gain; inspect paired wins
and losses rather than treating exit zero as improvement.

The full team demo is a different workload.
It resets `alpha/app` and `beta/app` and scales shared infrastructure.
Follow [the team guide](run-team-demo.md) only after approving those effects.
One new full-team run is not a matched before/after experiment and cannot
attribute a change in coding quality or cost to this skill.

## Boundaries

This is instruction-layer self-improvement with durable admitted definitions,
not a continuously scheduled daemon or unrestricted recursive self-modification.
It does not train models, install new packages, modify executable tools, change
gateways, evolve evaluator code, promote Engram memories or run the entire team
as an optimization metric.

The structured-decision gate is deliberately inexpensive. The optional smoke
proves one OpenCode file-writing task, not end-to-end coding improvement,
mutation-score improvement, robust multi-tenant behavior or statistical
generalization. Require those workload-specific gates before production use.
