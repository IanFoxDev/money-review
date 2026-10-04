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
