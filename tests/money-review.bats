#!/usr/bin/env bats

setup() {
    bin="$BATS_TEST_DIRNAME/../plugins/money-review/bin/money-review"
    diffs="$BATS_TEST_DIRNAME/fixtures/diffs"
    reports="$BATS_TEST_DIRNAME/fixtures/reports"
    export MONEY_REVIEW_CLAUDE="$BATS_TEST_DIRNAME/fake/claude"
    export FAKE_LOG="$BATS_TEST_TMPDIR/claude.args"
    export FAKE_REPORT="$reports/mixed.json"
    export MONEY_REVIEW_RETRY_DELAY=0
    unset ANTHROPIC_API_KEY
    out="$BATS_TEST_TMPDIR/out"
}

@test "refuses to run with ANTHROPIC_API_KEY set" {
    ANTHROPIC_API_KEY=sk-test run "$bin" --diff "$diffs/withdrawal.diff"
    [ "$status" -eq 3 ]
    [[ "$output" == *"bill the API instead of your subscription"* ]]
    [ ! -f "$FAKE_LOG" ]
}

@test "--allow-api-key lets it run" {
    ANTHROPIC_API_KEY=sk-test run "$bin" --allow-api-key --diff "$diffs/withdrawal.diff" --out "$out"
    [ "$status" -eq 0 ]
    [ -f "$FAKE_LOG" ]
}

@test "a change without money never starts claude" {
    run "$bin" --diff "$diffs/readme-only.diff" --out "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no money-related changes"* ]]
    [ ! -f "$FAKE_LOG" ]
    [ "$(jq -c . "$out/report.json")" = '{"findings":[],"rejected":[]}' ]
}

@test "json output for a change without money is an empty report" {
    run "$bin" --diff "$diffs/readme-only.diff" --format json
    [ "$(jq -c . <<< "$output")" = '{"findings":[],"rejected":[]}' ]
}

@test "a money change is reviewed and rendered" {
    run "$bin" --diff "$diffs/withdrawal.diff" --out "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"### 1. HIGH RACE-1"* ]]
    [[ "$output" == *"4 turns"* ]]
    [[ "$output" == *"API-equivalent 0.37 USD"* ]]
    [[ "$output" == *"models: claude-opus-5-5, claude-sonnet-5-5"* ]]
}

@test "--quiet suppresses usage but keeps the rendered report" {
    run "$bin" --quiet --diff "$diffs/withdrawal.diff" --out "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"### 1. HIGH RACE-1"* ]]
    [[ "$output" != *"4 turns"* ]]
    [[ "$output" != *"API-equivalent"* ]]
    [ -f "$FAKE_LOG" ]
}

@test "--quiet keeps JSON output and the findings exit status" {
    run "$bin" --quiet --diff "$diffs/withdrawal.diff" --format json --fail-on high
    [ "$status" -eq 1 ]
    [ "$(jq '.findings | length' <<< "$output")" = "2" ]
    [[ "$output" != *"API-equivalent"* ]]
}

@test "--quiet keeps errors when a review produces no report" {
    FAKE_REPORT="" run "$bin" --quiet --diff "$diffs/withdrawal.diff" --out "$out" --retries 0
    [ "$status" -eq 4 ]
    [[ "$output" == *"without a valid report"* ]]
    [[ "$output" == *"done"* ]]
}

@test "claude is called with the plugin, sonnet and narrow permissions" {
    run "$bin" --diff "$diffs/withdrawal.diff" --out "$out"
    args="$(cat "$FAKE_LOG")"
    [[ "$args" == *"/money-review:money-review --diff $out/change.diff --out $out"* ]]
    grep -qx -- "--model" "$FAKE_LOG"
    grep -qx -- "sonnet" "$FAKE_LOG"
    grep -qx -- "--plugin-dir" "$FAKE_LOG"
    grep -qx -- "Edit(/$out/report.json)" "$FAKE_LOG"
    grep -q -- "^Edit(//" "$FAKE_LOG"
    grep -q -- "^Bash(.*/scripts/prepare.sh:\*)$" "$FAKE_LOG"
    ! grep -qx -- "Bash" "$FAKE_LOG"
}

@test "json format prints the report" {
    run "$bin" --diff "$diffs/withdrawal.diff" --format json
    [ "$(jq -r '.findings | length' <<< "${output#*$'\n'}")" = "2" ]
}

@test "--fail-on high exits 1 when there is a high finding" {
    run "$bin" --diff "$diffs/withdrawal.diff" --fail-on high
    [ "$status" -eq 1 ]
}

@test "--fail-on high exits 0 when findings are lower" {
    jq '.findings |= map(.severity = "low")' "$reports/mixed.json" > "$BATS_TEST_TMPDIR/low.json"
    FAKE_REPORT="$BATS_TEST_TMPDIR/low.json" run "$bin" --diff "$diffs/withdrawal.diff" --fail-on high
    [ "$status" -eq 0 ]
}

@test "a run without a report fails with code 4" {
    FAKE_REPORT="" run "$bin" --diff "$diffs/withdrawal.diff" --out "$out"
    [ "$status" -eq 4 ]
    [[ "$output" == *"without a valid report"* ]]
    [[ "$output" == *"done"* ]]
}

@test "an old claude is rejected" {
    FAKE_VERSION=2.0.9 run "$bin" --diff "$diffs/withdrawal.diff"
    [ "$status" -eq 2 ]
    [[ "$output" == *"2.1.0 or newer is required, found 2.0.9"* ]]
}

@test "bad options are usage errors" {
    run "$bin" --format html
    [ "$status" -eq 2 ]
    run "$bin" --fail-on critical
    [ "$status" -eq 2 ]
    run "$bin" --nope
    [ "$status" -eq 2 ]
}

@test "a change split into groups gets more turns" {
    load helpers
    make_diff "$BATS_TEST_TMPDIR/big.diff" a.php:50 b.php:50 c.php:50
    printf '{"review": {"group_lines": 60}}' > "$BATS_TEST_TMPDIR/cfg.json"
    run "$bin" --diff "$BATS_TEST_TMPDIR/big.diff" --config "$BATS_TEST_TMPDIR/cfg.json" --out "$out"
    grep -qx -- "--max-turns" "$FAKE_LOG"
    [ "$(grep -A1 -x -- '--max-turns' "$FAKE_LOG" | tail -1)" = "28" ]
}

@test "a finding ignored in the config does not fail the run" {
    echo '{"ignore": [{"rule": "RACE-1", "reason": "one worker per wallet"}]}' > "$BATS_TEST_TMPDIR/cfg.json"
    run "$bin" --diff "$diffs/withdrawal.diff" --config "$BATS_TEST_TMPDIR/cfg.json" --fail-on high --out "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 finding(s) suppressed by the team"* ]]
    [ "$(jq -r '.suppressed[0].reason' "$out/report.json")" = "one worker per wallet" ]
}

@test "an output directory with a space works" {
    run "$bin" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/my out" --format json
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/my out/report.json" ]
    [ "$(jq '.findings | length' "$BATS_TEST_TMPDIR/my out/report.json")" = "2" ]
}

@test "a run that ends without a report is tried again" {
    FAKE_FAIL=1 run "$bin" --diff "$diffs/withdrawal.diff" --out "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"trying again in 0 s (1 of 1)"* ]]
    [ "$(cat "$FAKE_LOG.calls")" = "2" ]
    [ -f "$out/report.json" ]
}

@test "retries stop at the limit" {
    FAKE_FAIL=5 run "$bin" --diff "$diffs/withdrawal.diff" --out "$out" --retries 2
    [ "$status" -eq 4 ]
    [ "$(cat "$FAKE_LOG.calls")" = "3" ]
    [[ "$output" == *"529 overloaded"* ]]
}

@test "--retries 0 runs claude once" {
    FAKE_FAIL=1 run "$bin" --diff "$diffs/withdrawal.diff" --out "$out" --retries 0
    [ "$status" -eq 4 ]
    [ "$(cat "$FAKE_LOG.calls")" = "1" ]
}

@test "a usage limit is not retried" {
    FAKE_FAIL=1 FAKE_FAIL_RESULT="Claude AI usage limit reached|1760000000" run "$bin" --diff "$diffs/withdrawal.diff" --out "$out"
    [ "$status" -eq 4 ]
    [ "$(cat "$FAKE_LOG.calls")" = "1" ]
    [[ "$output" == *"usage limit reached"* ]]
}

@test "files that may hold secrets are denied to the agents" {
    run "$bin" --diff "$diffs/withdrawal.diff" --out "$out"
    [ "$status" -eq 0 ]
    grep -qx -- '--disallowedTools' "$FAKE_LOG"
    grep -qx 'Read(\*\*/.env)' "$FAKE_LOG"
    grep -qx 'Read(\*\*/\*.pem)' "$FAKE_LOG"
    grep -qx 'Read(\*\*/secrets/\*\*)' "$FAKE_LOG"
}
