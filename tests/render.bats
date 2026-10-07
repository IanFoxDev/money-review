#!/usr/bin/env bats

setup() {
    render="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/render.sh"
    reports="$BATS_TEST_DIRNAME/fixtures/reports"
}

@test "an empty report says so" {
    run "$render" "$reports/empty.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No money bugs found in this change."* ]]
    [[ "$output" != *"<details>"* ]]
}

@test "counts findings by severity" {
    run "$render" "$reports/mixed.json"
    [[ "$output" == *"2 finding(s): 1 high, 0 medium, 1 low."* ]]
}

@test "high findings come first" {
    run "$render" "$reports/mixed.json"
    high="${output%%### 2. LOW*}"
    [ "$high" != "$output" ]
    [[ "$high" == *"### 1. HIGH RACE-1: Balance check and debit are not atomic"* ]]
}

@test "a finding shows location, scenario and fix" {
    run "$render" "$reports/mixed.json"
    [[ "$output" == *'`app/WithdrawalService.php:7`'* ]]
    [[ "$output" == *"**What happens:** Two withdrawals of 80"* ]]
    [[ "$output" == *"**How to fix:** lockForUpdate()"* ]]
}

@test "rejected candidates are folded" {
    run "$render" "$reports/mixed.json"
    [[ "$output" == *"1 candidate(s) dropped by the verifier"* ]]
    [[ "$output" == *'- IDEM-1 `app/Jobs/ApplyRefund.php:19`: Deduplicated by middleware.'* ]]
}

@test "the report can come from stdin" {
    run bash -c "'$render' < '$reports/empty.json'"
    [[ "$output" == *"No money bugs"* ]]
}

@test "coverage says how much was reviewed and what was not" {
    echo '{"findings":[],"rejected":[],"coverage":{"files_changed":77,"files_with_money":43,"files_reviewed":35,"groups":6,"not_reviewed":["app/X.php"]}}' > "$BATS_TEST_TMPDIR/r.json"
    run "$render" "$BATS_TEST_TMPDIR/r.json"
    [[ "$output" == *"43 of 77 changed file(s) touch money; 35 reviewed in 6 groups of files."* ]]
    [[ "$output" == *'**Not reviewed**'*'`app/X.php`'* ]]
}

@test "a fully reviewed small change says so" {
    echo '{"findings":[],"rejected":[],"coverage":{"files_changed":2,"files_with_money":1,"files_reviewed":1,"groups":1,"not_reviewed":[]}}' > "$BATS_TEST_TMPDIR/r.json"
    run "$render" "$BATS_TEST_TMPDIR/r.json"
    [[ "$output" == *"1 of 2 changed file(s) touch money; all of them reviewed."* ]]
    [[ "$output" != *"Not reviewed"* ]]
}

@test "files left out as secrets are named" {
    jq '. + {coverage: {files_changed: 2, files_with_money: 1, files_reviewed: 1, groups: 1, not_reviewed: [], secrets_excluded: [".env"]}}' "$reports/mixed.json" > "$BATS_TEST_TMPDIR/r.json"
    run "$render" "$BATS_TEST_TMPDIR/r.json"
    [[ "$output" == *'**Left out as possible secrets** (not sent to the model; see `secrets` in the config): `.env`'* ]]
}

@test "several findings get a table on top" {
    run "$render" "$reports/mixed.json"
    [[ "$output" == *"| # | Severity | Rule | Where | Problem |"* ]]
    [[ "$output" == *'| 1 | high | RACE-1 | `app/WithdrawalService.php:7` | Balance check and debit are not atomic |'* ]]
}

@test "one finding has no table" {
    run bash -c "jq '.findings |= .[:1]' '$reports/mixed.json' | '$render'"
    [[ "$output" != *"| # |"* ]]
}

@test "the code around a finding is shown, numbered, with its line marked" {
    report="$(jq '.findings[0] += {excerpt: {start: 8, text: "a\nb\n$x = 1 | 2;\nd"}} | .findings[0].line = 10' "$reports/mixed.json")"
    run bash -c "'$render' <<< '$report'"
    [[ "$output" == *'```php'* ]]
    [[ "$output" == *"   8 | a"* ]]
    [[ "$output" == *"> 10 | \$x = 1 | 2;"* ]]
    [[ "$output" == *"  11 | d"* ]]
}

@test "code that holds a fence gets a longer one" {
    report="$(jq '.findings[0] += {excerpt: {start: 7, text: "$s = \"```\";"}}' "$reports/mixed.json")"
    run bash -c "'$render' <<< '$report'"
    [[ "$output" == *"~~~~php"* ]]
}

@test "a pipe in a title does not break the table" {
    run bash -c "jq '.findings[0].title = \"a | b\"' '$reports/mixed.json' | '$render'"
    [[ "$output" == *'| a \| b |'* ]]
}
