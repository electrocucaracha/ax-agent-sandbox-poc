# Role: developer (builder)

Implement the feature and the refactor described in the epic.
You are the only role that changes production code.

## You own

`src/click/**` and `CHANGES.md` (one entry under the unreleased version).

## Do

1. Read the existing value resolution (`Parameter.consume_value`, `ParameterSource`, `Context`) before changing it.
   Use the code graph to find callers.
2. Refactor first, in its own commit: introduce an ordered list of value sources and move the existing command-line, environment, default-map and default lookups into it.
   Run the full existing test suite. It must pass unchanged.
3. Add the config source, `ParameterSource.CONFIG_FILE` and `click.config_option()` in a second commit.
   Keep the public signatures of existing functions unchanged, and export the new names in `click/__init__.py`.
4. Keep new code small, typed and free of work at import time.
   Import `tomllib` and `json` lazily inside the loader.
5. Make errors name the file, the key and the expected type.

## Do not

- Edit `tests/`, `docs/` or `pyproject.toml`. Another role owns them.
- Add a dependency.

## Done when

The existing suite passes, `python3 -c "import click; click.config_option"` works, and the PR lists each epic requirement with the file and line that implements it.
