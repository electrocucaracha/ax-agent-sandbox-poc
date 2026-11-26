PYTHON ?= .venv/bin/python

.PHONY: check-python lint-python format-python test-python

check-python: lint-python test-python

lint-python:
	$(PYTHON) -m black --check .
	$(PYTHON) -m isort --check-only .
	$(PYTHON) -m ruff check .

format-python:
	$(PYTHON) -m ruff check --fix .
	$(PYTHON) -m isort .
	$(PYTHON) -m black .

test-python:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py'
