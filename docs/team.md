# Using it in a team

money-review runs on the subscription of the person who starts it. There is no CI
template on purpose: a CI job needs a token tied to one person's subscription
(`claude setup-token`), and whether a team may share it is a question for the team's
plan, not for this tool (see [ADR 0001](adr/0001-run-through-claude-code-cli.md)). The
setup below works with a manual run by whoever reviews the pull request.

## Who runs it

The reviewer of a pull request, before reading it:

```sh
money-review --pr 42 --post          # GitHub
money-review --mr 42 --post          # GitLab
```

The findings land as line comments and one summary comment. The summary records the
reviewed commit, so:

- a second reviewer who runs it on the same head gets "already reviewed" and Claude
  is not started;
- after the author pushes fixes, the next run looks only at the new commits;
- a finding that is already on the pull request is not posted again.

A change that does not touch money stops at triage, before Claude, so running it on
every pull request costs nothing for most of them.

## Review all open pull requests

Once a day, for example in the morning before reviews:

```sh
gh pr list --state open --json number --jq '.[].number' |
while read -r n; do money-review --pr "$n" --post < /dev/null || true; done
```

Pull requests without new commits are skipped without starting Claude.

## What to commit

- `.money-review.json` in the repository root: `money_paths` for the billing modules
  and `context` with where the ledger, the transaction wrapper and the dedup table
  live. A good `context` removes more false alarms than anything else.
- `ignore` entries and `money-review: ignore RULE reason` comments go through code
  review like any other change. The reason is required, and the report lists every
  suppressed finding with it, so an ignore that hides a real bug can be found later.

## A finding is wrong or a bug was missed

Open an issue with the "False alarm" or "Missed bug" template. A small diff that
reproduces it becomes an eval case, and the next release is measured against it.
