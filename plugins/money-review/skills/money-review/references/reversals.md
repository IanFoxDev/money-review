# Refunds, chargebacks and reversals (REV)

The question for every change: does every reversal undo exactly the original it belongs
to, by the amount that was really reversed, on the same accounts, and nothing else?

A reversal is a refund, a chargeback, a void, a cancelled bet, a rolled-back transfer
or a credit note. Each of them points at an earlier money movement. Most bugs here come
from finding the wrong original, or from booking the reversal as if it were a new,
independent movement.

## REV-1. Reversal linked to the wrong original

Look for: a refund or chargeback resolved by our own order or merchant reference when
one order can have several provider transactions (initial charge, rebills, retries);
matching by user, member id, amount or "the latest purchase" with `findOne` /
`getFirstEntry` and no tie-break; a reversal that is matched only when it carries the
original id and silently dropped otherwise.

Failure scenario: a subscription has an initial charge and three rebills under the same
merchant reference. A refund for the third rebill arrives; the handler looks up the
purchase by merchant reference and refunds the initial charge. Revenue, affiliate
commission and access are corrected on the wrong period; the third rebill still counts
as paid.

Good: link by the provider's id of the original transaction (`related_transaction_id`,
`original_payment_id`, `parent`), stored at the time of the charge; when the link is
missing, park the reversal for review instead of guessing.

Do not report: a domain where one reference has exactly one transaction, enforced by a
unique index.

## REV-2. Reversal booked as a new movement instead of mirroring the original

Look for: a refund, rollback or cancel that calls a generic credit (`applyWin`,
`credit`, `increaseBalance`, `createPurchase`) instead of reversing the original
entries; a reversal recomputed from current data (today's exchange rate, today's fee
schedule, today's tax rate, today's split between bonus and real money) instead of
copied from the original; commission, VAT, affiliate share or revenue share not reversed
in proportion.

Failure scenario: a bet of 10.00 is debited 7.00 from the bonus balance and 3.00 from
the real balance. The provider cancels the round; the cancel handler credits 10.00 to
the real balance as a win. The player turns 7.00 of bonus into withdrawable money, and
the "wins" report includes a refund. A refund of a EUR payment taken a month ago is
converted at today's rate, and the ledger's EUR clearing account no longer nets to zero.

Good: the reversal reads the original entries by transaction id and posts the same
legs with the opposite sign and the original amounts and rates; a partial reversal is
allocated over the original legs in a fixed order (see MONEY-4).

Do not report: a domain where the business rule says the reversal goes elsewhere (a
refund to store credit by the customer's choice), recorded as such.

## REV-3. Reversals add up to more than the original

Look for: a refund limit that checks the request against the original amount but not
against refunds already made; several partial refunds or a refund plus a chargeback on
the same payment; a dedup that uses "is this payment refunded" (a flag) so a second
partial refund is dropped, or the opposite: no dedup at all.

Failure scenario: a payment of 100.00 gets a refund of 60.00. A second refund of 60.00
is checked against the payment amount (60 <= 100) and goes through: 120.00 refunded for
100.00 paid. With a flag-based dedup, the second legitimate partial refund of 40.00 is
treated as a duplicate and never booked, so the ledger shows 40.00 more revenue than
the provider settled.

Good: `refundable = captured - sum(reversals)` computed from the reversal records under a
lock or a constraint (see RACE-1); dedup each reversal by its own provider id, not by a
flag on the original.

Do not report: a provider that rejects over-refunds and whose answer the code checks
before booking.

See also MONEY-7: the amount of each reversal comes from the event, not from the
original.

## REV-4. A failure or decline undone by paying out of our own money

Look for: a decline, failure, expiry or reversal handler that credits the customer or
the wallet; a "refund" issued for a charge that was never captured or settled; holds
released by a new credit instead of releasing the hold.

Failure scenario: a card authorisation of 50.00 places a hold. The merchant declines
it later; the decline handler "refunds" 50.00 to the card balance from the house account
instead of releasing the hold. The customer gets 50.00 that was never taken. Repeated
at scale, this is how a fintech lost millions on declined transactions.

Good: a decline releases exactly the hold it belongs to (a no-op when already
released); only a settled charge can be refunded.

Do not report: a goodwill credit that is booked to an explicit compensation account and
approved as such.

## REV-5. Side effects of a reversal missing or applied to the wrong scope

Look for: a refund or chargeback that does not revoke the access, tokens, bonus or
subscription period it paid for, or revokes more than it paid for (a partial refund that
cancels the whole subscription); a won chargeback (the dispute reversed in our favour)
that is only a flag and does not restore revenue; affiliate or partner commissions paid
on a sale that was later refunded, with no clawback.

Failure scenario: a user buys 1 000 tokens, spends them, and gets a chargeback. The
handler records the chargeback but the token balance is not touched; the next purchase
pattern repeats it. A partner was paid 30% on a sale that was refunded a week later;
nothing claws it back, and the payout report overpays every month.

Good: each reversal type has a defined effect on entitlements and on downstream shares,
in the same unit of work as the money entry, or recorded so a job applies it.

Do not report: a business rule that keeps access after a refund, documented in code.

## MongoDB, Go and events

- A reversal stored as a child of the original (`parent_transaction`) is itself
  something a later query may select as "refundable": make sure reversal queries
  exclude reversals (see REV-3).
- Mutating the original document's embedded data while building the reversal (copying
  `info` and changing it in place) changes the original too.
- When a reversal emits an event, the event must point at the original id that
  consumers key on; see TX-9.
