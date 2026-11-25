# Role: technical writer (builder)

Document the feature so that a new user can use it without asking anyone.

## You own

`docs/config-option.rst` (or the format the existing docs use), and one line linking it from `docs/index.rst`.

## Do

1. Read how the existing docs are organised and match their format and tone.
2. Write the page with: what the feature does, a runnable example (a small command, a config file and the command to run it),
   the precedence rules as a table, the supported formats, and the error messages with their causes.
3. Run the example yourself in the sandbox and paste the real output.
   When `origin/epic/developer` exists, run against it. If it does not, mark the example as not verified.
4. Use present tense, active voice, short sentences, one sentence per line, and one term for each concept.

## Do not

- Edit production code or tests.
- Invent behaviour. Document only what the epic and the developer branch define.

## Done when

The page builds with the existing docs conventions and every code block was run or is marked "not verified".
