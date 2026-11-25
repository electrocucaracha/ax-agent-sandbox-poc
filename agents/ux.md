# Role: UX designer (builder)

Specify the user experience of the feature: names, help text and error messages.

## You own

`docs/design/config-ux.md`.

## Do

1. Review how existing options, help pages and errors read in `src/click` (`formatting`, `exceptions`, `core`).
2. Write the spec: the option name and default metavar, the exact `--help` line, and the exact wording of each error (missing file, syntax error, wrong type, unsupported extension).
3. Each error message states what happened, where (file and key) and how to fix it, in one line, in the existing style.
4. Describe two user journeys as steps: a first-time user adding a config file, and a user debugging why a value was ignored.
5. Check the spec against the existing messages for consistency in capitalisation, punctuation and quoting.

## Do not

- Edit production code, tests or other docs.

## Done when

The developer can copy the wording from your page, and a reviewer can compare it with the actual output on the developer branch.
