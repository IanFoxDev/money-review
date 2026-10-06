# Contributing

## Running locally

You need Bash, `jq`, `git`, [bats](https://github.com/bats-core/bats-core) and
`shellcheck`. PHP is needed only to lint the eval app, Claude Code only to validate
the plugin manifest.

```bash
make lint          # shellcheck, JSON files parse
make test          # bats tests, no model involved
make validate      # claude plugin validate
make eval-check    # eval app and cases parse, anchors resolve
make check         # all of the above
```

The tests never start Claude or call GitLab: `tests/fake/claude` and `tests/fake/glab`
stand in for them. Scripts must work with Bash 3.2, the macOS default, so no
associative arrays and no `mapfile`. CI runs the tests under `/bin/bash` on macOS.

To try the plugin on a real change, start Claude Code with the local copy:

```bash
claude --plugin-dir ./plugins/money-review
```

## Where things are

| Path | What |
|---|---|
| `plugins/money-review/skills/money-review/SKILL.md` | the coordinator |
| `plugins/money-review/skills/money-review/references/` | the checklists |
| `plugins/money-review/agents/` | reviewer and verifier |
| `plugins/money-review/scripts/` | prepare, triage, render, GitLab |
| `plugins/money-review/bin/money-review` | the shell command |
| `plugins/money-review/defaults/config.json` | default triage patterns |
| `eval/` | the eval app, cases and scoring |
| `docs/adr/` | decisions and why |

## Changing a checklist

A new rule or a reworded one changes what the model reports, so it needs evidence:

1. Add or change the rule with a failure scenario, a bad and a good example, and a
   "do not report" section.
2. Add an eval case that the rule is meant to catch, and if the rule could fire on
   correct code, a clean case for that too (see [docs/eval.md](docs/eval.md)).
3. Run the cases of that checklist and every clean case three times, compare with the
   baseline (`eval/compare.sh`), and put the comparison in the pull request. The
   schedule for releases and model changes is in [docs/eval.md](docs/eval.md#when-to-run-it).

## Reporting a false alarm or a missed bug

These are the most useful issues. Use the templates; a small diff that reproduces it
is worth more than a description, and it can become an eval case.

## Before you write code

Open an issue first for anything bigger than a fix. Running only through the Claude
Code CLI, read-only agents and no model in CI are deliberate (see `docs/adr/`).
