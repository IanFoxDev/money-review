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

### `context`

Free text passed to the reviewer as is. This is the cheapest way to cut false alarms.
Say where the things live that a reviewer would otherwise have to guess:

```json
{
  "context": "Amounts are integer cents with a currency. Balances change only through App\\Ledger\\Ledger::transfer, which locks both accounts in id order. Provider calls go through App\\Psp\\Gateway and take an idempotency key. Incoming provider events are deduplicated by the DeduplicateEvent job middleware with a unique index on processed_events."
}
```

## Checking what triage does

Triage is a plain script, so you can see its decision without starting Claude:

```sh
git diff master | ~/.claude/plugins/marketplaces/money-review/plugins/money-review/scripts/triage.sh | jq
```

It prints whether the change touches money, the files in scope, the checklists it
picked, and for each file and checklist the first text that matched. Add
`--config .money-review.json` to try a config change before you commit it.
