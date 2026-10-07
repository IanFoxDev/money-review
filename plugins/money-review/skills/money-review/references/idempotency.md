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

## Message brokers, MongoDB and Redis

Kafka, Redpanda and RabbitMQ deliver at least once. A consumer that changes money
must survive the same message twice: after a crash between the work and the offset
commit or ack, after a rebalance, after a requeue.

### IDEM-1 with a broker: consumer without a dedup key

Look for: a Kafka or RabbitMQ handler that credits, debits or changes a payment
status and does not record the event id (or another stable key from the message)
together with the change.

Good with MongoDB: the event id goes into the same document update, or into a
`processed_events` collection with a unique index, inside the same transaction as
the money change.

```go
// good: the dedup key and the credit are one atomic update
res, err := wallets.UpdateOne(ctx,
    bson.M{"_id": userID, "applied_events": bson.M{"$ne": eventID}},
    bson.M{"$inc": bson.M{"balance": amount}, "$push": bson.M{"applied_events": eventID}},
)
if err == nil && res.ModifiedCount == 0 {
    return nil // already applied
}
```

Do not report: the handler only moves a state forward with the current state in the
update filter (RACE-3) and has no other side effects.

### IDEM-2 with MongoDB or Redis: dedup outside the money write

Look for: a dedup check against Redis (`SET event:{id} NX`) or a separate collection,
done before the money update and not in the same transaction; a Redis dedup key with
a TTL shorter than the broker's redelivery window.

Failure scenario: the consumer sets `event:77` in Redis, credits the wallet in
MongoDB, crashes before the ack. The redelivery sees the key and skips: fine. But if
it crashed after setting the key and before the credit, the redelivery skips and the
credit is lost. With a 1 h TTL, a message redelivered after a day-long outage is
applied twice.

Good: the dedup record lives in the same database write as the money change.

## IDEM-7. Offset commit or ack in the wrong place

Look for:

- the Kafka offset committed (`CommitMessages`, `commitSync`, `commit`) or the
  RabbitMQ message acked (`basic_ack`, `Ack`) **before** the money change is applied;
- `enable.auto.commit=true` (or a library default that auto-commits) on a consumer
  that changes money;
- a failure path that acks or commits anyway (`catch` that logs and acks), or that
  nacks with requeue forever without a dead-letter queue.

Failure scenario: the consumer commits the offset of `payment.succeeded`, then the pod
is killed before the wallet is credited. The message is never delivered again; the
user paid and got nothing. The reverse order without dedup (IDEM-1) credits twice.

```go
// bad
msg, _ := reader.FetchMessage(ctx)
reader.CommitMessages(ctx, msg)
applyPayment(ctx, msg.Value)

// good: apply idempotently, then commit
msg, err := reader.FetchMessage(ctx)
if err != nil {
    return err
}
if err := applyPaymentOnce(ctx, msg); err != nil { // dedup by event id inside
    return err // no commit: the message comes back
}
return reader.CommitMessages(ctx, msg)
```

Do not report: a consumer whose work is a pure cache or metrics update.

## IDEM-8. Events of one account processed out of order

Look for: money events of one account or payment produced with a partition key that
is not the account or payment id (random, empty, event id), or consumed by several
workers in parallel without per-key ordering; a consumer that applies `refunded`
without checking that `paid` was applied.

Failure scenario: `payment.refunded` reaches the consumer before `payment.paid`
because they went to different partitions. The refund is applied to a pending
payment and ignored or rejected; `paid` then credits the wallet, and the refund is
lost.

Good: key money events by account or payment id, and keep a state guard in the
consumer (RACE-3), so an early event is parked or retried, not dropped.

## IDEM-9. Duplicate key caught inside a MongoDB transaction

Look for: inside `startTransaction` / `withTransaction`, an insert of an idempotency
key (a processed event, a ledger entry with the key as `_id`) wrapped in a catch for
the duplicate key error (E11000, `isDuplicateKey`, `mongo.IsDuplicateKeyError`) that
returns as if the work were already done.

Failure scenario: the provider retries `payment.succeeded`. The insert of
`psp:evt1` fails with E11000 and the server aborts the transaction. The catch returns
normally, the commit then fails, and the driver runs the callback again with the same
result until its 120 s limit. The retry never becomes a no-op: the webhook times out
and the provider keeps retrying; in a consumer, the partition stalls.

```php
// bad
try {
    $this->processed->insertOne(['_id' => $eventId], ['session' => $session]);
} catch (BulkWriteException $e) {
    return; // the transaction is already aborted here
}

// good: check with a read in the session, let a real conflict fail and retry
if ($this->processed->findOne(['_id' => $eventId], ['session' => $session]) !== null) {
    return;
}
$this->processed->insertOne(['_id' => $eventId], ['session' => $session]);
```

Do not report: the same pattern outside a transaction, where a duplicate key error
affects only that one write.

## IDEM-10. Provider or business outcome not handled

Look for: a call to a provider or to the ledger that can end in a decline, insufficient
funds or another expected business error, where the code handles success and maybe a
timeout but not that; an expected business error thrown out of a webhook or consumer,
so the transaction rolls back and the sender retries forever.

Failure scenario: a payout retry catches `GatewayTimeout` only. The provider declines,
`GatewayDeclined` escapes, the payout stays `pending` and its 500.00 stay in
`payouts_in_flight` with nothing to release them. A chargeback handler debits the
user's wallet; the user has already spent the money, the ledger throws
`InsufficientFunds`, the handler returns 500, the provider retries every hour and the
chargeback is never booked, although the provider has taken the money.

Good: every outcome has a path. Success: mark it done. Decline: mark it failed and
release the funds. Timeout: keep it pending and resolve it later (IDEM-4). Money that
has already left (a chargeback, a fee the provider took): book it to an account that may
go negative and alert, do not refuse it.
