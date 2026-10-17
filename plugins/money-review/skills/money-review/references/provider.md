# Provider events and responses (PSP)

The question for every change: does the code read what the payment provider said
correctly, and does every kind of message lead to the money action it really means?

A provider talks to us in webhooks, postbacks, redirects and API responses. Each of them
is a string, a number or a document that our code turns into "paid", "refunded",
"declined" or "nothing happened". Most money bugs here are not in the arithmetic but in
that translation.

## PSP-1. Unknown event mapped to a money action by default

Look for: a `match`, `switch` or `if` chain over event types, actions, transaction
types or status codes whose default branch grants, charges, credits or marks paid; a
fallback such as `default => EventType::CHARGE`, `else { $purchase->markPaid() }`, a
map lookup with a default of `success`.

Failure scenario: the provider adds a `void` event or sends a `rebill_decline` that the
handler does not list. The `default` branch maps it to `charge`, the order is marked
paid and access is granted for money that never arrived. Or a refund arrives with an
action the code does not know and is booked as a new sale.

```php
// bad
$type = match ($payload['action']) {
    'refund' => EventType::REFUND,
    'chargeback' => EventType::CHARGEBACK,
    default => EventType::CHARGE,
};

// good: list what grants money, refuse the rest
$type = match ($payload['action']) {
    'sale', 'rebill' => EventType::CHARGE,
    'refund' => EventType::REFUND,
    'chargeback' => EventType::CHARGEBACK,
    default => throw new UnknownProviderEvent($payload['action']),
};
```

Good: only the events that are known to move money in our favour lead to a grant; an
unknown event is logged, stored and answered so the provider does not lose it, but
nothing is credited.

Do not report: a default that does nothing with money (logs, ignores, stores the raw
event for later).

## PSP-2. Provider value read loosely

Look for: strings from the provider compared with `===` or `==` without normalising case
or whitespace; the string `"false"` or `"0"` used as a boolean; `!empty($response)` or
`if ($response)` as the success test; a missing key read with `?? true`, `?? false` or
`?? 'approved'`; `&&` and `||` mixed in a status condition; a field that is a list
when there are several items and a single map when there is one (XML, some JSON APIs);
amounts read from a differently named field (`authprice` against `price`, `amount`
against `amount_settled`).

Failure scenario: the provider answers `{"success": "false", "reason": "card expired"}`.
`if ($response['success'])` is true for any non-empty string, the rebill is marked paid
and the subscription extended for a month without a charge. Another provider sends
`APPROVED` in one product and `approved` in another; the case-sensitive check treats
the second as a decline and the customer is asked to pay again.

Good: parse into a typed result once, at the edge: explicit enums for statuses with
case normalisation, booleans parsed from the documented values only, a required field
that is missing is an error, a single XML element normalised to a list.

Do not report: a loose read of a field that does not decide money (a description, a
display name).

## PSP-3. Pending or deferred result treated as final

Look for: an API call or callback whose result can be `pending`, `deferred`,
`scheduled`, `processing` or `accepted` (asynchronous refunds, cancellations at the end
of the period, payouts in flight) where the code marks the operation done or failed
right away; an "already cancelled", "already refunded" or "already inactive" answer
treated as a failure and retried or escalated.

Failure scenario: a subscription is cancelled at the provider. The provider answers
`202 cancel scheduled at period end`; the job marks the cancellation done and never
looks again. The provider later fails to apply it and keeps billing the card every
month. In the other direction: the refund API answers "already refunded" to a retry,
the code records a failed refund and support refunds the customer a second time by hand.

Good: an explicit state for "accepted, not yet final" that something resolves later
(a webhook, a status poll); "already done" answers map to success after checking that
the earlier operation matches this one.

Do not report: a provider whose API documents the answer as final (a synchronous
capture that either succeeds or fails).

See also IDEM-4 (timeout as failure) and IDEM-10 (decline or business error not
handled): this rule is about an answer that arrived and was misread.

## PSP-4. Callback amount and currency not checked against the order

Look for: a success callback, redirect or IPN that marks an order paid or credits a
wallet without comparing the reported amount and currency with what we expected; a
credit that uses the amount from the payload instead of the order; a partial payment
accepted as full.

Failure scenario: the customer changes the amount in the hosted payment page request
from 100.00 to 1.00 (or pays 1.00 USD on an order of 100.00 EUR). The provider reports
`status=success, amount=1.00`; the handler only checks the status and credits the order
total of 100.00.

```php
// good
if ($cb->amountMinor !== $order->amountMinor || $cb->currency !== $order->currency) {
    $order->flagMismatch($cb);   // do not credit, alert
    return;
}
```

Good: the expected amount and currency are ours; the callback must match them exactly,
and a mismatch is a separate state, not a credit.

Do not report: a provider flow where the amount cannot change after we create the
payment and the callback carries only a reference that we resolve through the API.

## PSP-5. Message not authenticated, or status taken from an unsigned source

Look for: a webhook handler without signature verification; HMAC computed over
re-encoded JSON instead of the raw request body; signatures compared with `==` instead
of `hash_equals` (PHP) or `hmac.Equal` (Go); no timestamp tolerance, so an old signed
message can be replayed; an order marked paid from the redirect back to our site (query
string) without asking the provider API.

Failure scenario: the success redirect carries `?status=paid&order=42`. The return
controller marks order 42 paid from the query string. Anyone who knows the URL pattern
gets goods without paying. A replayed, correctly signed `payment.succeeded` from last
month credits the wallet again when dedup keys have expired.

Good: verify the signature over the raw bytes with a constant-time compare and a time
window; treat the redirect as a hint and confirm the state with the provider API or
the signed webhook.

Do not report: an endpoint that only stores the raw message and lets a verified worker
act on it.

## PSP-6. Late or out-of-order event moves a final state back

Look for: a handler that sets a status from an event without asking whether the current
state is final (`paid`, `refunded`, `charged back`, `expired`) or newer than the event;
decline, cancel or expire events applied after success; event timestamps ignored.

Failure scenario: the provider sends `approved` and, a minute later, a delayed
`declined` for a duplicate attempt of the same order. The handler sets the order to
`failed` and revokes access although the money is captured. An `expired` postback that
arrives after a lifetime upgrade revokes the lifetime access.

Good: a transition table: an event may only move a state forward; an event older than
the last applied one, or for another attempt, is stored and ignored. Combine with RACE-3
for the concurrent case.

Do not report: an event the provider documents as final and authoritative (a chargeback
can follow a success; that is a forward move, not a regression).

## PSP-7. Message acknowledged without being processed

Look for: a webhook branch that returns 200 or `OK` for an event type with a `TODO` or an
empty body; a `catch` that logs and returns 200, so the provider stops retrying; a
handler that answers before the money write is committed, in a process that can die.

Failure scenario: a `subscription_extended` event is answered `OK` by a stub handler.
The provider extended the subscription and charged the customer; we never extend
access, and the provider never sends the event again. Support finds it months later.

Good: return success only after the event is applied or durably stored for a worker;
unknown or unimplemented events are stored for review, not silently acknowledged.

Do not report: an event type that we explicitly do not need, ignored by design with a
comment that says so.

## MongoDB, Go and other providers' formats

- Go: decode provider JSON into typed structs with `json.Number` or decimal types;
  `map[string]interface{}` turns numbers into `float64` and strings stay unchecked.
- A `bool` field in Go defaults to `false` when the key is missing: a missing
  `"approved"` silently becomes a decline, or a missing `"test"` silently becomes live.
- When the handler writes the event and the money change to MongoDB in separate calls,
  see TX-3; when it dedups by event id, see IDEM-1 and IDEM-11.
