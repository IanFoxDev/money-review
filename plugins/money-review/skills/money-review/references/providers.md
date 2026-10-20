# Payment providers (PSP)

The provider is a second ledger that we do not control. It keeps its own subscription
schedule, retries declined charges on its own timetable, sends notifications for more
than payments, and may accept a request without doing what it asked. The question for
every change that talks to a provider or acts on its state: what does the provider
believe after this code runs, and does our side agree?

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

Good: an explicit list of the types that move money, every other type logged and
ignored, a unique key on the provider's transaction id for the money row.

Do not report: a handler behind a provider setting that sends only one type, when the
code or its configuration shows that setting.

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
