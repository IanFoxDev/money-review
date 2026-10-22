# Subscription lifecycle (SUB)

The question for every change: after this change, is every customer charged exactly
once per period they have, for the plan they have, and does every access period match
a charge?

Subscriptions move money on a schedule and through state changes: trial, paid, renewed,
upgraded, downgraded, converted, cancelled, expired, reactivated. A bug is often not in
one line but in a transition that forgets the other side: we change our state and the
provider keeps billing, or the provider stops and we keep granting.

## SUB-1. Plan change leaves the old recurring charge running

Look for: an upgrade, downgrade, conversion to lifetime, plan switch or account merge
that creates the new subscription or grant but does not cancel the old recurring
agreement at the provider (or cancels only our copy); a cancel call whose failure is only
logged; a new path that grants a plan and skips the cancel that the main path does.

Failure scenario: a monthly subscriber buys the lifetime plan. The code grants lifetime
access and marks the monthly subscription `converted` in our database, but the recurring
sale at the provider is not cancelled. The card is charged every month for a plan the
customer already replaced; the first chargeback arrives three months later.

Good: the old agreement is cancelled at the provider as part of the change, and a failed
cancel is a retried, visible state (not a log line); the new grant waits for, or is
compensated by, that cancel.

Do not report: a provider that ends the old agreement itself when the new one is created
(an in-place plan change through the provider API).

## SUB-2. Two active subscriptions where the product allows one

Look for: a purchase or renewal path that does not check for an existing active
subscription of the same type for the user; a rebill selection that does not exclude
users who have a newer active subscription; uniqueness of "active per user and type"
enforced only in code (see RACE-5).

Failure scenario: a user's card fails, they buy a new subscription with another card.
The old subscription stays `past_due` and the dunning job keeps retrying it. Two days
later the old card is topped up, the retry succeeds, and the user pays twice for the
same month.

Good: the rebill or retry job checks that the subscription is still the user's current
one; the product rule is enforced by a unique index or a lock on the user.

Do not report: products where several concurrent subscriptions are legitimate (per seat,
per site), when the code keys them that way.

## SUB-3. Renewal selects subscriptions it must not charge

Look for: the query or condition that picks subscriptions to renew, rebill or retry:
missing filters for `cancel_at_period_end`, cancelled, refunded, charged back, paused
or already renewed for this period; a retry policy keyed on the clock (`hour % 12 == 0`,
"last attempt more than N hours ago" over failed attempts only) instead of on the
period being paid.

Failure scenario: the user cancels with "at the end of the period". The renewal job
selects active subscriptions whose period ends today and does not look at
`cancel_at_period_end`; the user is charged for a month they cancelled. Or the retry
guard looks only at failed attempts: a pending attempt from an hour ago is ignored and
a second charge for the same period goes out.

Good: renewal is keyed on (subscription, period): one charge record per period, created
before the call, unique, and its state decides whether to call again (see IDEM-5).

Do not report: a provider-driven renewal where we only record what the provider charged.

## SUB-4. Access period computed from the wrong base

Look for: an extension computed from `now()` instead of from the current end of the
period; local plan-day arithmetic (30 days) where the provider bills by calendar month
(or the reverse); expiry set from our clock while the next charge date comes from the
provider; an upgrade or conversion purchase recorded without an expiry; access ending
before the next charge would happen.

Failure scenario: a rebill arrives two days early. The handler sets the new end to
`now + 30 days`, cutting two paid days. Over a year of early rebills the customer loses
weeks of paid access. In the other direction, a late rebill extended from `now` gives
free days. A plan billed "every 1 month" is extended by 30 days: in a 31-day month access
lapses a day before the charge, and the customer sees "expired" while paying.

Good: the new end is the old end plus one billing period in the provider's unit; where
the provider tells the next charge date, access is bounded by it.

Do not report: a product rule that deliberately restarts the period on payment
(prepaid packs), documented as such; a subscription that had already expired, renewed
from now, when the user had no access in the gap and the paid period is counted in full.

## SUB-5. Cancellation applied with the wrong timing or to a final state

Look for: "cancel at period end" implemented as an immediate cancel (paid days lost) or
an immediate cancel implemented as end-of-period (charged again); a cancel or expire
write without a condition on the current state, so it overwrites `refunded`,
`charged_back` or `lifetime`; cancel requests sent twice to the provider; a provider's
deferred cancel treated as done (see PSP-6); provider-side reactivations never recorded.

Failure scenario: an `expire` webhook for a subscription that was already upgraded to
lifetime sets `status = expired` by id. The lifetime customer loses access and asks for a
refund. A user reactivates at the provider's portal; we never record it and keep the
subscription expired while the provider charges monthly.

Good: state changes carry the expected current state in the write (RACE-3); each
cancellation type has its own path and stored effective date; provider-side state is
reconciled.

Do not report: a cancel that the business defines as immediate for a reason (fraud),
recorded with that reason.

## SUB-6. Trials, promotions and renewal price

Look for: a trial that can be taken again (no check by customer, card fingerprint or
email); a trial that converts without a stored payment method or mandate; a promotion or
coupon that applies to every renewal instead of the first, or stacks with another; the
renewal price read from the current catalog instead of the price the customer agreed to;
a percentage increase applied with rounding that differs from the invoice.

Failure scenario: a coupon "50% off the first month" is stored on the subscription
without a duration. Every renewal applies it, the subscription is billed at half price
forever. A catalog price change from 9.99 to 12.99 silently raises existing customers on
their next renewal, which the terms do not allow.

Good: discounts carry their scope (first period, N periods, forever) and are consumed;
the agreed price is stored on the subscription; trial eligibility is checked against a
durable record.

Do not report: price changes the product applies to everyone by design, with notice
handled elsewhere.

## SUB-7. Proration with the wrong basis

Look for: a plan change mid-period whose credit for unused time uses the current list
price instead of the price paid for that period; a denominator of 30 days instead of the
real length of the period; a credit not linked to the original invoice, so a later
refund refunds both the credit and the original.

Failure scenario: a customer paid 30.00 for a 31-day month and upgrades on day 16. The
code credits `(15 / 30) * current price 35.00 = 17.50` instead of
`(15 / 31) * 30.00 = 14.52`. Every upgrade gives away about 3.00.

Good: proration from the paid amount and the real period length, with an explicit
rounding rule (MONEY-3), and the credit stored as a line linked to the original charge.

## Provider and data notes

- When the provider is the source of truth for renewals, our state is a copy: every
  provider event that changes the agreement (rebill, cancel, reactivate, change of
  plan) needs a handler, or the copy drifts (see PSP-10).
- A denormalised copy of subscriptions on the user document (a list rewritten in full
  by a hook) loses entries when two writes race (RACE-2).
