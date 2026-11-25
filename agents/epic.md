# Epic: configuration-file support for Click

Project: the Click library at `/workspace/repo` (Python, `src/click`, tests in `tests/`).
This epic is shared by every role on the team. Your role file says what you own.

## Goal

Let a command read option defaults from a configuration file.
Add a `click.config_option()` decorator that adds a `--config PATH` option, loads TOML or JSON, and feeds the values into the normal parameter resolution.

## Requirements

1. **Precedence**: command line, then environment variable, then configuration file, then the declared default.
   Report the new source as `ParameterSource.CONFIG_FILE`.
2. **Formats**: TOML (standard library `tomllib`) and JSON, chosen by file extension.
   Add no new runtime dependency.
3. **Scoping**: values are looked up by command path, so a group can hold `[tool.mycli.subcommand]` tables.
4. **Refactor**: value resolution in `Parameter.consume_value` is a hard-coded chain.
   Refactor it into an ordered list of value sources that the config source plugs into.
   Behaviour for existing code must not change.
5. **Errors**: a missing file, a syntax error and a value of the wrong type raise `click.BadParameter` or `click.UsageError`.
   The message names the file, the key and the expected type.
6. **Compatibility**: the public API of `click` stays backward compatible.
   The existing test suite passes unchanged.

## Quality gates (a reviewer blocks the epic if one fails)

| Area        | Gate                                                                                                                                                        |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tests       | Unit and functional tests for every requirement. Line and branch coverage of the repository does not drop, and the new code has at least 95% coverage.      |
| Mutation    | Mutation score of the new and refactored modules is at least 80%. Surviving mutants are listed with a reason.                                               |
| Performance | `import click` time and the time to invoke a small command grow by no more than 2%. No new work happens at import time.                                     |
| Security    | The config file is parsed as data only. Paths are not expanded outside the working directory unless the user passes them. Errors do not echo secret values. |
| Design      | One clear extension point for value sources. No circular imports. No change to existing public signatures.                                                  |
| Operability | Failures are explicit and testable. Nothing is logged by the library itself.                                                                                |
| Docs and UX | Documented with a runnable example. Help text and error messages are consistent with the existing style.                                                    |
