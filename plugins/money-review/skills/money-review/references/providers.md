# Payment providers (PSP)

The provider is a second ledger that we do not control. It keeps its own subscription
schedule, retries declined charges on its own timetable, sends notifications for more
than payments, and may accept a request without doing what it asked. The question for
every change that talks to a provider or acts on its state: what does the provider
believe after this code runs, and does our side agree?

A provider talks to us in webhooks, postbacks, redirects and API responses. Each of them
is a string, a number or a document that our code turns into "paid", "refunded",
"declined" or "nothing happened". Most money bugs here are not in the arithmetic but in
that translation.

## PSP-1. Provider change trusted on an accepted response

Look for: a call that changes money terms at the provider (a discount, a new price, a
plan or billing cycle change, a pause, a cancellation, a refund request) where the code
marks the change as done because the call returned 200, `success: true` or a redirect,
and nothing later checks that the provider applied it: no read-back of the subscription,
no check of the next charge amount, no reconciliation.

Failure scenario: a retention flow offers 50% off, sends a modify request with a billing
cycle the provider does not accept for this subscription. The provider answers 200 and
ignores it. We record the discount as granted and tell the user. The next rebill charges
the full 29.99; the user complains, asks for a refund or files a chargeback.

```php
// bad: the answer is the only evidence
$response = $this->gateway->modifySubscription($sub->providerId, ['price' => 14.99]);
if ($response->ok()) {
    $sub->update(['discount_applied' => true]);
}

// good: record the request, confirm the effect from the provider's own state
$response = $this->gateway->modifySubscription($sub->providerId, ['price' => 14.99]);
$sub->update(['discount_status' => 'requested']);
$remote = $this->gateway->getSubscription($sub->providerId);
if ((int) round($remote->nextAmount * 100) !== 1499) {
    $sub->update(['discount_status' => 'not_applied']);
    $this->alerts->discountNotApplied($sub);
    return;
}
$sub->update(['discount_status' => 'applied']);
```

Also look for: parameters built from our settings (plan cycle, interval unit, product
id) for subscriptions that were created under older settings, where the provider keeps
the values from the time of creation.

Good: the stored state says "requested" until something from the provider confirms
it: a read-back, a notification with the new terms, the amount of the next charge.

Do not report: a provider whose API documents that an accepted request is applied
synchronously and fails otherwise, when the code checks that failure. Name the
documentation or the code that shows it.

## PSP-2. Our "not active" is not the provider's "will not charge"

Look for: a decision that assumes the provider will not charge a subscription because
of our local state: a guard against a second purchase that counts only subscriptions
with `expires_at > now`, a status set to `expired` or `canceled` without a cancel call
at the provider, a new subscription created while the old one is still alive at the
provider, a local expiry date that can come before the provider's next rebill.

Failure scenario: our expiry is set to the last paid period, the provider rebills a few
days later and retries a declined rebill for up to two weeks. On day 2 after our expiry
the user sees "no subscription" and buys again through another provider. On day 4 the
first provider's retry succeeds. The user pays twice for the same month, then asks for
a refund or files a chargeback.

```php
// bad: only our dates decide whether the user has a subscription
$active = Subscription::where('user_id', $userId)
    ->where('expires_at', '>', now())
    ->exists();

// good: a subscription counts until the provider can no longer charge it
$active = Subscription::where('user_id', $userId)
    ->whereIn('status', ['active', 'past_due', 'canceled_pending'])
    ->where(fn ($q) => $q->where('expires_at', '>', now())
        ->orWhere('provider_may_charge_until', '>', now()))
    ->exists();
// and when a new purchase replaces an old subscription: cancel the old one at the
// provider first, or in the same flow, and check that the cancel was applied (PSP-1)
```

Good: one rule for "can this subscription still be charged", owned in one place, that
covers the provider's rebill date, its retry window after a decline and a pending
cancel; replacing a subscription cancels the old one at the provider.

Do not report: a provider that charges only on our request (we run the rebill
ourselves) when the code that runs rebills reads the same state.

## PSP-3. Notification type not dispatched

Look for: a webhook or notification handler that turns every incoming message into a
payment, a renewal or a grant of access without branching on the type: the type is
parsed and not used, or a default branch treats unknown types as success. Also: a
handler that branches on the type but books a payment twice when the provider sends two
notifications for one charge (a renewal and an invoice, a test and a live event), with
no dedup on the provider's transaction id (IDEM-1).

Also look for: a `match`, `switch` or `if` chain over event types, actions, transaction
types or status codes whose default branch grants, charges, credits or marks paid; a
fallback such as `default => EventType::CHARGE`, `else { $purchase->markPaid() }`, a
map lookup with a default of `success`.

Failure scenario: an app store sends notifications for renewal, expiry, a refund
request, a change of the auto-renew flag. The handler creates a successful purchase for
each and extends the subscription. A user who turned off auto-renew gets another month
of access and a purchase row that the revenue report and the partner split count as
money.

```php
// bad
$type = $payload['notificationType'];
$this->purchases->recordRenewal($payload['transactionId'], $payload['price']);

// good: handle the types that move money, ignore the rest explicitly
switch ($payload['notificationType']) {
    case 'DID_RENEW':
    case 'SUBSCRIBED':
        $this->purchases->recordOnce($payload['transactionId'], $payload['price']);
        break;
    case 'REFUND':
        $this->refunds->recordOnce($payload['transactionId']);
        break;
    default:
        $this->log->info('ignored notification', ['type' => $payload['notificationType']]);
}
```

The same with a mapping over actions or statuses: the provider adds a `void` event or
sends a `rebill_decline` that the handler does not list. The `default` branch maps it to
`charge`, the order is marked paid and access is granted for money that never arrived.
Or a refund arrives with an action the code does not know and is booked as a new sale.

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

Good: an explicit list of the types that move money, every other type logged and
ignored, a unique key on the provider's transaction id for the money row.

Do not report: a default that does nothing with money (logs, ignores, stores the raw
event for later); a handler behind a provider setting that sends only one type, when the
code, its configuration, its route or its docblock shows that setting (an endpoint for
`chargeback.created` only). Report it when one URL gets several types and the handler
does not look at the type.

## PSP-4. Fix applied to one provider or path, the siblings keep the bug

Look for: a change that fixes or changes money behaviour for one provider, one product,
one plan type or one entry point (web, admin, cron, webhook) when the same logic exists
for others: an `if ($provider === 'x')` around the new behaviour, a fix in one adapter
of several, a new guard in the web purchase flow but not in the admin grant or the
smart-routing flow.

Failure scenario: a bug lets a subscription expire before the provider's next rebill.
The fix keeps the expiry after the next rebill, but only for provider A. Providers B and
C keep the old expiry; the window from PSP-2 stays open for them, and the double
subscriptions continue at a lower rate, now harder to see.

Before you report, search the repository for the siblings: the other adapters of the
same interface, the other callers of the changed function, the other places that set the
same field. Report only when a sibling has the same problem and the change does not say
why it is different.

Good: the fix lives where every provider passes (a shared service, the base adapter),
or the change says why the others are not affected.

Do not report: a provider-specific workaround for a provider-specific behaviour that the
others do not have, when the change or the code says so.

## PSP-5. Provider value read loosely

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

## PSP-6. Pending or deferred result treated as final

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

## PSP-7. Callback amount and currency not checked against the order

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

## PSP-8. Message not authenticated, or status taken from an unsigned source

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

## PSP-9. Late or out-of-order event moves a final state back

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

## PSP-10. Message acknowledged without being processed

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
  see TX-3; when it dedups by event id, see IDEM-1 and IDEM-12.
