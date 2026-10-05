SCRIPTS := $(shell find plugins -name '*.sh') plugins/money-review/bin/money-review tests/fake/claude tests/fake/glab tests/fake/gh $(wildcard eval/*.sh)

.PHONY: test lint validate eval-check check

test:
	bats tests/

lint:
	shellcheck $(SCRIPTS)
	jq empty plugins/money-review/defaults/config.json plugins/money-review/schemas/report.schema.json

validate:
	claude plugin validate .
	claude plugin validate plugins/money-review --strict

eval-check:
	find eval -name '*.php' -print0 | xargs -0 -n 1 php -l > /dev/null
	eval/expected.sh $(notdir $(wildcard eval/cases/*)) > /dev/null

check: lint test validate eval-check
