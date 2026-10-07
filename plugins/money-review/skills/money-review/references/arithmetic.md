# Money arithmetic (MONEY)

The question for every change: is every amount an exact number in a known currency,
and does every split add up to the total?

## MONEY-1. Float for amounts

Look for: `float` types, `(float)` casts, `floatval`, `round()`, JSON numbers parsed
into floats, `DOUBLE` or `FLOAT` columns for amounts.

Failure scenario: `0.1 + 0.2` is `0.30000000000000004`. A comparison
`$paid == $price` fails for a correct payment, the order stays unpaid. Summing 100 000
float amounts drifts by cents, and the period does not reconcile.

Good: integer minor units (`int` cents with the currency scale) or a decimal library
(`brick/money`, `moneyphp/money`, `bcmath`). Columns `BIGINT` minor units or
`NUMERIC(p, s)`.

Do not report: float used for a ratio or weight that is converted into an exact
amount by a split function (MONEY-4) and never stored as an amount.

## MONEY-2. Amount without a currency

Look for: an amount passed, stored or compared without its currency; adding amounts
from rows with different currencies; a hardcoded scale of 2.

Failure scenario: a JPY amount (scale 0) is divided by 100 as if it were cents; a BTC
amount (scale 8) is truncated to 2 places; USD and EUR balances are summed into one
total.

Good: amount and currency travel together (a money object), arithmetic between
different currencies throws.

## MONEY-3. Rounding without a rule

Look for: percentage fees, taxes, commissions, conversions, prorations where the code
rounds with the default mode or truncates by casting to int.

Failure scenario: a 35% commission on 9.99 is 3.4965. Rounding half up gives 3.50,
truncation gives 3.49. Over a million transactions the two rules differ by thousands,
and the partner report does not match ours.

Good: the rounding mode is explicit and the same everywhere for that calculation;
the remainder goes to an explicit account.

## MONEY-4. Split that does not add up

Look for: a total divided into parts (revenue share, pool distribution, installment
plan, refund across items) where each part is rounded on its own.

Failure scenario: a pool of 100.00 split three ways gives 33.33 x 3 = 99.99. One cent
per split is lost or created. At 10 000 partners per month the books are off every
period and nobody can say where the money went.

```php
// bad
$share = round($pool * $weight / $totalWeight, 2);

// good: allocate the whole amount, remainder goes by a fixed rule
[$a, $b, $c] = Money::of('100.00', 'USD')->allocate(1, 1, 1); // 33.34, 33.33, 33.33
```

## MONEY-5. Sign and direction

Look for: refunds, chargebacks and fees stored with an implicit sign; code that uses
`abs()`; a mix of "positive amount plus type" and "signed amount" conventions in one
calculation. An amount from a request, an event or a job argument that moves money
without a check that it is positive. A reversal (refund, chargeback, cancellation,
returned payout) that moves money in the same direction as the operation it reverses.

Failure scenario: a refund of 10 stored as `+10` with type `refund` is summed with
payments as `+10`. Revenue is overstated by twice the refund. `withdraw(-50)` passes
the balance check and credits the wallet with 50. A top-up moves money from
`psp_clearing` to the wallet; the chargeback for it moves money out of `psp_clearing`
again, so the clearing account shows 200 owed by the provider instead of 0.

Good: every function that moves money rejects an amount of zero or less, or goes
through a ledger that does; a reversal swaps the two sides of the original posting.

Do not report: a missing sign check when the amount goes straight into a ledger call
that rejects it (name the check).

## MONEY-6. Balance stored and changed in place

Look for: `balance = balance + x`, `increment('balance')`, a balance column updated
without a ledger entry in the same transaction.

Failure scenario: the balance is 120 and nobody can say why. A support ticket "my
deposit disappeared" cannot be answered, an audit cannot be passed.

Good: the balance is derived from immutable entries, or every change writes an entry
in the same transaction and a check recomputes the balance from entries.

Do not report: a cached balance that is updated together with a ledger entry in the
same transaction and verified against it.

## MONEY-7. Amount from the wrong source

Look for: a stored full amount (the payment amount, the order total) used where an
event or the provider reports its own amount; partial refunds, partial captures or an
earlier chargeback not subtracted; a cap computed from one record while the operations
it limits update another.

Failure scenario: a payment of 100.00 has 40.00 refunded. The chargeback handler books
`$payment->amount_cents`, 100.00, while the provider took back 60.00. The ledger and the
provider's settlement differ by 40.00 every time this happens.

Good: book the amount the provider reports and check it against what is left of the
payment; a cap reads the same records that the later operations change.

Do not report: an operation that the domain defines as full (a void before capture
always covers the whole authorization).

## MongoDB, Go and JSON

### MONEY-1 in stored documents and decoded JSON

Look for: amounts stored as BSON double (a PHP `float` or Go `float64` written to
MongoDB, `$inc` with a float), `$sum` in aggregations over double fields, Go
`encoding/json` decoding a provider amount into `float64` or `interface{}` (numbers
become `float64`), `strconv.ParseFloat` on amounts.

Failure scenario: `$inc: {balance: 0.1}` ten times leaves 0.9999999999999999 in the
document; the daily `$sum` of 40 000 payments differs from the provider report by
cents, and the period does not reconcile.

Good: integers in minor units (`int64`, `NumberLong`) or `Decimal128`; in Go decode
with `json.Number` or into a decimal type; PHP `bcmath` or a money library for
division and percentages.

Do not report: a float used for a rate or a weight that is converted to an integer
amount in one place with an explicit rounding rule (MONEY-3).
