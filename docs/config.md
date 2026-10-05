# Configuration

money-review reads `.money-review.json` from the root of the repository it reviews.
The file is optional. It is merged over the plugin defaults
(`plugins/money-review/defaults/config.json`) with jq's `*`: objects merge key by key,
strings and arrays replace the default.

Pass another file with `--config FILE` (both the skill and the shell command accept it).

## Fields

### `paths.include`, `paths.exclude`

Globs for files that triage looks at. `*` matches any characters, including `/`.

Defaults: include `*.php` and `*.go`; exclude test directories (`tests/`, `test/`),
`vendor/`, `*_test.go`, `testdata/`, `mocks/`, generated Go files (`*.pb.go`,
`*_gen.go`, `*_mock.go`), Blade templates, `lang/` and `resources/`.

For a repository with only Go code:

```json
{
  "paths": {
    "include": ["*.go"],
    "exclude": ["*_test.go", "vendor/*", "*/mocks/*", "*.pb.go"]
  }
}
```

### `money_paths`

Globs for files that are always money code, whatever words they contain. A file here
gets every checklist. Use it for the billing module, the ledger, provider adapters.

```json
{ "money_paths": ["app/Billing/*", "src/Ledger/*", "app/Psp/*"] }
```

### `signals`

An extended regular expression. A file that is not in `money_paths` is reviewed only
if its changed lines (with the hunk's context lines) match it, in any letter case, so
`amount` also finds Go's `Amount`. The default lists words like `amount`, `balance`,
`payout`, `refund`, `wallet`, `ledger`, `invoice`, `fee`, `currency`, `bonus`. Add your domain words, for example `credits|tokens|coins`, by writing the
whole expression: a string replaces the default.

### `categories`

An object from checklist prefix to an extended regular expression: `TX`, `RACE`,
`IDEM`, `MONEY`. A checklist is loaded when a file in scope matches its expression.
The defaults cover Laravel (`DB::transaction`, `lockForUpdate`, `ShouldQueue`), the
MongoDB drivers for PHP and Go (`updateOne`, `findOneAndUpdate`, `$inc`, sessions and
`withTransaction`), Kafka and RabbitMQ clients (`produce`, `WriteMessages`,
`CommitMessages`, `basic_publish`, `basic_ack`), Redis locks (`SET NX`) and Go floats.
These patterns are case-sensitive, because they name API calls. Override one category
without touching the others:

```json
{
  "categories": {
    "TX": "->save\\(|->persist\\(|->flush\\(|wrapInTransaction|beginTransaction|->commit\\(|HttpClient|->request\\(|dispatch|->publish\\("
  }
}
```

### `review`

How a large change is split. A change whose money files have more than
`group_lines` changed lines is reviewed in groups of files, each by its own reviewer
pass; one verifier pass then checks all candidates. Files go in path order, so the
files of one module stay together.

```json
{ "review": { "group_lines": 800, "max_groups": 6 } }
```

When there are more groups than `max_groups`, the groups that match the most
checklists are reviewed and the rest are listed in the report as not reviewed. Each
extra group adds about one reviewer pass to the time and the subscription use.

### `context`

Free text passed to the reviewer as is. This is the cheapest way to cut false alarms.
Say where the things live that a reviewer would otherwise have to guess:

```json
{
  "context": "Amounts are integer cents with a currency. Balances change only through App\\Ledger\\Ledger::transfer, which locks both accounts in id order. Provider calls go through App\\Psp\\Gateway and take an idempotency key. Incoming provider events are deduplicated by the DeduplicateEvent job middleware with a unique index on processed_events."
}
```

### `ignore`

Findings the team has looked at and accepted. Each entry names a rule (`RACE-1`) or a
whole checklist (`RACE`), an optional `path` glob (default: every file) and a reason.
The reason is required: an entry without one is not applied, and the run says so.

```json
{
  "ignore": [
    {"rule": "MONEY-2", "path": "src/Reports/*", "reason": "reports show amounts in one currency, never sum them"},
    {"rule": "RACE-7", "reason": "the Redis lock is a throttle, the balance is guarded by $inc with a condition"}
  ]
}
```

For one place in the code, put a comment on the line of the finding or the line above
it. It works in any comment style, and takes one rule, a list or a checklist:

```php
// money-review: ignore RACE-1 the caller holds lockForUpdate on the wallet
$wallet->balance -= $amount;

$total = $a + $b; # money-review: ignore MONEY-1,MONEY-4 display only, see BILL-412
```

Suppression is applied by `scripts/suppress.sh` after the verifier, without a model,
so it does not change what the review costs. Suppressed findings do not count for
`--fail-on`, are not posted as merge request comments, and are listed in a folded
section of the report with their reason, so an ignore that hides a real bug can still
be found.

## Checking what triage does

Triage is a plain script, so you can see its decision without starting Claude:

```sh
git diff master | ~/.claude/plugins/marketplaces/money-review/plugins/money-review/scripts/triage.sh | jq
```

It prints whether the change touches money, the files in scope, the checklists it
picked, and for each file and checklist the first text that matched. Add
`--config .money-review.json` to try a config change before you commit it.
