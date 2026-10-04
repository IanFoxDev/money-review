# Idempotency (IDEM)

Every message, callback and job will be delivered more than once. Providers retry
callbacks, brokers redeliver after a rebalance, users double click, cron overlaps,
engineers re-run a failed batch. The question for every change: what happens on the
second delivery of the same thing?

## IDEM-1. Callback or consumer without a dedup key

Look for: a webhook handler, a queue consumer or a job that changes money (credit,
debit, status that triggers fulfilment) and does not record the incoming event id.

Failure scenario: the provider sends `payment.succeeded`, our response takes 11
seconds, the provider times out at 10 and retries. Both deliveries credit the wallet.

```php
// bad
public function handle(Callback $cb): void
{
    $this->wallet->credit($cb->userId, $cb->amount);
}

// good: unique (source, event_id) in the same transaction as the credit
public function handle(Callback $cb): void
{
    DB::transaction(function () use ($cb) {
        $inserted = DB::table('processed_events')->insertOrIgnore([
            'source' => 'psp', 'event_id' => $cb->eventId,
        ]);
        if ($inserted === 0) {
            return; // already processed
        }
        $this->wallet->credit($cb->userId, $cb->amount);
    });
}
```

Do not report: the handler only moves a state machine forward with a guard on the
current state (RACE-3) and the move itself has no other side effects.

## IDEM-2. Dedup check outside the transaction

Look for: `if (processed($id)) return;` ... work ... `markProcessed($id)`, as three
separate steps.

Failure scenario: two deliveries arrive together, both see "not processed", both
credit. Or the process dies after the credit and before `markProcessed`: the retry
credits again.

Good: the dedup row and the money change commit in one transaction, the dedup row is
protected by a unique index (IDEM-1 example).

## IDEM-3. Outgoing request without an idempotency key

Look for: a call that creates a payment, refund or payout at a provider without an
idempotency key, or with a key that changes on retry (random UUID generated inside
the retry loop, timestamp).

Failure scenario: the refund request times out on our side, the provider processed
it. Our retry sends a new refund. The customer gets money back twice.

```php
// bad
retry(3, fn () => $this->psp->refund($paymentId, $amount, key: Str::uuid()));

// good: the key is derived from our record and stored before the first attempt
$refund = Refund::firstOrCreate(['payment_id' => $paymentId, 'reason' => $reason], [...]);
retry(3, fn () => $this->psp->refund($paymentId, $amount, key: "refund-{$refund->id}"));
```

## IDEM-4. Timeout treated as failure

Look for: a timeout or 5xx from the provider handled as "payment failed" (status set
to failed, user asked to pay again, funds released).

Failure scenario: the provider charged the card, we timed out and marked the payment
failed. The user pays again and is charged twice. Or a payout is marked failed and
re-sent next day.

Good: timeout = unknown. Keep the payment pending and resolve it by polling the
provider status or waiting for the callback.

## IDEM-5. Job or batch that is not safe to re-run

Look for: a scheduled job (payouts, invoices, revenue share, interest, bonus
accrual) with no period key and no record of what is already done.

Failure scenario: the monthly payout job fails at row 7000 of 10000. Someone re-runs
it. Rows 1 to 7000 are paid twice.

Good: a unique key per unit and period (`payout:{partner}:{2026-09}`), status per
unit, re-run skips done units.

## IDEM-6. Retry wrapper around a non-idempotent block

Look for: `retry()`, a loop with `catch` and `continue`, or a queue `tries` setting
around code that already changed money before the failure point.

Failure scenario: credit succeeded, the following notification call threw, the job
is retried, the credit runs again.

Good: retry only the idempotent part, or make the whole unit idempotent first.
