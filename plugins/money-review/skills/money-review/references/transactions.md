# Transaction boundaries (TX)

The question for every change: if the process dies on any line, or the database rolls
back, which side effects already happened and which did not?

## TX-1. External call inside a database transaction

Look for: an HTTP call to a payment provider, a message to a broker, an email or a
call to another service between `BEGIN` and `COMMIT` (`DB::transaction()`,
`wrapInTransaction()`, `beginTransaction()`).

Failure scenario: the provider captures the payment, then the commit fails (deadlock,
constraint, timeout). The customer is charged, the database says the payment never
happened. Second scenario: the provider is slow, the transaction holds row locks for
30 seconds, other requests on the same account time out.

```php
// bad
DB::transaction(function () use ($order) {
    $order->markPaid();
    $this->psp->capture($order->paymentId);   // money moves, commit may still fail
});

// good: record the intent in the transaction, act after commit
DB::transaction(function () use ($order) {
    $order->markCapturePending();
    $this->outbox->record(new CaptureRequested($order->id));
});
```

Do not report: a read-only call with a short timeout whose result is checked again
later (for example a currency rate lookup). Still mention it if the transaction holds
locks on accounts while it waits.

## TX-2. Side effect after commit with no record

Look for: an event published or a job dispatched after commit with no row that says
it must happen (no outbox, no status column).

Failure scenario: the commit succeeds, the process is killed before `publish()`.
The order is paid, the fulfilment service never hears about it, nobody retries.

```php
// bad
DB::transaction(fn () => $payment->markSucceeded());
$this->bus->publish(new PaymentSucceeded($payment->id));

// good
DB::transaction(function () use ($payment) {
    $payment->markSucceeded();
    $this->outbox->record(new PaymentSucceeded($payment->id));
});
```

Do not report: a job dispatched inside the transaction to a queue stored in the same
database (Laravel `database` driver without `afterCommit`): the job row commits or
rolls back together with the change.

## TX-3. Money change split across transactions

Look for: debit and credit, or balance change and ledger entry, written in two
separate transactions or two separate `save()` calls without a surrounding
transaction.

Failure scenario: the debit commits, the credit fails. Money disappears from one
account and never appears in the other. The daily reconciliation finds it a week later.

```php
// bad
$from->decrement('balance', $amount);
$to->increment('balance', $amount);

// good
DB::transaction(function () use ($from, $to, $amount) {
    $this->ledger->transfer($from, $to, $amount);
});
```

## TX-4. Swallowed exception inside a transaction

Look for: `try/catch` inside the transaction callback that logs and continues, so the
transaction commits a partial change.

Failure scenario: the ledger insert fails on a constraint, the catch logs a warning,
the status update still commits. The payment is marked settled without a ledger entry.

Do not report: a catch that rethrows or that marks the whole operation as failed in
the same transaction.

## TX-5. Nested transaction assumptions

Look for: a service that opens its own transaction and is called from inside another
transaction; code that relies on the inner commit being durable.

Failure scenario: the inner `commit()` only releases a savepoint. The outer
transaction rolls back later, the inner "committed" credit is gone, but an email
"your payout is on the way" was already sent based on it.

## TX-6. Long transaction around a loop

Look for: one transaction over a loop that processes many accounts, payouts or
invoices.

Failure scenario: a batch of 10 000 payouts holds locks for minutes; user requests on
those accounts time out; one bad row rolls back the whole batch and it is re-run with
the first rows already sent to the bank.

Good: one transaction per unit of work, a status per unit, the batch is resumable.

## MongoDB and message brokers

MongoDB updates one document atomically. Anything that spans two documents or two
collections is atomic only inside a multi-document transaction (a session with
`startTransaction` / `withTransaction`, replica set required). A broker (Kafka,
Redpanda, RabbitMQ) never takes part in that transaction.

### TX-2 with a broker: write to MongoDB, then produce

Look for: `updateOne` / `insertOne` followed by `produce`, `WriteMessages`,
`basic_publish`, with no outbox document written in the same transaction or the same
document.

Failure scenario: the payment document is marked paid, the process dies before
`produce`. The event that credits the partner or fires fulfilment is never sent.
Produce first instead, and a crash before the write sends an event for a payment
that does not exist.

```php
// bad
$this->payments->updateOne(['_id' => $id, 'status' => 'pending'], ['$set' => ['status' => 'paid']]);
$this->producer->produce(RD_KAFKA_PARTITION_UA, 0, json_encode(['type' => 'payment.paid', 'id' => $id]));

// good: the event is part of the same atomic write, a relay publishes it later
$this->payments->updateOne(
    ['_id' => $id, 'status' => 'pending'],
    ['$set' => ['status' => 'paid'], '$push' => ['outbox' => ['type' => 'payment.paid', 'published' => false]]],
);
```

Do not report: the event is only a cache refresh or a notification that is also
derived from the database by a periodic job.

### TX-3 with MongoDB: two documents changed without a transaction

Look for: debit on one document and credit on another (two wallets, wallet and
ledger, order and payment) as two separate `updateOne` calls, or `bulkWrite` treated
as atomic (it is not: ordered bulk stops at the first error, earlier writes stay).

Failure scenario: the debit of wallet A succeeds, the credit of wallet B fails on a
network error. 50.00 leaves A and arrives nowhere.

```go
// bad
_, err := wallets.UpdateOne(ctx, bson.M{"_id": from}, bson.M{"$inc": bson.M{"balance": -amount}})
_, err = wallets.UpdateOne(ctx, bson.M{"_id": to}, bson.M{"$inc": bson.M{"balance": amount}})

// good
_, err := session.WithTransaction(ctx, func(sc mongo.SessionContext) (any, error) {
    res, err := wallets.UpdateOne(sc, bson.M{"_id": from, "balance": bson.M{"$gte": amount}},
        bson.M{"$inc": bson.M{"balance": -amount}})
    if err != nil {
        return nil, err
    }
    if res.ModifiedCount == 0 {
        return nil, ErrInsufficientFunds // aborts the transaction
    }
    return wallets.UpdateOne(sc, bson.M{"_id": to}, bson.M{"$inc": bson.M{"balance": amount}})
})
```

Do not report: both changes live in one document (an embedded ledger array, a
balance and its history in the same document): a single-document update is atomic.

## TX-7. Operation inside a transaction without the session

Look for: inside `startTransaction` ... `commitTransaction` or a `withTransaction`
callback, a call that does not pass the session (`['session' => $session]` in PHP,
the `SessionContext` as ctx in Go). A repository or DAO method called from the
callback that uses its own collection handle is the usual case.

Failure scenario: the ledger insert runs outside the transaction and commits
immediately. The wallet update in the transaction then aborts on a write conflict.
The ledger shows a debit of 30.00 that never happened, reconciliation breaks.

```php
// bad
$session->startTransaction();
$this->wallets->updateOne($filter, $update, ['session' => $session]);
$this->ledger->insertOne($entry);              // no session: not part of the transaction
$session->commitTransaction();

// good
$this->ledger->insertOne($entry, ['session' => $session]);
```

Do not report: a read that only feeds a log line or a metric.

## TX-8. Side effect inside a retried transaction callback

Look for: an HTTP call, `produce`, an email or a cache write inside a
`withTransaction` callback. Drivers retry the whole callback on
`TransientTransactionError` and `UnknownTransactionCommitResult`.

Failure scenario: the callback debits the wallet and calls the provider's payout. The
commit hits a transient error, the driver runs the callback again. The provider is
called twice; with no idempotency key the user is paid twice.

Good: keep the callback to database writes only. Record the intent in the
transaction (an outbox or a status), act after it returns.
