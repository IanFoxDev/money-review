# Provider checklist, IDEM-11, private rules

Measured 2026-10-19 with money-review after 0.8.3 (uncommitted work on the PSP checklist,
IDEM-11, private rules and invariants), models claude-opus-5-5 and claude-sonnet-5-5.

## New cases

Four cases for the new rules and one clean case next to them, on `eval/app`.

| Case | Rule | Runs | Found |
|---|---|---|---|
| psp-retention-discount-trusted | PSP-1 | 3 | 3 |
| psp-expire-without-provider-cancel | PSP-2 | 1 | 1 |
| psp-store-notification-any-type | PSP-3 | 1 | 1 |
| idem-projection-key-late-field | IDEM-11 | 1 | 1 |
| clean-retention-confirmed | none | 2 | no alarm |

The first version of both retention cases let the offer be accepted twice, which halves
the discounted price again; the reviewer reported it in both, rightly. The cases now
claim the offer with a conditional update. The bug case also reports that `price_cents`
defaults to 0 for old subscriptions; that is listed as acceptable. PSP-4 (a fix for one
provider only) has no case yet: `eval/app` has a single provider.

## Clean cases with the new checklist loaded

The seven clean cases on `eval/app` and two webhook bug cases, one run each, to see
whether the provider checklist adds noise:

| Metric | Value |
|---|---|
| False alarms on clean cases | 0 of 7 |
| idem-chargeback-webhook-no-dedup | 2 of 2 bugs |
| race-webhook-no-state-guard | 1 of 1 bug |
| Time per reviewed run | 45 s |

## Real bugs

`eval/real/`, 2026-10-20, one run per case (45 runs), against the baseline of 2026-10-17
(three runs per case). Private rules were off (`MONEY_REVIEW_PRIVATE` pointed nowhere).

| Metric | Baseline | With PSP and IDEM-11 |
|---|---|---|
| Precision | 93% (70 true, 5 false in 135 runs) | 92% (23 true, 2 false in 45 runs) |
| Recall | 61% | 61% |
| Recall, any rule | 75% | 79% |
| Recall on bugs fixed from 2026-06-01 | 52% | 50% |
| NEW-PSP bugs found | 50% (9 of 18) | 50% (3 of 6) |
| NEW-SUB bugs found | 33% (7 of 21) | 29% (2 of 7) |
| Clean runs with a false alarm | 0 of 27 | 0 of 9 |
| Bug cases skipped by triage | 12 runs (4 cases) | 2 runs (2 cases) |
| Time per reviewed run | 102 s | 95 s |
| API-equivalent cost per reviewed run | 0.38 USD | 0.39 USD |

What changed: the provider patterns bring two cases into scope that triage skipped before
(a Stripe trial webhook, a payment amount after capture); one is now found under another
rule, the other still missed. PSP rules were reported once, PSP-2 on the renewal of an
order with a scheduled cancellation, which is the case's bug (scored under its expected
rule IDEM-10). IDEM-11 was not reported. One case went from found to missed with a new
false alarm (midaz-counter-expiry-from-reservation-ttl); with one run that is within the
spread seen in the baseline.

Reading: on code nobody wrote for this tool the new public rules cost nothing measurable
and add little. Recall on provider and subscription bugs did not move. The gain on the
project these rules were written for came from the private rules, which carry facts about
its providers that no public rule can know.
