# Concurrency (RACE)

The question for every change: what happens if this code runs twice at the same time
for the same account, payment or order? Two HTTP requests, two queue workers, a
provider callback and a user click, a cron job and a manual retry.

## RACE-1. Check-then-act without a lock

Look for: read a row, check a condition in code, then write, with no lock and no
conditional update.

Failure scenario: two withdrawals of 80 from a balance of 100 arrive together. Both
read 100, both pass `balance >= 80`, both write. Balance is -60 and 160 left the
platform.

```php
// bad
$wallet = Wallet::find($id);
if ($wallet->balance >= $amount) {
    $wallet->balance -= $amount;
    $wallet->save();
}

// good: lock the row for the rest of the transaction
DB::transaction(function () use ($id, $amount) {
    $wallet = Wallet::whereKey($id)->lockForUpdate()->firstOrFail();
    if ($wallet->balance < $amount) {
        throw new InsufficientFunds();
    }
    $wallet->balance -= $amount;
    $wallet->save();
});

// also good: let the database check it
$updated = DB::update(
    'UPDATE wallets SET balance = balance - ? WHERE id = ? AND balance >= ?',
    [$amount, $id, $amount],
);
if ($updated === 0) {
    throw new InsufficientFunds();
}
```

Do not report: the check is repeated inside a conditional `UPDATE ... WHERE` or the
row is locked earlier in the same transaction.

## RACE-2. Lost update on a status or amount

Look for: load model, change one field, `save()` the whole model, while another path
changes the same row (status from a callback, amount from a refund).

Failure scenario: the refund handler loads the payment (status `captured`), the
callback handler marks it `refunded`, the refund handler saves its copy with
`refunded_amount` set and status `captured`. The status flips back and the refund is
retried.

Good: lock the row, or update only the changed columns with a condition on the
expected state (`WHERE status = 'captured'`), or use a version column.

## RACE-3. State transition without a guard on the current state

Look for: `$payment->status = 'succeeded'` without checking the current status in the
same statement or under a lock.

Failure scenario: a `failed` callback and a `succeeded` callback arrive within 50 ms.
Each handler sets its status. Final state depends on who wrote last; a succeeded
payment can end up failed and the user is asked to pay again.

```php
// good
$moved = Payment::whereKey($id)
    ->where('status', 'pending')
    ->update(['status' => 'succeeded']);
if ($moved === 0) {
    return; // already moved by someone else, look at the current state
}
```

## RACE-4. Lock order between two rows

Look for: a transfer that locks `from` then `to`. Another transfer between the same
accounts in the opposite direction locks `to` then `from`.

Failure scenario: A->B and B->A at the same time deadlock. The database kills one;
if the caller does not retry on deadlock, a payment fails at random under load.

Good: lock both rows in a fixed order (by id), and retry the transaction on deadlock.

## RACE-5. Unique business rule enforced only in code

Look for: "only one active subscription", "one payout per period", "one refund per
chargeback" checked with `exists()` before insert.

Failure scenario: a double click creates two subscriptions; both are billed monthly.

Good: a unique index (a partial index where the rule is conditional) and handling the
duplicate key error.

## RACE-6. Isolation level assumption

Look for: logic that reads a sum or a count and then writes based on it (limits,
quotas, pool distribution) under READ COMMITTED.

Failure scenario: daily withdrawal limit is 1000. Two requests each read "spent today:
600" and each withdraw 300. The limit is broken without any single bad request.

Good: lock a row that represents the limit (the account), or use SERIALIZABLE with a
retry on serialization failure.
