# Real-bug eval, first run

Measured 2026-10-17 with money-review 0.8.3 (56439bc), Claude Code 2.1.302, models
claude-opus-5-5 and claude-sonnet-5-5. 15 cases from `eval/real/` (12 bugs, 3 controls),
one run each. One run per case is a smoke test of the set, not a baseline: the baseline
needs several runs per case and more cases.

| Metric | Value |
|---|---|
| Bugs found | 11 of 12 (recall 92%, the same under any rule) |
| Missed | 1, skipped by triage before review |
| False alarms on controls | 0 of 3 |
| Other findings marked false | 2, in one case (see below) |
| Time per reviewed run | 80 s |
| API-equivalent cost per reviewed run | 0.37 USD |

By mode:

| Mode | Bugs | Found |
|---|---|---|
| introducer (the review of the pull request that shipped the bug) | 6 | 6 |
| reverse (the fix undone) | 6 | 5 |

By family: MONEY 8 of 8, NEW-STATE 2 of 2, NEW-TIME 1 of 1, RACE 0 of 1.

## The miss

`blnk-unlock-request-ctx`: the Redis lock of a balance is released on the request
context. The change is in `internal/lock/lock.go`, a file with no money words, so triage
skipped it and Claude never saw it. A lock, an idempotency store or an outbox can sit in
code that says nothing about money. In a real setup `money_paths` covers such files; the
defaults do not.

## The two findings counted as false

Both are in `blnk-inflight-dryrun-amount`, in the dry-run code the case adds: the preview
rejects a whole action when one leg is already settled while the real path settles the
rest, and a leg projection reports the original amount next to a partial precise amount.
Upstream reworked the same function in two later fixes (b9ed19f, 9de80ef) for related
but not identical reasons. They stay counted as false; the case does not list them.

## What this does not show yet

- Contamination. 6 of the 12 bugs are from commits older than 2026 and may be known to the
  models. After June 2026 there are 5 bugs (4 found, the miss is one of them), and only one
  is an introducer case.
- Families. The set is mostly MONEY. Subscriptions, periods, provider events and data
  completeness, which dominate the bugs we see in production code, are 3 of 12.
- Stability. One run per case.
