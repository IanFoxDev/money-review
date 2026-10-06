# money-review

Code review for changes that move money. A Claude Code plugin that reads a diff and
looks only for the bugs that cost money: an HTTP call to the payment provider inside a
database transaction, check-then-act without a lock, a webhook handler that credits
twice when the provider retries, a float where cents should be.

Every finding comes with a failure scenario: what happens, in which order, and what it
costs. A finding without one is dropped.

It runs on your Claude subscription through the Claude Code CLI. No API key, no extra
bill per merge request, and a change that does not touch money never reaches the model.

[![ci](https://github.com/IanFoxDev/money-review/actions/workflows/ci.yml/badge.svg)](https://github.com/IanFoxDev/money-review/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Status: 0.x. Triage knows PHP (Laravel and plain PHP) and Go, SQL and MongoDB
drivers, Kafka and RabbitMQ clients; the checklists are not tied to a language, but
their examples are still SQL-flavored. Works on GitLab merge requests and GitHub pull
requests.

## What a finding looks like

From a real run on a merge request that adds wallet withdrawals (one new 27-line file):

> ### HIGH RACE-1: Balance check and debit with no lock or transaction
>
> `app/Services/WithdrawalService.php:18`
>
> **What happens:** The wallet holds 10000 balance_cents (100.00). The user
> double-clicks to withdraw 80.00. Both requests load the wallet at line 15 with no
> lock and read 10000. Both pass the check at line 18. Both set balance_cents to 2000
> and save. Both call gateway->payout(8000) at line 25. 160.00 is paid out against
> 100.00, and the wallet shows 2000, so the 6000 overdraft is not recorded anywhere.
>
> **Fix:** Wrap the read, check and debit in DB::transaction and load the wallet with
> lockForUpdate(), or run a conditional UPDATE ... WHERE balance_cents >= ? and treat 0
> affected rows as insufficient funds. Keep the gateway call outside the transaction.

The same run reported a float amount cast to cents (19.99 becomes 19.98), the payout
sent after the debit with no record of the withdrawal, and a payout without an
idempotency key. After the author pushed a fix that moved the payout inside the
transaction, the next run looked only at the new commit and reported exactly that.

## Install

You need Claude Code 2.1 or newer, logged in with a Claude subscription, plus `git` and
`jq`. For GitLab merge requests, also [`glab`](https://gitlab.com/gitlab-org/cli);
for GitHub pull requests, [`gh`](https://cli.github.com). Both logged in. They take the
host from the git remote, so GitHub Enterprise Server and self-managed GitLab need only
a login to that host (`gh auth login --hostname git.example.com`, `glab auth login
--hostname git.example.com`); this path has not been tested on them yet.

In Claude Code:

```
/plugin marketplace add IanFoxDev/money-review
/plugin install money-review@money-review
```

The plugin brings the shell command with it. Put it on your `PATH`:

```sh
ln -s ~/.claude/plugins/marketplaces/money-review/plugins/money-review/bin/money-review ~/.local/bin/money-review
```

Without Claude Code plugins, clone the repository instead and link
`plugins/money-review/bin/money-review` from there.

## Use

Inside a Claude Code session, in the repository with your change:

```
/money-review:money-review                 # this branch against master or main
/money-review:money-review --base develop
```

From a shell:

```sh
money-review                               # Markdown report
money-review --format json                 # the report as JSON
money-review --fail-on high                # exit 1 if there is a high finding
```

On a GitLab merge request or a GitHub pull request:

```sh
money-review --mr 42                       # review GitLab !42, print the report
money-review --mr 42 --post                # and comment on the merge request
money-review --pr 42 --post                # the same for GitHub #42
money-review --mr 42 --full                # review the whole MR again
```

`--mr` and `--pr` check out the head in a temporary git worktree, so your working copy
is not touched. `--post` leaves one comment per finding on the line it is about and
keeps one summary comment up to date. The summary records the reviewed commit: the
next run looks only at commits pushed after it, and does not start Claude at all if
there are none. A finding that is already there (same rule, same file) is not posted
twice. How a team can share this without a CI token: [docs/team.md](docs/team.md).

Exit codes: 0 done, 1 findings at the `--fail-on` level, 2 usage error, 3 refused to
run because `ANTHROPIC_API_KEY` is set (it would bill the API instead of your
subscription; pass `--allow-api-key` if that is what you want), 4 the review did not
produce a report, also after one more try (`--retries N` to change that).

## What it checks

Four checklists, 31 rules. Each rule has what to look for, a failure scenario, a bad
and a good example, and a "do not report" section that keeps false alarms down. Every
checklist covers SQL databases and MongoDB; transactions and idempotency also cover
Kafka, Redpanda and RabbitMQ consumers and producers.

| Checklist | Covers |
|---|---|
| [Transaction boundaries (TX)](plugins/money-review/skills/money-review/references/transactions.md) | provider calls inside a transaction, side effects after commit with no record (including a database write followed by a Kafka produce), debit and credit in separate transactions, swallowed exceptions, nested transactions, one transaction around a batch, MongoDB calls that miss the session, side effects in a retried transaction callback |
| [Races (RACE)](plugins/money-review/skills/money-review/references/races.md) | check-then-act (including `findOne` then `updateOne`), lost updates, state transitions without a guard, lock order, uniqueness enforced only in code, limits checked under READ COMMITTED, Redis locks that do not hold, money decisions read from a secondary or a cache |
| [Idempotency (IDEM)](plugins/money-review/skills/money-review/references/idempotency.md) | callbacks and consumers without a dedup key, dedup outside the transaction, outgoing calls without a stable idempotency key, timeouts treated as failures, batches that are not safe to re-run, retries around non-idempotent code, offset commits and acks before the work, events of one account out of order, a duplicate key caught inside a MongoDB transaction |
| [Money arithmetic (MONEY)](plugins/money-review/skills/money-review/references/arithmetic.md) | floats, amounts without a currency, rounding without a rule, splits that do not add up, signs of refunds and fees, balances changed without a ledger entry |

Style, naming and general code quality are out of scope on purpose. Use it next to
your usual review, not instead of it.

## How it keeps usage low

A review is a pipeline, and each stage can stop it:

1. Triage without a model. A script decides from the diff and your config whether any
   changed file touches money and which checklists apply. A merge request about
   avatars ends here.
2. One reviewer pass (Sonnet) with only the matched checklists.
3. A verifier (Opus) tries to refute each candidate against the code around it: an
   earlier lock, a unique index in a migration, an outer transaction. It runs only if
   there are candidates.
4. The coordinator never reads code. It passes file paths between stages.

On the merge request above a full review took 88 seconds and 5 turns. The
same run on the API would cost about 0.38 USD; on a subscription it uses your limits
instead. More in [docs/how-it-works.md](docs/how-it-works.md).

## Configure

Put `.money-review.json` in the repository root. It is merged over the
[defaults](plugins/money-review/defaults/config.json):

```json
{
  "money_paths": ["app/Billing/*", "app/Wallet/*"],
  "context": "Amounts are integer cents. Balances change only through App\\Ledger. Provider calls go through App\\Psp\\Gateway."
}
```

`money_paths` always count as money code. `context` is passed to the reviewer: tell it
where your transaction wrapper, ledger and dedup table are, and it stops guessing.
A finding the team has accepted can be silenced with a reason, in the code or in the
config:

```php
// money-review: ignore RACE-1 the caller holds lockForUpdate on the wallet
```

Every field is described in [docs/config.md](docs/config.md).

## How good is it

The repository has an eval with two apps and 49 merge requests on top of them, each
with one planted bug or none (clean cases, some of them touching money code
correctly). See [docs/eval.md](docs/eval.md), and [docs/eval-results/](docs/eval-results/)
for full reports. The table is the run of 2026-10-05 over the 43 cases of that day, each
three times (Claude Code 2.1.289); the cases added later are covered below it.

| | Laravel app on SQL | PHP and Go on MongoDB, Kafka, Redis |
|---|---|---|
| Cases | 25 (20 bugs, 5 clean) | 18 (14 bugs, 4 clean) |
| Precision | 100% (56 of 56) | 100% (42 of 42) |
| Recall | 93% (56 of 60) | 100% (42 of 42) |
| False alarms on clean cases | 0 in 15 runs | 0 in 12 runs |
| Time per review | 48 s | 52 s |
| API-equivalent cost per review | 0.28 USD | 0.31 USD |

The SQL numbers were measured with the rules of 0.1 and 0.2; the MongoDB numbers with the rules
and triage of 0.3. The checklists and the cases were written by the same person, so
these numbers show that the rules work as intended, not how the tool does on someone
else's code.

On the SQL app, recall by checklist:

| Checklist | Recall |
|---|---|
| RACE | 100% |
| TX | 100% |
| MONEY | 100% |
| IDEM | 78% |

On the SQL app, all four misses were in two cases where the change removed one of two
safety layers and the other one still held. Those two cases were rebuilt so that the
removed layer is the only one, and cases were added for MONEY-3, MONEY-5 and TX-5
with a clean pair for each. On these 8 cases (2026-10-06, 24 runs): 14 of 15 bugs
found, 1 false alarm (low), 0 false alarms in 9 clean runs. The one miss is the right
finding reported at line 1 of the file. Details in
[docs/eval-results/2026-10-06-new-cases.md](docs/eval-results/2026-10-06-new-cases.md).

Bugs that only the current callers hide are reported as `low`, with the code that
protects them today: a ledger transfer split over two transactions is safe while
every caller opens an outer transaction, and breaks with the first one that does not.

## Limits

- The model is not deterministic. Two runs on the same change can report 4 and 5
  findings. Treat it as a reviewer with good days and bad days, not as a linter.
- A large change is reviewed in groups of files (800 changed lines each by default,
  up to 6 groups). Past that limit the report lists the files it did not review.
- Triage works on words and paths. A money change that uses none of the configured
  words is skipped; add its paths to `money_paths`.
- It reads the repository it runs in. A guard that lives in another service is
  invisible to it; the verifier lowers the severity when it cannot tell.
- Running it in CI needs a token tied to one person's subscription
  (`claude setup-token`). Check that your plan allows that before you set it up for a
  team. Until then, the reviewer runs it by hand ([docs/team.md](docs/team.md)).

## License

MIT
