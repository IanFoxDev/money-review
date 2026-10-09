# Eval run 2026-10-08: a second look

The 2026-10-08 run ([2026-10-08-rules.md](2026-10-08-rules.md)) found 25 of the 45
second bugs, the quieter bug next to the planted one. Most of the misses were not
rejected by the verifier: the reviewer folded the second bug into the scenario or the
fix of the first finding.

Two tries:

- **Separate findings rule** (`45ddab4`, reverted): both prompts said that two defects
  are two findings when the smallest fix of one leaves the other. Full run: 25 of 45
  second bugs again, recall 86.2%, more duplicates, and `idem-retry-fresh-key` dropped
  from 3 of 3 to 0 of 3 on its decline bug. No effect on the target; reverted.
- **Second look** (`6cf9167`, kept): when the reviewer finds something, it reviews the
  same change once more, told what it already found, for other money bugs. The verifier
  still runs once for all candidates. Changes with no candidate, clean ones among them,
  do not get the second look.

## Result, same 50 cases, three runs each

| | Recall | Second bugs | Precision | Clean runs with a false alarm | Median time | USD per run |
|---|---|---|---|---|---|---|
| without the second look | 87.4% | 25 of 45 | 100% | 0 of 36 | 62 s | 0.27 |
| with the second look | 91.2% | 31 of 45 | 100% | 0 of 36 | 80 s | 0.30 |

On a subscription the extra pass uses the limits, not money; on the API it would cost
about 0.03 USD more per review on average.

Before scoring, two case changes, applied to both runs:

- `race-refund-cap-sum`: its second bug (`refunded_cents` no longer incremented but
  still decremented) was reported where the increment was removed, in
  `RefundService.php`, while the anchor was in `ResolvePendingRefunds.php`. Bugs can now
  name another place where they can fairly be reported (`also` in `case.json`).
- `money-chargeback-wrong-amount`: the old code drops a chargeback for a payment that is
  not `succeeded` after recording the event. It was already accepted under IDEM-10 and
  RACE-3; the second look reported it under IDEM-8 in all three runs, now accepted too.

`eval/compare.sh` against the previous baseline flags one case:
`mongo-tx3-transfer-without-transaction` found its second bug (the credit result is not
checked, so a missing wallet loses the debited money) in 2 of 3 runs, as before, but
labelled TX-3, the rule of the planted bug, instead of MONEY-0 or TX-4. The eval counts
a TX-3 finding there as a duplicate of the planted bug. The rules of the second bug are
not widened, so that a repeat of the planted bug cannot count for it.

What is still missed is in MONEY (76%): mostly the sign of an input amount and a balance
changed without a ledger entry when another finding is on the same lines.

50 cases, 150 runs.

Measured 2026-10-08 with money-review 0.7.0 (6cf9167), Claude Code 2.1.294.
Models: claude-opus-5-5, claude-sonnet-5-5.

| Metric | Value |
|---|---|
| Precision | 100% (145 true, 0 false) |
| Recall | 91% (14 missed) |
| Recall, any rule | 91% (3 found under another rule) |
| Clean runs with a false alarm | 0 of 36 |
| Bug cases skipped by triage | 0 |
| Duplicates, acceptable extras | 5, 7 |
| Errors | 0 |
| Time per reviewed run | 130.743 s |
| API-equivalent cost per reviewed run | 0.297 USD (total 42.73) |

## By category

| Category | Bugs | Found | Recall |
|---|---|---|---|
| IDEM | 39 | 38 | 97% |
| MONEY | 54 | 41 | 76% |
| RACE | 30 | 30 | 100% |
| TX | 36 | 36 | 100% |

## By case

| Case | Runs | Found / bugs | Any rule | False alarms | Skipped | s | USD |
|---|---|---|---|---|---|---|---|
| clean-avatar-upload | 3 | 0 / 0 | 0 | 0 | 3 | 0 | 0 |
| clean-chargeback-webhook | 3 | 0 / 0 | 0 | 0 | 0 | 26 | 0.15 |
| clean-commission-rounding | 3 | 0 / 0 | 0 | 0 | 0 | 34 | 0.15 |
| clean-installments | 3 | 0 / 0 | 0 | 0 | 0 | 19 | 0.11 |
| clean-ledger-refactor | 3 | 0 / 0 | 0 | 0 | 0 | 23 | 0.11 |
| clean-payment-receipt | 3 | 0 / 0 | 0 | 0 | 0 | 24 | 0.1 |
| clean-payout-approval | 3 | 0 / 0 | 0 | 0 | 0 | 30 | 0.15 |
| clean-revenue-report | 3 | 0 / 0 | 0 | 0 | 0 | 25 | 0.12 |
| idem-cashback-rerun | 3 | 3 / 3 | 3 | 0 | 0 | 77 | 0.31 |
| idem-chargeback-webhook-no-dedup | 3 | 6 / 6 | 6 | 0 | 0 | 113 | 0.4 |
| idem-dedup-outside-transaction | 3 | 3 / 3 | 3 | 0 | 0 | 93 | 0.35 |
| idem-retry-around-credit | 3 | 3 / 3 | 3 | 0 | 0 | 80 | 0.29 |
| idem-retry-fresh-key | 3 | 6 / 6 | 6 | 0 | 0 | 107 | 0.41 |
| idem-timeout-as-failure | 3 | 3 / 3 | 3 | 0 | 0 | 361 | 0.3 |
| money-balance-without-entry | 3 | 3 / 3 | 3 | 0 | 0 | 89 | 0.33 |
| money-chargeback-wrong-amount | 3 | 6 / 6 | 6 | 0 | 0 | 146 | 0.5 |
| money-commission-rounding | 3 | 4 / 6 | 4 | 0 | 0 | 90 | 0.36 |
| money-float-fee | 3 | 4 / 6 | 4 | 0 | 0 | 110 | 0.32 |
| money-mixed-currency-total | 3 | 3 / 3 | 3 | 0 | 0 | 65 | 0.24 |
| money-refund-sign | 3 | 3 / 3 | 3 | 0 | 0 | 124 | 0.28 |
| money-split-rounding | 3 | 3 / 3 | 3 | 0 | 0 | 105 | 0.28 |
| mongo-clean-consumer-metrics | 3 | 0 / 0 | 0 | 0 | 0 | 33 | 0.13 |
| mongo-clean-ledger-refactor | 3 | 0 / 0 | 0 | 0 | 0 | 40 | 0.14 |
| mongo-clean-relay-batch | 3 | 0 / 0 | 0 | 0 | 3 | 0 | 0 |
| mongo-clean-wallet-hold | 3 | 0 / 0 | 0 | 0 | 0 | 38 | 0.15 |
| mongo-idem1-commission-random-key | 3 | 3 / 3 | 3 | 0 | 0 | 62 | 0.28 |
| mongo-idem2-redis-dedup | 3 | 3 / 3 | 3 | 0 | 0 | 93 | 0.35 |
| mongo-idem7-commit-before-apply | 3 | 3 / 3 | 3 | 0 | 0 | 70 | 0.28 |
| mongo-idem8-relay-without-key | 3 | 3 / 3 | 3 | 0 | 0 | 102 | 0.32 |
| mongo-money1-go-float | 3 | 2 / 3 | 2 | 0 | 0 | 138 | 0.38 |
| mongo-race1-findone-set | 3 | 5 / 9 | 5 | 0 | 0 | 105 | 0.34 |
| mongo-race3-refund-without-status | 3 | 3 / 3 | 3 | 0 | 0 | 81 | 0.32 |
| mongo-race5-payout-unique-in-code | 3 | 3 / 3 | 3 | 0 | 0 | 139 | 0.34 |
| mongo-race7-lock-only-guard | 3 | 3 / 3 | 3 | 0 | 0 | 98 | 0.34 |
| mongo-race8-secondary-balance | 3 | 10 / 12 | 10 | 0 | 0 | 127 | 0.41 |
| mongo-tx2-produce-after-write | 3 | 6 / 6 | 6 | 0 | 0 | 221 | 0.38 |
| mongo-tx3-transfer-without-transaction | 3 | 3 / 6 | 3 | 0 | 0 | 92 | 0.35 |
| mongo-tx7-missing-session | 3 | 3 / 3 | 3 | 0 | 0 | 1711 | 0.27 |
| mongo-tx8-provider-in-callback | 3 | 3 / 3 | 3 | 0 | 0 | 288 | 0.41 |
| race-lock-order | 3 | 3 / 3 | 3 | 0 | 0 | 72 | 0.3 |
| race-refund-cap-sum | 3 | 6 / 6 | 6 | 0 | 0 | 119 | 0.36 |
| race-unique-in-code | 3 | 3 / 3 | 3 | 0 | 0 | 69 | 0.29 |
| race-webhook-no-state-guard | 3 | 3 / 3 | 3 | 0 | 0 | 63 | 0.28 |
| race-withdraw-no-lock | 3 | 9 / 9 | 9 | 0 | 0 | 184 | 0.55 |
| tx-nested-payout-email | 3 | 3 / 3 | 3 | 0 | 0 | 75 | 0.31 |
| tx-payout-batch-one-transaction | 3 | 3 / 3 | 3 | 0 | 0 | 139 | 0.42 |
| tx-publish-after-commit | 3 | 3 / 3 | 3 | 0 | 0 | 102 | 0.29 |
| tx-refund-call-in-transaction | 3 | 3 / 3 | 3 | 0 | 0 | 88 | 0.35 |
| tx-split-transfer | 3 | 3 / 3 | 3 | 0 | 0 | 103 | 0.33 |
| tx-swallowed-ledger-error | 3 | 3 / 3 | 3 | 0 | 0 | 83 | 0.31 |

## Missed

- money-commission-rounding: MONEY-2 `app/Services/PartnerCommission.php:47`
- money-float-fee: MONEY-5 or MONEY-0 `app/Services/FeeCalculator.php:17`
- mongo-money1-go-float: MONEY-1 or MONEY-3 `go/internal/credits/consumer.go:15`
- mongo-race1-findone-set: MONEY-6 or MONEY-0 `src/Money/FeeCharger.php:27`
- mongo-race1-findone-set: IDEM-5 or MONEY-0 `src/Money/FeeCharger.php:29`
- mongo-race8-secondary-balance: MONEY-6 or MONEY-0 `src/Payouts/InstantWithdrawal.php:34`
- mongo-tx3-transfer-without-transaction: MONEY-0 or TX-4 `src/Money/Ledger.php:51`

