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

## MongoDB and Redis

MongoDB has no `SELECT ... FOR UPDATE`. The tools are: a conditional update (the
filter carries the condition, the update is `$inc` or `$set`), `findOneAndUpdate` for
read-and-change in one step, a version field for optimistic concurrency, unique
indexes, and multi-document transactions, where a write conflict aborts one side.

### RACE-1 with MongoDB: findOne, check in code, updateOne

Look for: `findOne` / `FindOne`, a check of a balance or a status in code, then an
update that writes a value computed in code (`$set: {balance: $old - $amount}`), or
an `$inc` without the condition in the filter.

Failure scenario: two withdrawals of 80.00 from 100.00. Both `findOne` see 100.00,
both pass the check, both write. With `$set` the balance ends at 20.00 and 160.00
was paid out; with `$inc` and no condition it ends at -60.00.

```php
// bad
$wallet = $this->wallets->findOne(['_id' => $userId]);
if ($wallet['balance'] >= $amount) {
    $this->wallets->updateOne(['_id' => $userId], ['$set' => ['balance' => $wallet['balance'] - $amount]]);
}

// good: the condition is part of the atomic update
$result = $this->wallets->updateOne(
    ['_id' => $userId, 'balance' => ['$gte' => $amount]],
    ['$inc' => ['balance' => -$amount]],
);
if ($result->getModifiedCount() === 0) {
    throw new InsufficientFunds();
}
```

Do not report: a single `updateOne` / `findOneAndUpdate` whose filter holds the whole
condition and whose update is relative (`$inc`) or sets fields that do not depend on
values read earlier. Do not ask for a lock there: the operation is already atomic.

### RACE-2 with MongoDB: whole document written back

Look for: load a document, change a field in code, then `replaceOne` or an ODM/DAO
`save()` that writes the whole document, while another path changes other fields of
the same document.

Failure scenario: the refund job loads the payment, the callback sets
`status: refunded`, the refund job saves its copy with `refunded_amount` and the old
status. The status goes back, the refund is retried.

Good: `$set` only the changed fields with the expected state in the filter, or a
`version` field: filter on the version you read, `$inc` it on write, and treat
`modifiedCount == 0` as a conflict.

### RACE-3 with MongoDB: state change without the current state in the filter

Look for: `updateOne(['_id' => $id], ['$set' => ['status' => 'paid']])` with no
`status` condition in the filter.

Good: `['_id' => $id, 'status' => 'pending']` in the filter, `modifiedCount == 0`
means someone else moved it first.

### RACE-5 with MongoDB: uniqueness only in code

Look for: `findOne` / `countDocuments` before `insertOne` to keep a rule like "one
active subscription", "one payout per period". Also a unique index with a
`partialFilterExpression` that does not match how the code writes the field.

Good: a unique index (partial if the rule is conditional) and handling of the
duplicate key error (E11000, `mongo.IsDuplicateKeyError` in Go).

## RACE-7. A Redis lock that does not hold

Look for: a lock taken with `SET key value NX` (or `setnx`) that protects a money
operation, and any of:

- no expiry (`PX` / `EX`): a crashed worker keeps the lock forever;
- expiry shorter than the work it protects: the lock expires, a second worker enters;
- release by plain `DEL` without checking the owner token: worker A deletes the lock
  that worker B now holds;
- the lock is the only guard: no condition in the database write.

Failure scenario: the payout job takes `lock:payout:42` for 10 s, the provider call
takes 15 s. A second run takes the lock at 10 s and pays out again.

Good: the lock reduces contention, the database write keeps the guarantee (a
conditional update, a unique key, a status in the filter). Release with a check of
the owner token (a Lua script or `SET` with a random value compared on release).

Do not report: a lock that only prevents duplicate work whose result is idempotent
anyway (a cache rebuild, a report).

## RACE-8. Money decision read from a secondary or a stale cache

Look for: a balance, limit or status read with `readPreference` secondary /
`secondaryPreferred`, from a Redis cache, or from a read model fed by Kafka, and then
used to allow a debit, a payout or a bonus.

Failure scenario: the user spends 90.00 of 100.00, the secondary lags by two seconds
and still shows 100.00, the withdrawal check passes and 100.00 more is reserved.

Good: decide on the primary inside the conditional write. Cached or replicated
values are for display.
