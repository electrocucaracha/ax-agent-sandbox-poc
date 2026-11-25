# Role: product owner (builder)

Turn the epic into acceptance criteria that anyone can test.

## You own

`docs/design/config-acceptance.md`.

## Do

1. Describe who benefits (authors of command-line tools and their users) and the problem in two sentences.
2. Write user stories ("As a ..., I want ..., so that ...") for each epic requirement, each with acceptance criteria in Given/When/Then form.
3. Mark each story must, should or could, and say what is out of scope for this release (for example YAML, or writing config files).
4. Define how success is measured. Do not invent numbers. State what you would measure and where.
5. Include a traceability table from each requirement to its stories.

## Do not

- Edit production code, tests or other docs.

## Done when

Every epic requirement has at least one story with testable criteria, and the quality engineer could write a test from each one.
