# Self-improvement replay: runtime validation and evidence

**Run date:** 2026-11-26 UTC.
**Audience:** engineers evaluating whether the admitted evidence skill helps.

The paired replay reproduces the known reporting correction.
It does not establish an accuracy gain on new scenarios or a whole-team coding gain.
The improved instructions also have a measurable context-cost tradeoff.

## Matched before/after results

The replay compares the frozen original evidence skill with the admitted skill.
It does not optimize, revise expected answers or promote another change.
Both variants use `claude-sonnet-4-6`, the same image, scenarios and output contract.
Variant order alternates.

| Evaluation                         | Original      | Improved      | Evidence                                                  |
| ---------------------------------- | ------------- | ------------- | --------------------------------------------------------- |
| Historical scenarios, direct model | 12/18 correct | 15/18 correct | Three paired wins, zero losses                            |
| New scenarios, direct model        | 18/18 correct | 18/18 correct | No measurable accuracy gain                               |
| All direct answers                 | 30/36 correct | 33/36 correct | 8.3-percentage-point gain, entirely on historical cases   |
| New scenarios, actual OpenCode     | 6/6 correct   | 6/6 correct   | Equal accuracy; all tasks exited zero                     |
| Unsupported success claims         | 0             | 0             | Both variants avoided explicit false success assertions   |
| OpenCode input-file changes        | 0             | 0             | Both variants preserved all scenario and definition files |

Each direct dataset contains six unique scenarios, repeated three times.
The OpenCode experiment contains six unique scenario pairs, each run once.
Repeated answers are not independent tasks or a large statistical sample.
The historical gain fixes `measured-isolation`; the `interrupted-score`
classification mismatch remains.

### Latency and context-token volume

| Metric                                            | Original | Improved | Observed change              |
| ------------------------------------------------- | -------- | -------- | ---------------------------- |
| Direct-request median wall time                   | 0.880 s  | 0.840 s  | 4.5% lower; small difference |
| Direct input tokens                               | 8,949    | 13,665   | 52.7% higher                 |
| Direct output tokens                              | 540      | 540      | Unchanged                    |
| Direct total tokens                               | 9,489    | 14,205   | 49.7% higher                 |
| Direct tokens per correct answer                  | 316.3    | 430.5    | 36.1% higher                 |
| OpenCode median task wall time                    | 12.827 s | 10.068 s | 21.5% lower                  |
| OpenCode total context tokens, including cache    | 129,451  | 109,261  | 15.6% lower                  |
| OpenCode tokens per correct task, including cache | 21,575.2 | 18,210.2 | 15.6% lower                  |

The OpenCode wall time includes CLI startup and file-writing behavior.
All six paired tasks were faster with the improved definition.
Only three of six pairs used fewer total context tokens;
the other three used slightly more.
The result is an observed small-workload performance difference, not a general
speed guarantee.

### Separate OpenCode token categories

| Provider/SDK category | Original | Improved |
| --------------------- | -------- | -------- |
| Uncached input        | 30       | 27       |
| Cache read            | 121,632  | 95,394   |
| Cache creation        | 6,164    | 12,793   |
| Output                | 1,625    | 1,047    |

Cache creation increased while cache reads decreased.
These categories have different billing weights.
**Lower total context-token volume does not prove lower monetary cost.**
No dollars or provider-pricing savings are inferred.
All twelve OpenCode tasks supplied step-finish token evidence;
none was silently counted as zero usage.

### Paired OpenCode tasks

| Scenario                              | Original / improved seconds | Original / improved context tokens |
| ------------------------------------- | --------------------------- | ---------------------------------- |
| One observed tenant boundary          | 13.263 / 8.695              | 21,576 / 14,452                    |
| One observed persistence cycle        | 19.163 / 9.665              | 21,561 / 14,436                    |
| Agent-reported measurement            | 12.390 / 12.147             | 21,486 / 21,884                    |
| Synthetic-to-production extrapolation | 15.306 / 14.071             | 21,778 / 22,155                    |
| Bounded captured assertions           | 11.140 / 10.471             | 21,493 / 14,440                    |
| Recovered versus unattended run       | 11.471 / 9.540              | 21,557 / 21,894                    |

These are file-writing decisions over controlled scenario descriptions.
They are actual OpenCode executions, but they do not rerun the tenant,
persistence or compression operations described in the fixtures.

## Full team rerun

The user approved resetting `alpha/app` and `beta/app`.
The full demo runs once with eight worker replicas, a 1,800-second non-mutation
deadline and a 3,600-second mutation deadline.
It uses the admitted evidence skill in the normal role prompts.

**Status:** failed, exit code **1**, after **3,208.26 seconds (53.5 minutes)**.
The [full-team metrics](team-demo-rerun-2026-11-26.json) record stage timestamps,
exit status and displayed role token counts.
This was one invocation, with no retries or recovered continuation.

| Stage interval                 | Wall time   | Outcome                      |
| ------------------------------ | ----------- | ---------------------------- |
| Triage to builder launch       | 251.176 s   | Ten role assignments created |
| Builders to mutation launch    | 398.143 s   | Six builders completed       |
| Mutation to reviewer launch    | 2,286.841 s | Mutation PR created          |
| Reviewers to orchestrator exit | 252.152 s   | Performance reviewer failed  |

Intervals include orchestration and cleanup overhead, not just model execution.
The first stage starts 19.948 seconds after the wrapper starts.

AX reports that **performance, principal and security** each failed with
`TASK_STATUS_REASON_SANDBOX_CRASHED`: killed for exceeding the sandbox memory
limit.
The performance failure ended the orchestrator; the other two reviewers also
failed while evidence was being collected.
Failed tasks could not be accessed with AX SSH.
Reviewer token usage is unavailable, not zero.
No RAM peak is inferred from the failure reason.

| Operational evidence                        | Result                                                              |
| ------------------------------------------- | ------------------------------------------------------------------- |
| Local PRs created                           | 8: plumbing plus 7 role branches; nothing merged                    |
| Review comments / formal reviews at capture | 0 / 0                                                               |
| Git plumbing                                | `push=ok`, PR HTTP 201, issue read HTTP 200, issue comment HTTP 201 |
| Unlisted-host probe                         | No response: `blocked-host=000refused`                              |
| Final suspend/resume assertion              | Not reached; unverified for this run                                |
| Final sandbox-credential inspection         | Not reached; unverified for this run                                |
| Final cross-tenant clone assertion          | Not reached; unverified for this run                                |
| Cleanup                                     | Alpha/beta demo tasks, workspaces and team gateways removed         |
| Worker pool after cleanup                   | Desired 1, actual 1, ready 1                                        |

Pre-existing default tasks and gateways, and both tenants' `git-gw` gateways,
remain present.
The replay resources were already removed separately.

### Mutation report is not an independent quality pass

The mutation PR reports a selected-code score of **87/116 (75.0%)** before
additional killing tests and **107/116 (92.2%)** afterward.
These are **agent-reported** results over the new config code, not an independent
rerun or a measurement of the evidence skill's effect.
The same PR reports 59 passing tests with **five tests deselected** because of
a config-scoping defect in the developer branch.
It also adds a Click-reloading pytest hook for the mutant sandbox.
The reported score therefore does not establish a passing full baseline,
full feature correctness or merge readiness.

Mutation alone displayed 73.6K output tokens, 25.9M cache-read tokens and
195.9K cache-write tokens.
The linked JSON retains the nine completed model roles' displayed usage.
Those counts are rounded CLI values and omit the failed reviewers.
They are not whole-team savings or billing measurements.

### Independent generated-code test attempt

[The independent result](team-demo-independent-tests-2026-11-26.json) records
both the seed and combined developer/quality branches exiting **2** during
pytest collection.
Neither suite executed its tests.
Each JUnit report contains one collection error.

The installed pytest version is **9.2.0**.
Both variants fail on the seed's `test_boolean_conversion` parametrization:
`PytestRemovedIn10Warning` rejects a `chain` iterable under the repository's
warnings-as-errors policy.
The verifier did not modify generated code, rewrite tests or suppress warnings.
Full-suite quality is therefore **unverified / validation failed**, not passing.

The verifier's first setup attempt also lacked `origin/main` in the local
workspace clone.
It then explicitly fetched the remote refs into fresh scratch copies.
That setup correction succeeded; the subsequent collection failure is retained.

A single fresh team run is not a matched before/after experiment.
The historical team run used different generated branches and required a
mutation retry, so its token totals cannot serve as a causal savings baseline.

## Environment and verification

| Capability                         | Observed result                                                               |
| ---------------------------------- | ----------------------------------------------------------------------------- |
| Docker                             | Functional daemon                                                             |
| Node.js on the host                | v26.12.0                                                                      |
| OpenCode in the pinned image       | 1.19.6                                                                        |
| Model                              | `claude-sonnet-4-6`                                                           |
| AX/Substrate                       | Existing running cluster; gVisor-backed tasks                                 |
| Resource metrics API               | Unavailable; CPU/RAM measurements are not claimed                             |
| Browser E2E                        | Not applicable to this CLI workflow                                           |
| Diagram rendering                  | Two SVGs rendered with Mermaid CLI 11.17.1 and installed Chrome 158.0.8127.88 |
| Unit/regression tests              | 13 passed; exit code 0                                                        |
| Shell syntax and whitespace checks | Passed                                                                        |
| Replay cleanup                     | Complete; report and worker log collected                                     |
| Full-team cleanup                  | Complete; one ready worker remains; pre-existing resources preserved          |

The cached Mermaid CLI initially lacked its pinned headless-shell browser.
Rendering then succeeded with the already installed system Chrome.
No optimizer dependency or browser download was added to the repository.

The documentation revision uses technical-writer guidance:
the explanation contains the architecture and admission diagrams,
the how-to contains runnable procedures,
and the reference describes the validation command separately.

## Evidence and reproduction

- [Replay answers, usage and summaries](self-improvement-runs/evidence-paired-replay-2026-11-26/report.json)
- [Frozen cases](self-improvement-runs/evidence-paired-replay-2026-11-26/cases.json)
- [Original instructions](self-improvement-runs/evidence-paired-replay-2026-11-26/original.md)
- [Improved instructions](self-improvement-runs/evidence-paired-replay-2026-11-26/improved.md)
- [Harness provenance](self-improvement-runs/evidence-paired-replay-2026-11-26/provenance.json)
- [Cleanup receipt](self-improvement-runs/evidence-paired-replay-2026-11-26/cleanup.json)
- [Replay procedure](../how-to/self-improve-agent-definitions.md#replay-the-admitted-evidence-skill-without-optimizing)
- [Architecture and admission diagrams](self-improvement-findings.md#implemented-system)

Image digest:
`sha256:f60d41b313e50a94688f784bf85093957838f55a83dc6d0f37451738b8e9e993`.

Definition hashes:

| Variant  | SHA-256                                                            |
| -------- | ------------------------------------------------------------------ |
| Original | `d7d7b43f4d2334f3a16e029b1746fb718144370a52706ea7f4b7cb8b8677028c` |
| Improved | `37827552e63cb89d797ec3f77b79e6f8e4c21852b94101f090740a4ebf8b204e` |

## Limits and verdict

- Historical correctness improved, but fresh-case accuracy was already perfect
  for the original instructions. Transfer beyond these fixtures is unproven.
- The direct model used more tokens per correct answer.
  The admitted addition is not universally more efficient.
- OpenCode latency and token observations come from six pairs.
  Shared provider load, cache state and execution variance remain confounders.
- The full team ran concurrently with part of the replay.
  Do not treat the measured latency differences as isolated infrastructure benchmarks.
- The exact-answer grader is deterministic, but the classification taxonomy
  still needs independent review for the remaining partial-progress case.
- No full-paper review, model training or executable-tool evolution occurred.

**Replay measurement:** complete, exit code 0; 72 direct requests and 12
OpenCode tasks recorded.
**Replay correctness:** historical gain reproduced; new-case and OpenCode
accuracy tied.
**Full-team verdict:** FAIL, exit code 1; all three reviewer sandboxes exceeded
their memory limits.
**Full-suite validation:** FAIL, exit codes 2 and 2; collection blocked.
**Overall:** FAIL for full feature-quality validation; the paired measurement
completed successfully and reproduced the bounded reporting gain.

```yaml
environment:
  docker: AVAILABLE
  node: AVAILABLE - v26.12.0
  infra-tier: PRIMARY - existing AX/Substrate cluster with gVisor tasks
  browser-tier: SKIPPED - CLI workflow, no browser application
startup: PASS - existing platform executed triage and builder tasks
integration: FAIL - seed exit_code 2, combined exit_code 2, zero executed tests
e2e: PASS - paired OpenCode replay exit_code 0, 12 tasks, controlled file-writing scope
team-demo: FAIL - exit_code 1, reviewer memory-limit failures
overall: FAIL - full quality validation blocked; no waiver or recovered success claimed
```
