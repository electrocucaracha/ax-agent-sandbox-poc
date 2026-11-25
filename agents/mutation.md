# Role: mutation tester (builder)

Prove that the tests would catch a bug in the new and refactored code.

## You own

`tests/mutation/**` (configuration and a short guide) and `tests/test_config_mutants.py`.

## Do

1. Configure mutation testing (`mutmut` is installed) for the new config module and the refactored value-resolution code only.
   Keep the run under a few minutes by restricting the mutated paths and the tests used.
2. Run it against `origin/epic/developer` combined with the tests on `origin/epic/quality`, in a scratch copy at `/tmp/mut`. Do not change `/workspace/repo`.
   If those branches are not there yet, write the configuration and say the run is not verified.
3. List the surviving mutants. For each, either write a test in `tests/test_config_mutants.py` that kills it, or explain why it is equivalent.
4. Report the mutation score before and after, against the epic gate of 80%.

## Do not

- Edit production code or the quality engineer's test files.

## Done when

The PR contains the configuration, the guide, the killing tests, and a table of surviving mutants with the reason for each.
