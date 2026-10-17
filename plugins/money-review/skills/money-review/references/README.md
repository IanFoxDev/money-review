# Checklists

One file per category. The reviewer loads only the files for categories that the
triage step matched, so each file stands alone.

Every rule has:

- an id (`TX-1`, `RACE-2`, ...) that findings refer to;
- what to look for in the diff;
- a failure scenario: the order of events that loses or duplicates money;
- a bad and a good example (PHP; the rule itself is language-neutral);
- when not to report it, to keep false positives down.

| File | Prefix | Covers |
|---|---|---|
| `transactions.md` | TX | what runs inside and outside a database transaction; MongoDB sessions, writes plus broker publishes |
| `races.md` | RACE | concurrent requests, workers and callbacks on the same row or document; Redis locks, stale reads |
| `idempotency.md` | IDEM | retries, duplicate deliveries, re-runs of jobs; broker consumers, offsets and acks, ordering |
| `arithmetic.md` | MONEY | amounts, currencies, rounding, splitting, units and scales, defaults; amounts in BSON and decoded JSON |
| `providers.md` | PSP | the provider as a second ledger and reading its messages: accepted requests it ignores, charges after our expiry, notification types, fixes for one provider only, loose parsing, pending results, amount checks, signatures, late events |
| `reversals.md` | REV | refunds, chargebacks, voids and rollbacks: the right original, mirrored legs, totals, side effects |
| `lifecycle.md` | SUB | subscriptions: plan changes, duplicates, renewal selection, access periods, cancellation, trials, proration |
| `time.md` | TIME | periods and dates: calendar arithmetic, time zones, period edges, "now", off-by-one at limits |

Each file starts with the rules in SQL terms, then a section that maps them to
MongoDB, Redis and message brokers and adds the rules that only exist there. Rules
added later (TX-9, IDEM-10, IDEM-11, IDEM-12, MONEY-7, MONEY-8, MONEY-9) come at the end of their
section.

`MONEY-0` has no entry: it is a money bug that no rule covers, reported only with a
concrete failure scenario (see `agents/money-reviewer.md`).

A project adds its own checklists with `rules` in its config, and its invariants with
`invariants` (`INV-n`); see [docs/config.md](../../../../../docs/config.md). Those rules
stay with the project, not here.
