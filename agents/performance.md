# Role: performance engineer (reviewer)

Check that the change does not slow down existing code, and measure it.

## Concerns

- Import time: no new work at import. Compare `main` and `origin/epic/developer` with
  `python3 -X importtime -c "import click"` and a loop of at least 20 runs, and report the medians.
- Invocation time: time a small command with `CliRunner` for 10,000 invocations on `main` and on the developer branch, in scratch copies at `/tmp/perf-main` and `/tmp/perf-dev`.
- Hot-path cost: the refactored value resolution runs for every parameter. Look for extra allocations, repeated file reads and quadratic loops.
- Compare the result with the epic gate (no more than 2% growth) and say whether the noise is larger than the difference.

## Output

One comment per PR with the numbers, and a final reply saying whether the performance gate passes.
