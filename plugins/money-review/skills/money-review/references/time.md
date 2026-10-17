# Periods, dates and time zones (TIME)

The question for every change: does every period, window and deadline that decides money
start and end where the business and the provider say it does, in every month, every
time zone and every year?

Money is counted per period: billing cycles, daily revenue, monthly payouts, refund
windows, trial ends, retry schedules. A period computed one day or a few hours off moves
money between periods, drops it, or counts it twice, and nothing fails loudly.

## TIME-1. Calendar arithmetic that does not hold in every month or year

Look for: `+1 month` / `modify('+1 month')` / `AddDate(0, 1, 0)` from a day after the
28th; a month or year expressed as a number of days (30, 365) or the reverse; a cycle
guessed from a day count (`days == 365 ? '1 year' : '1 month'`); a date parsed with
`createFromFormat` without `!` and without checking that it round-trips (PHP turns
2026-02-31 into March 3); Go `time.Date` with an overflowing day, which normalises
silently.

Failure scenario: a subscription started on January 31. `+1 month` gives March 3 in
PHP, so the February charge is skipped and the anchor drifts to the 3rd for the rest of
the customer's life. A yearly plan of `365 DAY` renews a day early in every leap year,
while our records say "1 year", and the provider's charge no longer matches our period.

Good: keep the original anchor day and clamp to the last day of short months (the way
the provider does); use the provider's unit (`MONTH` vs `DAY`) for the provider's cycles;
reject impossible dates.

Do not report: a period that the product defines as a number of days (a 30-day pass).

## TIME-2. Boundary in the wrong time zone

Look for: day, month or report windows computed in the server's default zone while the
business or the provider counts in another; dates formatted with `format('Y-m-d H:i:s')`
and passed to another system (a provider's database, an API, a SQL query against a
`DATETIME` or `TIMESTAMP WITHOUT TIME ZONE` column) without converting to that system's
zone; `whereDate` or `DATE()` on a timestamp in a different zone; cron schedules in local
time across DST.

Failure scenario: the provider's reporting database stores times in US Eastern. The sync
asks for `created_at >= '2026-10-01 00:00:00'` formatted in UTC; every run misses the last
four or five hours of the provider's day and those payments are never imported. On the
DST change a daily job runs twice, or not at all, and one day is billed twice.

Good: each boundary is computed in a named zone and converted explicitly when it crosses
a system; storage is in UTC or in a type that carries the zone; jobs are keyed by the
business date they cover, not by the time they ran.

Do not report: a boundary inside one system where all values are in one zone by
construction.

## TIME-3. Period edges that overlap or leave a gap

Look for: windows closed on both ends (`BETWEEN from AND to`, `whereBetween` with
`to = from + 1 day`, `<= end` together with `>= start` of the next period); a date-only
value from a provider (`2026-10-31`) parsed as midnight at the start of the day when it
means the end; end-of-day written as `23:59:59` (drops the last second, and
sub-second times).

Failure scenario: daily revenue is summed with `created_at BETWEEN '2026-10-01 00:00:00'
AND '2026-10-02 00:00:00'`. A payment at exactly midnight is counted in both days; the
monthly total is higher than the provider's. A provider says the subscription is paid
"until 2026-10-31"; parsed as 00:00 on the 31st, access ends a day early.

Good: half-open intervals `[start, end)` everywhere; date-only values converted with the
meaning the source documents.

## TIME-4. "Now" where the event's own time belongs

Look for: a selection window relative to the current time in a job (`expiry > now - 7
days`, "yesterday" computed at run time) so a missed or late run never covers the days
it skipped; an exchange rate, price or tax rate taken at processing time for an event
that happened earlier; an extension from `now` (see SUB-4); signed differences used as
durations (`$now->diffInSeconds($past)` is negative in Carbon 3, operands in the wrong
order).

Failure scenario: the daily expiry job selects subscriptions that expired in the last 7
days. The job is down for 9 days during a migration; subscriptions that expired on days
8 and 9 are never processed and keep their access, or are never charged again. A
backfill of last month's purchases converts amounts at today's rate, and last month's
revenue changes every time the backfill runs.

Good: jobs keep a cursor of the last business date or id they completed and catch up
from it; amounts are converted with the rate of the event's time and the rate is stored.

## TIME-5. Off-by-one at a limit

Look for: `>` against `>=` (or `<` against `<=`) on due dates, trial ends, refund windows,
thresholds and counters ("the third attempt", "after 14 days"); a limit checked against
a count that already includes the current item, or does not.

Failure scenario: the refund window is "within 14 days". The code checks
`days_since_purchase < 14`, refusing refunds on day 14 that the terms allow; the customer
files a chargeback instead and we pay a fee on top of the refund. A trial limit of "one
per customer" compares `count > 1` and allows a second trial.

Good: the limit is written the way the terms state it, with a test at the exact edge.

## Go, SQL and MongoDB notes

- Go: `time.Time` compared with `==` compares the location too; use `Equal`. Truncating
  to a day with `Truncate(24 * time.Hour)` works in UTC only.
- PostgreSQL: comparing `timestamp without time zone` with a `timestamptz` value converts
  with the session `TimeZone`; a non-UTC session shifts every window.
- MongoDB stores dates in UTC; a `$dateTrunc` or `$dayOfMonth` without `timezone` groups
  by UTC days.
- ClickHouse `DateTime` without a zone uses the server zone; `toDate()` on it groups by
  that zone.
