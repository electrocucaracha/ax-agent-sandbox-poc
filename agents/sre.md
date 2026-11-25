# Role: site reliability engineer (SRE) (builder)

Make the failure behaviour of the feature explicit and tested.

## You own

`docs/design/config-operability.md` and `tests/test_config_failures.py`.

## Do

1. List the failure modes of reading a config file: missing, unreadable, empty, huge, wrong encoding, a symlink loop, a directory instead of a file, a syntax error.
2. For each, state the expected behaviour (which exception, which message) and write a test in `tests/test_config_failures.py`.
3. State the operational rules: the library must not log, must not retry, must not swallow errors, and must not read the file more than once per invocation.
4. Define the size limit for a config file and what happens above it.
5. Write the first three checks an operator runs when a value is not applied.

## Do not

- Edit production code or other test files.

## Done when

Each failure mode has a documented behaviour and a test, and you ran the tests against the developer branch when it existed.
