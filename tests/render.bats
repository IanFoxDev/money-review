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
    high="${output%%### LOW*}"
    [[ "$high" == *"### HIGH RACE-1: Balance check and debit are not atomic"* ]]
}

@test "a finding shows location, scenario and fix" {
    run "$render" "$reports/mixed.json"
    [[ "$output" == *'`app/WithdrawalService.php:7`'* ]]
    [[ "$output" == *"**What happens:** Two withdrawals of 80"* ]]
    [[ "$output" == *"**Fix:** lockForUpdate()"* ]]
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
