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
| `arithmetic.md` | MONEY | amounts, currencies, rounding, splitting; amounts in BSON and decoded JSON |

Each file starts with the rules in SQL terms, then a section that maps them to
MongoDB, Redis and message brokers and adds the rules that only exist there.
