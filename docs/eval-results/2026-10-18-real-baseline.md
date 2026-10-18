# Real-bug eval, baseline

Measured 2026-10-17 with money-review 0.8.3 (d2f8054), Claude Code 2.1.302, models
claude-opus-5-5 and claude-sonnet-5-5. 45 cases from `eval/real/` (36 bug cases, 9
controls), three runs each, 135 runs. Scored after the review of every false alarm
described below; `eval/real/baseline/summary.json` holds the scored run.

| Metric | Value |
|---|---|
| Precision | 93% (70 true, 5 false) |
| Recall | 61% |
| Recall, any rule | 75% |
| Clean runs with a false alarm | 0 of 27 |
| Bug cases skipped by triage | 12 runs (4 cases) |
| Real issues outside the case (acceptable) | 19 |
| Errors | 0 |
| Time per reviewed run | 102 s |
| API-equivalent cost per reviewed run | 0.38 USD (45 USD in total) |

| Split | Bugs | Found | Recall |
|---|---|---|---|
| introducer | 72 | 47 | 65% |
| reverse | 42 | 23 | 55% |
| fixed before 2026-06-01 | 30 | 26 | 87% |
| fixed from 2026-06-01 | 84 | 44 | 52% |

The numbers count each bug once per run. Bugs fixed before June 2026 may be known to the
models; the 52% on later fixes is the number to watch.

Bug cases found in every run: 19 of 36, in some runs: 4, never: 13.

## By family

| Family | Bugs | Found | Recall |
|---|---|---|---|
| MONEY | 27 | 26 | 96% |
| IDEM | 6 | 5 | 83% |
| TX | 6 | 5 | 83% |
| NEW-STATE | 6 | 6 | 100% |
| NEW-TIME | 6 | 6 | 100% |
| RACE | 12 | 6 | 50% |
| NEW-PSP | 18 | 9 | 50% |
| NEW-SUB | 21 | 7 | 33% |
| NEW-AGG | 6 | 0 | 0% |
| NEW-DATA | 3 | 0 | 0% |
| NEW-DEDUP | 3 | 0 | 0% |

`NEW-*` families have no rules in 0.8.3. Arithmetic, idempotency and transactions are
covered; provider events, subscriptions, aggregates and data completeness are where the
misses are.

## The false alarms, reviewed

The raw score was 66% precision: 32 findings matched no expected bug. Each was checked
against the code at `head` and against the later upstream history. They are 19 distinct
issues:

| Verdict | Issues | Findings |
|---|---|---|
| Real, brought in by the change | 12 | 25 |
| Real, present before the change | 3 | 5 |
| False | 4 | 4 |

Upstream later fixed several of the real ones: the update-prices action in invoiceninja
copied the purchase cost into the selling price (1863da082), a retried reserve in midaz
counted usage twice (c0bde7390), the fee debt collect in midaz had no idempotency key
(e525d6e, the case's own bug, reported at a place the case did not list), the blnk
inflight dry run ignored the amount (0cc9e68, the case's own bug, reported with an
absolute path).

What changed after the review:

- Two second bugs that upstream fixed are now bugs of their cases
  (`midaz-counter-expiry-from-reservation-ttl`, `invoiceninja-increase-price-rounded-rate`).
- Other real issues are `acceptable` entries: neither a hit nor a false alarm.
- `also` entries take an `anchor_end`, and the fee debt case lists the places where the
  missing key shows.
- `control-paymenter-paid-after-commit` keeps no expected bug, but TX-2 and TX-3 on the
  observer are acceptable: the fix moves crediting and renewal after the commit, so a
  failure there now leaves a paid invoice with no credit and nothing retries it.
- One report held absolute paths of the working copy. `fix-lines.sh` now makes paths
  under the repository root relative, and the score strips the working copy prefix from
  older runs.

The four false findings: a fee estimate shown on a pending invoice read as a charge; an
amount that a helper had already rewritten read as stale; a half-applied leg that needs
an inconsistent ledger to happen; a credit for money that really arrived on a paid
invoice read as a double credit. One more stays counted as false: an `authorized`
payment accepted as paid where the gateway captures automatically.

## What is next

- The new checklists (provider events, reversals, subscriptions, periods, data
  completeness) measured on the same set.
- Triage: 4 bug cases never reach the review: a Redis lock helper (blnk), a webhook
  controller (cashier-stripe), a credit balance snapshot (openmeter) and an order payment
  processor (Sylius). Their changed lines carry no money words.
