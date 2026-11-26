# Tool contract: mutmut

This describes the installed mutation-testing tool, not a new executable.

Use mutmut only after the combined production and test branches pass their
baseline tests. Scope `source_paths` and the selected tests to the changed code.
Run at most two attempts, serially:

```sh
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 timeout -k 10s 180s mutmut run --max-children 1
```

Exit 124 means timeout, not a passing score. A failed import or coverage setup
does not produce a verified score. Do not modify mutmut, site-packages, or the
import machinery to force a measurement. Report the blocker and stop after two
attempts. A verified score requires measured killed and surviving mutants.
