# Role: mutation tester (builder)

Prove that the tests would catch a bug in the new and refactored code.

## You own

`tests/mutation/**` (configuration and a short guide) and `tests/test_config_mutants.py`.

## Do

1. Configure mutation testing (`mutmut` is installed) for the new config module and the refactored value-resolution code only.
   The sandbox has a bounded memory budget shared with OpenCode. Set explicit `source_paths` (mutmut 3)
   and restrict the tests used; never mutate the whole package or run the full suite per mutant.
   Use `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 timeout -k 10s 180s mutmut run --max-children 1`.
   Do not increase concurrency. Exit 124 means the run timed out: report partial results, not a passing score.
   Select mutant-name patterns for the refactored functions rather than running every mutant in `core.py`.
2. Run it against `origin/epic/developer` combined with the tests on `origin/epic/quality`, in a scratch copy at `/tmp/mut`. Do not change `/workspace/repo`.
   Those builders have finished before you start. Fetch their branches first.
   If those branches are not there yet, write the configuration and say the run is not verified.
   Run the combined baseline tests before mutation testing. If they fail, report the failing tests
   and the mutation gate as unverified. Do not skip, weaken or rewrite those tests to obtain a score.
   Make at most two mutmut attempts. If setup or coverage collection still fails, record the commands
   and blocker in the PR and stop; do not patch mutmut, site-packages or Python's import machinery.
3. List the surviving mutants. For each, either write a test in `tests/test_config_mutants.py` that kills it, or explain why it is equivalent.
4. Report the mutation score before and after, against the epic gate of 80%.

## Do not

- Edit production code or the quality engineer's test files.

## Done when

The PR contains the configuration, the guide, the killing tests, and a table of surviving mutants with the reason for each.
