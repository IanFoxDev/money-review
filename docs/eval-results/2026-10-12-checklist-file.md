# Eval run 2026-10-12: the checklist as one file

On a larger codebase, the reviewer was given the paths of several checklists and in
most runs read only the ones it judged relevant from their names. Rules from the other
checklists were never in front of it, and the same change got a finding in one run and
none in the next.

Change (`4bd1c07`): `prepare.sh` joins the checklists of each group into one file,
`checklists-<i>.md`, and all chosen checklists into `checklists.md` for the verifier.
Each agent gets one path, and the reviewer is told to read the file in full before the
diff: triage chose these categories, so every rule in the file is in scope.

## Result, same 50 cases, three runs each

| | Recall | Second bugs | Precision | Clean runs with a false alarm | Median time | USD per run |
|---|---|---|---|---|---|---|
| several checklist paths (`6cf9167`) | 91.2% | 32 of 45 | 100% | 0 of 36 | 80 s | 0.30 |
| one checklist file (`4bd1c07`) | 93.7% | 37 of 45 | 100% | 0 of 36 | 70 s | 0.33 |

MONEY recall went from 76% to 89%: rules such as MONEY-7 (amount from the wrong source)
sit in a checklist the reviewer used to skip on a change that looked like a race or a
retry. The cost is about 0.03 USD more per review on the API, from the longer prompt.

Before scoring, three case changes, applied to both runs:

- `money-chargeback-wrong-amount`: the chargeback dropped for a payment that is not
  `succeeded` was already accepted under IDEM-10, IDEM-8 and RACE-3; one run reported it
  under MONEY-0, now accepted too.
- `race-refund-cap-sum`: the second bug can also be reported where the decrement on a
  declined refund was removed (`RefundService.php`, the `failed` update).
- `tx-nested-payout-email`: the new batch job checks its daily limit against the
  current batch only, so a second run on the same day approves another full limit.
  Nothing in the case limits the job to one run a day. Accepted as a real extra under
  MONEY-7 and MONEY-0.

`eval/compare.sh` reports no regressions. Four cases lost one run each, with no common
cause: a second bug left out of one run (`idem-retry-fresh-key`, `race-refund-cap-sum`),
the verifier rejecting the planted bug once (`mongo-idem8-relay-without-key`, "nothing
in this repository produces a second event"), and the verifier merging the planted bug
into a MONEY-0 finding once (`mongo-race7-lock-only-guard`).

50 cases, 150 runs.

Measured 2026-10-12 with money-review 0.8.1 (4bd1c07), Claude Code 2.1.296.
Models: claude-opus-5-5, claude-sonnet-5-5.

| Metric | Value |
|---|---|
| Precision | 100% (149 true, 0 false) |
| Recall | 94% (10 missed) |
| Recall, any rule | 94% (10 found under another rule) |
| Clean runs with a false alarm | 0 of 36 |
| Bug cases skipped by triage | 0 |
| Duplicates, acceptable extras | 6, 9 |
| Errors | 0 |
| Time per reviewed run | 79.299 s |
| API-equivalent cost per reviewed run | 0.329 USD (total 47.32) |

## By category

| Category | Bugs | Found | Recall |
|---|---|---|---|
| IDEM | 39 | 36 | 92% |
| MONEY | 54 | 48 | 89% |
| RACE | 30 | 29 | 97% |
| TX | 36 | 36 | 100% |

## By case

| Case | Runs | Found / bugs | Any rule | False alarms | Skipped | s | USD |
|---|---|---|---|---|---|---|---|
| clean-avatar-upload | 3 | 0 / 0 | 0 | 0 | 3 | 0 | 0 |
| clean-chargeback-webhook | 3 | 0 / 0 | 0 | 0 | 0 | 26 | 0.15 |
| clean-commission-rounding | 3 | 0 / 0 | 0 | 0 | 0 | 24 | 0.14 |
| clean-installments | 3 | 0 / 0 | 0 | 0 | 0 | 18 | 0.1 |
| clean-ledger-refactor | 3 | 0 / 0 | 0 | 0 | 0 | 23 | 0.14 |
| clean-payment-receipt | 3 | 0 / 0 | 0 | 0 | 0 | 22 | 0.13 |
| clean-payout-approval | 3 | 0 / 0 | 0 | 0 | 0 | 28 | 0.15 |
| clean-revenue-report | 3 | 0 / 0 | 0 | 0 | 0 | 21 | 0.12 |
| idem-cashback-rerun | 3 | 3 / 3 | 3 | 0 | 0 | 66 | 0.34 |
| idem-chargeback-webhook-no-dedup | 3 | 6 / 6 | 6 | 0 | 0 | 116 | 0.54 |
| idem-dedup-outside-transaction | 3 | 3 / 3 | 3 | 0 | 0 | 78 | 0.38 |
| idem-retry-around-credit | 3 | 3 / 3 | 3 | 0 | 0 | 67 | 0.3 |
| idem-retry-fresh-key | 3 | 5 / 6 | 5 | 0 | 0 | 82 | 0.38 |
| idem-timeout-as-failure | 3 | 3 / 3 | 3 | 0 | 0 | 71 | 0.33 |
| money-balance-without-entry | 3 | 3 / 3 | 3 | 0 | 0 | 74 | 0.36 |
| money-chargeback-wrong-amount | 3 | 6 / 6 | 6 | 0 | 0 | 112 | 0.53 |
| money-commission-rounding | 3 | 4 / 6 | 4 | 0 | 0 | 86 | 0.37 |
| money-float-fee | 3 | 5 / 6 | 5 | 0 | 0 | 115 | 0.43 |
| money-mixed-currency-total | 3 | 3 / 3 | 3 | 0 | 0 | 58 | 0.27 |
| money-refund-sign | 3 | 3 / 3 | 3 | 0 | 0 | 59 | 0.3 |
| money-split-rounding | 3 | 3 / 3 | 3 | 0 | 0 | 66 | 0.27 |
| mongo-clean-consumer-metrics | 3 | 0 / 0 | 0 | 0 | 0 | 23 | 0.12 |
| mongo-clean-ledger-refactor | 3 | 0 / 0 | 0 | 0 | 0 | 21 | 0.14 |
| mongo-clean-relay-batch | 3 | 0 / 0 | 0 | 0 | 3 | 0 | 0 |
| mongo-clean-wallet-hold | 3 | 0 / 0 | 0 | 0 | 0 | 29 | 0.14 |
| mongo-idem1-commission-random-key | 3 | 3 / 3 | 3 | 0 | 0 | 69 | 0.31 |
| mongo-idem2-redis-dedup | 3 | 3 / 3 | 3 | 0 | 0 | 414 | 0.47 |
| mongo-idem7-commit-before-apply | 3 | 3 / 3 | 3 | 0 | 0 | 183 | 0.28 |
| mongo-idem8-relay-without-key | 3 | 2 / 3 | 2 | 0 | 0 | 78 | 0.34 |
| mongo-money1-go-float | 3 | 3 / 3 | 3 | 0 | 0 | 90 | 0.34 |
| mongo-race1-findone-set | 3 | 8 / 9 | 8 | 0 | 0 | 93 | 0.49 |
| mongo-race3-refund-without-status | 3 | 3 / 3 | 3 | 0 | 0 | 83 | 0.39 |
| mongo-race5-payout-unique-in-code | 3 | 3 / 3 | 3 | 0 | 0 | 77 | 0.38 |
| mongo-race7-lock-only-guard | 3 | 2 / 3 | 3 | 0 | 0 | 74 | 0.34 |
| mongo-race8-secondary-balance | 3 | 11 / 12 | 11 | 0 | 0 | 99 | 0.47 |
| mongo-tx2-produce-after-write | 3 | 6 / 6 | 6 | 0 | 0 | 106 | 0.5 |
| mongo-tx3-transfer-without-transaction | 3 | 5 / 6 | 5 | 0 | 0 | 97 | 0.46 |
| mongo-tx7-missing-session | 3 | 3 / 3 | 3 | 0 | 0 | 63 | 0.29 |
| mongo-tx8-provider-in-callback | 3 | 3 / 3 | 3 | 0 | 0 | 109 | 0.34 |
| race-lock-order | 3 | 3 / 3 | 3 | 0 | 0 | 72 | 0.31 |
| race-refund-cap-sum | 3 | 5 / 6 | 5 | 0 | 0 | 92 | 0.44 |
| race-unique-in-code | 3 | 3 / 3 | 3 | 0 | 0 | 61 | 0.32 |
| race-webhook-no-state-guard | 3 | 3 / 3 | 3 | 0 | 0 | 62 | 0.28 |
| race-withdraw-no-lock | 3 | 9 / 9 | 9 | 0 | 0 | 102 | 0.5 |
| tx-nested-payout-email | 3 | 3 / 3 | 3 | 0 | 0 | 90 | 0.4 |
| tx-payout-batch-one-transaction | 3 | 3 / 3 | 3 | 0 | 0 | 99 | 0.45 |
| tx-publish-after-commit | 3 | 3 / 3 | 3 | 0 | 0 | 67 | 0.4 |
| tx-refund-call-in-transaction | 3 | 3 / 3 | 3 | 0 | 0 | 81 | 0.4 |
| tx-split-transfer | 3 | 3 / 3 | 3 | 0 | 0 | 87 | 0.42 |
| tx-swallowed-ledger-error | 3 | 3 / 3 | 3 | 0 | 0 | 73 | 0.34 |

## Missed

- idem-retry-fresh-key: IDEM-10 or MONEY-0 `app/Jobs/RetryFailedPayout.php:30`
- money-commission-rounding: MONEY-2 `app/Services/PartnerCommission.php:47`
- money-float-fee: MONEY-5 or MONEY-0 `app/Services/FeeCalculator.php:17`
- mongo-idem8-relay-without-key: IDEM-8 `src/Events/OutboxRelay.php:45`
- mongo-race1-findone-set: IDEM-5 or MONEY-0 `src/Money/FeeCharger.php:29`
- mongo-race7-lock-only-guard: RACE-7 or RACE-1 or RACE-3 `src/Payouts/PayoutService.php:68`
- mongo-race8-secondary-balance: MONEY-6 or MONEY-0 `src/Payouts/InstantWithdrawal.php:34`
- mongo-tx3-transfer-without-transaction: MONEY-0 or TX-4 `src/Money/Ledger.php:51`
- race-refund-cap-sum: MONEY-7 or MONEY-0 or TX-3 `app/Jobs/ResolvePendingRefunds.php:26`

