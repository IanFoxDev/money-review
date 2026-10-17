# Data completeness and aggregates (DATA)

The question for every change: does every money row that exists end up counted exactly
once in the totals that pay, bill or reconcile, also after a failure, a re-run or a
late arrival?

Payouts, revenue shares, invoices from usage, commissions and reconciliation are built
from data pipelines: syncs with a provider, consumers, backfills, daily and monthly
aggregates. A row that is skipped, read twice or kept stale does not raise an error. It
moves money quietly, and the books are wrong by the time anyone looks.

## DATA-1. A cursor or watermark that skips or stalls

Look for: a sync or poller that saves its position only when the window returned rows,
or that stops on one bad row without saving progress; a high-water mark on an id, a
sequence or `created_at` (`WHERE id > :last`), where rows committed later can have a
lower value; a timestamp cursor with `>` and ties on the same second; the next run
starting from "yesterday" or "now minus N" instead of the saved position.

Failure scenario: an export reads `WHERE id > last_id ORDER BY id`. Transaction A takes
id 101 and commits after transaction B, which took 102. The poller sees 102, moves the
mark to 102, and row 101 is never exported: the partner is not paid for it. A provider
sync saves its cursor only `if ($rowsSeen > 0)`; one empty window during an outage
freezes it, and every later run asks for the same day.

Good: the position is the last item fully processed and is saved with it; for ids or
times assigned before commit, read up to a safe lag (or use the database's commit order:
`pg_snapshot_xmin`) and reconcile counts; a run catches up from the saved position, not
from the clock.

Do not report: a cursor over an append-only source that assigns ordered ids at commit
(a Kafka offset, a provider's own event sequence with no gaps).

## DATA-2. A read that stops before the end

Look for: one page of an API, a Redis `SCAN` without the loop over the cursor, a query
with `LIMIT` and no loop, `OFFSET` pagination over rows that change while the job runs,
`chunk()` over rows the loop itself updates (Laravel skips every second page), a
provider list endpoint read without `has_more` / `next`.

Failure scenario: the invoice sync reads `GET /invoices/{id}/lines` once; the provider
returns the first 10 lines and `has_more: true`. Invoices with more than 10 lines are
stored short, and the revenue report misses the rest. A job marks pending payouts as
processed in `chunk(100)`; every update shifts the next page, so half the payouts are
never processed.

Good: loop until the source says there is no more; keyset pagination on `(time, id)`
with an upper bound fixed at the start; `chunkById` / `lazyById` when the loop changes
the rows.

## DATA-3. Rows silently dropped from a money total

Look for: an `INNER JOIN` to a lookup table (rates, plans, currencies, users) that drops
rows without a match; `WHERE status IN (...)` or `type IN (...)` lists in money queries
that a new status or operation type does not join; `COALESCE(amount, 0)` or `?? 0` that
hides missing data; rows with zero, negative or missing weight skipped instead of booked
to an explicit "unattributed" bucket; raw queries on soft-deleted tables that forget
`deleted_at`, or soft deletes that hide money rows that still count.

Failure scenario: partner commission sums `wallet_entries` where `type IN ('bet',
'win')`. A new `jackpot_win` type is added; jackpots are not netted against losses and
partners are overpaid. A daily revenue query joins `exchange_rates` on the day; on a day
the rate import failed, every non-USD payment disappears from the total, and nothing
fails.

Good: totals are computed so that every input row lands in some bucket, including
"unknown"; a control count or sum compares input and output; new enum values fail a test
until every money query decides what to do with them.

Do not report: a filter that the business defines (test accounts excluded), stated in the
query or next to it.

## DATA-4. A re-run or backfill that counts twice or leaves stale rows

Look for: a backfill or recompute that inserts again instead of replacing the period it
covers; a recompute that writes fewer rows than before without deleting the old ones; a
resume point (`max(original_id)`, "last processed date") that the live writer also
moves, so a restarted backfill skips history; a backfill window that overlaps the live
consumer with no shared idempotency key; a default end of `now` that overlaps the live
writer.

Failure scenario: a monthly revenue job is re-run after a fix. It inserts the month's
rows again; the payout job sums both copies and pays partners twice. A backfill resumes
from `max(original_id)` in the target table, but the live consumer has already written
rows for recent purchases with high ids; the restarted backfill starts after them and
older purchases are never loaded.

Good: each run owns a period or a key range and replaces it atomically (delete and
insert in one transaction, or a partition swap, or upserts keyed by the source id); a
backfill keeps its own position.

See also IDEM-5 for jobs that are not safe to re-run in general.

## DATA-5. Deduplicating storage read as if it were already deduplicated

Look for: money sums over a ClickHouse `ReplacingMergeTree`, `CollapsingMergeTree` or
`VersionedCollapsingMergeTree` without `FINAL`, `argMax(..., version)` or a dedup
subquery; synthetic or fallback rows whose sorting key differs from the real rows they
should replace; `PARTITION BY` a column that changes over the row's life (replacements
across partitions never merge); Elasticsearch or a cache used as the source of a money
total.

Failure scenario: purchases land in a `ReplacingMergeTree` ordered by `(purchase_id)`.
Refunds re-project the purchase with a new version. Until a background merge runs, both
versions exist and `sum(amount)` counts the purchase twice; the daily payout run happens
before the merge.

Good: read with `FINAL` or `argMax` by version, or aggregate into a table whose engine
gives the right sum on insert; keys of replacement rows equal the keys of the rows they
replace; partitions on immutable columns.

## DATA-6. A write acknowledged before it is stored

Look for: ClickHouse `async_insert=1` with `wait_for_async_insert=0` (or the client's
async insert without wait) followed by a Kafka offset commit or a "done" mark; buffered
writers whose flush errors are only logged; a batch insert whose error on one item is
ignored while the batch is marked complete.

Failure scenario: the purchase consumer inserts each event with async insert without
waiting and commits the offset. The ClickHouse buffer flush fails (a type error, a
restart); the offset is already committed and the purchase is gone from the payout data
for good.

Good: wait for the insert (or use synchronous inserts) before acknowledging; treat a flush
error as a reason not to commit (see IDEM-7).

## DATA-7. A period closed with missing inputs

Look for: a daily or monthly aggregate that runs on whatever input rows exist with no
check that the inputs are complete (all days present, the upstream job finished, the
provider import succeeded); a missing value read as zero (no commission row means 0
commission); a job that exits 0 or marks the period complete after errors on some rows;
a period that is frozen and never reopened when late data arrives.

Failure scenario: the monthly payout rolls up daily income rows. The daily job did not
run on the 14th; the month is frozen with 29 of 30 days and partners are underpaid by a
day, and since the month is closed nobody recomputes it. A missing commission row for the
previous month is read as 0, and the new month is paid out without the deduction.

Good: an explicit completeness check (expected days, upstream status, row counts against
the source) before a period is closed; missing inputs are an error, not a zero; late data
reopens or adjusts the period through a visible correction.

## Go, SQL and brokers

- Go: `rows.Err()` after the loop must be checked, or a broken stream ends the loop
  early and looks like the end of the data.
- MongoDB: `$lookup` drops nothing, but an `$unwind` without `preserveNullAndEmptyArrays`
  drops documents with no match, like an inner join.
- Kafka: a consumer that skips a message after N failed attempts must record it
  somewhere (a dead-letter topic), or the total misses it.
