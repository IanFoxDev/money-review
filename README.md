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

From a run on one of the eval cases, a new withdrawal service (one changed file):

> ### 1. HIGH RACE-1: Balance check and absolute balance write are not protected by a lock, so concurrent withdrawals both pass and updates are lost
>
> `app/Services/WithdrawalService.php:18`
>
> ```php
>   16 |     {
>   17 |         $account = Account::forUser($userId, $currency);
> > 18 |         if ($account->balance_cents < $amountCents) {
>   19 |             throw new \DomainException('Insufficient funds');
>   20 |         }
> ```
>
> **What happens:** A user has 100.00 EUR (balance_cents=10000). Two withdrawals of
> 80.00 arrive together with different requestIds. Both load the Account at line 17 with
> no lock and outside any transaction, and both pass the check at line 18. [...] Each
> then runs `$account->balance_cents -= 8000` and `save()` (lines 27-28). That writes
> the absolute value 2000 from its own stale copy. The user ends at 20.00 while
> withdrawals_pending is incremented twice (+16000, line 29). 160.00 is now pending
> against a 100.00 balance, and 60.00 has been created from nothing.
>
> **How to fix:** Call Ledger::transfer(...). It locks both rows in id order
> (Ledger.php:38), re-checks the balance under the lock (Ledger.php:42) and updates
> balances with relative SQL (Ledger.php:50-51). If the service keeps its own flow, read
> the account with lockForUpdate() inside DB::transaction, do the check after the lock,
> and use a relative update instead of save().

The code is cut from the file after the review, not written by the model, so it is the
code as it is. The same run found two more problems: balances changed with no ledger
entries (MONEY-6) and no check that the amount is positive (MONEY-5). When there is more
than one finding, the report starts with a table of them: severity, rule, file and line,
and the problem in one line.

## Install

You need Claude Code 2.1 or newer, logged in with a Claude subscription (Pro, Max, or a
seat on a Team or Enterprise plan), plus `git` and `jq`. For GitLab merge requests, also
[`glab`](https://gitlab.com/gitlab-org/cli); for GitHub pull requests,
[`gh`](https://cli.github.com). Both logged in. They take the host from the git remote,
so GitHub Enterprise Server and self-managed GitLab need only a login to that host (`gh
auth login --hostname git.example.com`, `glab auth login --hostname git.example.com`);
this path has not been tested on them yet.

In Claude Code:

```
/plugin marketplace add IanFoxDev/money-review
/plugin install money-review@money-review
```

The plugin brings the shell command with it. To put it on your `PATH`, run once in
Claude Code:

```
/money-review:setup
```

It writes a small wrapper to `~/.local/bin/money-review` that runs the installed release
(from the Claude profile in `CLAUDE_CONFIG_DIR`, or the default one), so it keeps
working after updates. The same by hand:

```sh
cat > ~/.local/bin/money-review <<'EOF'
#!/bin/sh
# Runs the installed release of money-review, from this or the default Claude profile.
for dir in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$HOME/.claude"; do
    p="$(jq -r '.plugins["money-review@money-review"][0].installPath // empty' "$dir/plugins/installed_plugins.json" 2>/dev/null)"
    [ -n "$p" ] && exec "$p/bin/money-review" "$@"
done
echo "money-review: the plugin is not installed (/plugin install money-review@money-review)" >&2
exit 2
EOF
chmod +x ~/.local/bin/money-review
```

The marketplace installs the latest release, not the tip of `master`. Without Claude
Code plugins, or to try unreleased changes, clone the repository and link
`plugins/money-review/bin/money-review` from there.

## Updating

A new release does not reach you by itself. Claude Code keeps auto-update off for
marketplaces outside Anthropic's own, so the version you installed stays until you
update. From a terminal:

```sh
claude plugin marketplace update money-review
claude plugin update money-review@money-review
```

Or in Claude Code: `/plugin marketplace update money-review`, then update the plugin
from the `/plugin` menu. Restart Claude Code after either. The shell command from
`/money-review:setup` follows the installed release, so it needs nothing.

To get releases without doing this, turn on auto-update for the `money-review`
marketplace in the `/plugin` menu; Claude Code then updates it at startup. What changed
in each release is in [CHANGELOG.md](CHANGELOG.md).

## Use

Inside a Claude Code session, in the repository with your change:

```
/money-review:money-review                 # this branch against master or main
/money-review:money-review --base develop
/money-review:money-review --commits HEAD~3..   # only the last three commits
```

From a shell:

```sh
money-review                               # Markdown report
money-review --format json                 # the report as JSON
money-review --quiet                       # suppress the usage summary on stderr
money-review --fail-on high                # exit 1 if there is a high finding
```

`--quiet` suppresses only the usage summary; reports, errors and exit codes stay the
same.

Before there is a merge request, or for a part of one, review commits instead of the
working tree:

```sh
money-review --commits abc1234             # one commit
money-review --commits HEAD~3..            # the last three commits
money-review --commits master..feature     # what feature adds since it left master
```

`--commits` leaves uncommitted edits out. From a shell it reads the code as it is at the
last commit of the range, in a temporary worktree; inside Claude Code the agents read
your working tree, so review a range that ends at `HEAD` there.

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
produce a report, also after one more try (`--retries N` to change that), or ran past
`--timeout` (20 minutes by default; a typical review takes one or two).

## What it checks

Four checklists, 34 rules. Each rule has what to look for, a failure scenario, a bad
and a good example, and a "do not report" section that keeps false alarms down. Every
checklist covers SQL databases and MongoDB; transactions and idempotency also cover
Kafka, Redpanda and RabbitMQ consumers and producers.

| Checklist | Covers |
|---|---|
| [Transaction boundaries (TX)](plugins/money-review/skills/money-review/references/transactions.md) | provider calls inside a transaction, side effects after commit with no record (including a database write followed by a Kafka produce), debit and credit in separate transactions, swallowed exceptions, nested transactions, one transaction around a batch, MongoDB calls that miss the session, side effects in a retried transaction callback, events that stop carrying what money consumers read |
| [Races (RACE)](plugins/money-review/skills/money-review/references/races.md) | check-then-act (including `findOne` then `updateOne`), lost updates, state transitions without a guard, lock order, uniqueness enforced only in code, limits checked under READ COMMITTED, Redis locks that do not hold, money decisions read from a secondary or a cache |
| [Idempotency (IDEM)](plugins/money-review/skills/money-review/references/idempotency.md) | callbacks and consumers without a dedup key, dedup outside the transaction, outgoing calls without a stable idempotency key, timeouts treated as failures, batches that are not safe to re-run, retries around non-idempotent code, offset commits and acks before the work, events of one account out of order, a duplicate key caught inside a MongoDB transaction, provider declines and business errors with no path |
| [Money arithmetic (MONEY)](plugins/money-review/skills/money-review/references/arithmetic.md) | floats, amounts without a currency, rounding without a rule, splits that do not add up, signs of refunds and fees, negative input amounts, reversals booked in the wrong direction, balances changed without a ledger entry, an amount taken from the wrong source (the full amount after a partial refund) |

A money bug that no rule covers is still reported, as `MONEY-0`, when the reviewer can
write a concrete failure scenario for it. Style, naming and general code quality are out
of scope on purpose. Use it next to
your usual review, not instead of it.

## How it keeps usage low

A review is a pipeline, and each stage can stop it:

1. Triage without a model. A script decides from the diff and your config whether any
   changed file touches money and which checklists apply. A merge request about
   avatars ends here.
2. One reviewer pass (Sonnet) with only the matched checklists. When it finds
   something, a second look at the same change, told what it already found, for other
   money bugs next to it (`review.second_pass`, on by default).
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

Files that may hold secrets (`.env`, keys, certificates) are cut from the diff and
denied to the review agents, in the shell command and inside Claude Code alike; the
list is `secrets` in the config.

Every field is described in [docs/config.md](docs/config.md).

## How good is it

The repository has an eval with two apps and 50 merge requests on top of them. Most
have one planted bug, eleven have a second, quieter one next to it, and twelve have none
(clean cases, some of them touching money code correctly). See
[docs/eval.md](docs/eval.md), and [docs/eval-results/](docs/eval-results/) for full
reports. The table is every case three times, run on 2026-10-08 with Claude Code
2.1.294, `claude-sonnet-5-5` as the reviewer and `claude-opus-5-5` as the verifier
([2026-10-08-second-look.md](docs/eval-results/2026-10-08-second-look.md)).

| | Laravel app on SQL | PHP and Go on MongoDB, Kafka, Redis |
|---|---|---|
| Cases | 32 (24 with bugs, 32 bugs; 8 clean) | 18 (14 with bugs, 21 bugs; 4 clean) |
| Precision | 100% (92 of 92) | 100% (53 of 53) |
| Recall | 96% (92 of 96) | 84% (53 of 63) |
| False alarms on clean cases | 0 in 24 runs | 0 in 12 runs |
| Time per review (median) | 80 s | 89 s |
| API-equivalent cost per review | 0.29 USD | 0.31 USD |

The same cases through a plain "review this change" prompt with no plugin
([2026-10-07-plain-prompt.md](docs/eval-results/2026-10-07-plain-prompt.md) for the
method):

| | money-review | plain prompt, opus | plain prompt, sonnet |
|---|---|---|---|
| Recall | 91% | 94% | 84% |
| Precision | 100% | 85% | 86% |
| Clean runs with a false alarm | 0 of 36 | 8 of 36 | 16 of 36 |
| API-equivalent cost per review | 0.30 USD | 0.15 USD | 0.07 USD |

That comparison is where the second bugs come from: a plain prompt on opus found money
bugs next to the planted ones that money-review did not report, because its reviewer could
report only what the checklists named. With `MONEY-0` and three new rules, recall went from
80% to 87% on the same cases, and a second look at changes with a finding took it to 91%,
with no false alarm added. What it still misses is mostly a second money bug on the same
lines as the first: the sign of an input amount, a balance changed without a ledger entry.

The checklists and the cases were written by the same person, so these numbers show
that the rules work as intended, not how the tool does on someone else's code. The eval
runs again on every minor release and every model change, and is compared with the last
accepted run (`eval/baseline/`).

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
