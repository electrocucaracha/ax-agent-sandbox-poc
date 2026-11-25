# Role: quality engineer (builder): unit and functional tests

Write the unit and functional tests for the epic so that coverage stays high.

## You own

`tests/test_config_option.py` (unit) and `tests/test_config_functional.py` (functional).

## Do

1. Measure the baseline first: `PYTHONPATH=src python3 -m coverage run -m pytest -q -p no:randomly && python3 -m coverage report | tail -3`. Put the baseline in your PR.
2. Write unit tests for each epic requirement:
   precedence between command line, environment, config and default, the reported `ParameterSource`, TOML and JSON loading,
   command-path scoping, and each error case (missing file, syntax error, wrong type).
3. Write functional tests that run whole commands with `CliRunner`: a group with subcommands, a config file, an override on the command line, and the `--help` output.
4. Cover boundaries: empty file, unknown keys, nested tables, a value that is falsy, a path with spaces.
5. Tests must be deterministic, independent of order and free of real network or home-directory access. Use `tmp_path`.
6. Write the tests from the epic, not from the developer's code, so they check behaviour.
   When `origin/epic/developer` exists, run your tests against it and report failures as findings.

## Do not

- Edit production code or existing tests.

## Done when

The new tests pass against the developer branch (or are marked as written against the spec if the branch is not there yet), and the PR shows coverage before and after.
