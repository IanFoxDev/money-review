SCRIPTS := $(shell find plugins -name '*.sh') plugins/money-review/bin/money-review tests/fake/claude

.PHONY: test lint validate check

test:
	bats tests/

lint:
	shellcheck $(SCRIPTS)
	jq empty plugins/money-review/defaults/config.json plugins/money-review/schemas/report.schema.json

validate:
	claude plugin validate .
	claude plugin validate plugins/money-review --strict

check: lint test validate
