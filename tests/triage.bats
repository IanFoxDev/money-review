#!/usr/bin/env bats

setup() {
    triage="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/triage.sh"
    diffs="$BATS_TEST_DIRNAME/fixtures/diffs"
}

field() { jq -c "$1" <<< "$output"; }

@test "a readme change is not money" {
    run "$triage" "$diffs/readme-only.diff"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "false" ]
}

@test "a php change without money words is not money" {
    run "$triage" "$diffs/avatar.diff"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "false" ]
}

@test "tests are excluded by default" {
    run "$triage" "$diffs/test-only.diff"
    [ "$(field .money)" = "false" ]
}

@test "a withdrawal matches tx, race, idempotency and arithmetic" {
    run "$triage" "$diffs/withdrawal.diff"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "true" ]
    [ "$(field .categories)" = '["IDEM","MONEY","RACE","TX"]' ]
    [ "$(field .files)" = '["app/WithdrawalService.php"]' ]
}

@test "removed lines count: dropping a lock is a race candidate" {
    run "$triage" "$diffs/webhook-deleted-lock.diff"
    [ "$(field .money)" = "true" ]
    [ "$(field '.categories | index("RACE") != null')" = "true" ]
}

@test "the diff can come from stdin" {
    run bash -c "'$triage' < '$diffs/withdrawal.diff'"
    [ "$(field .money)" = "true" ]
}

@test "a deleted file without money words is out of scope by default" {
    run "$triage" "$diffs/deleted-file.diff"
    [ "$(field .money)" = "false" ]
}

@test "money_paths put a file in scope for every category" {
    run "$triage" --config "$BATS_TEST_DIRNAME/fixtures/money-paths.json" "$diffs/deleted-file.diff"
    [ "$(field .money)" = "true" ]
    [ "$(field .files)" = '["app/Billing/Ledger.php"]' ]
    [ "$(field .categories)" = '["IDEM","MONEY","RACE","TX"]' ]
    [ "$(field '.reasons[0].scope')" = '"money_paths"' ]
}

@test "context from the config is passed through" {
    run "$triage" --config "$BATS_TEST_DIRNAME/fixtures/money-paths.json" "$diffs/readme-only.diff"
    [ "$(field .context)" = '"Wallet balances live in wallets.balance_cents."' ]
}

@test "an empty diff is not money" {
    run bash -c "'$triage' < /dev/null"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "false" ]
}

@test "unknown options fail" {
    run "$triage" --nope
    [ "$status" -eq 2 ]
}

has() { [ "$(field ".categories | index(\"$1\") != null")" = "true" ]; }

@test "php with mongodb: read then updateOne is a race, produce after it is a transaction boundary" {
    run "$triage" "$diffs/php-mongo-kafka.diff"
    [ "$(field .money)" = "true" ]
    has RACE
    has TX
}

@test "php with a mongodb session transaction is a transaction boundary" {
    run "$triage" "$diffs/php-mongo-session.diff"
    has TX
}

@test "go is reviewed, money words match in any case" {
    run "$triage" "$diffs/go-mongo-inc.diff"
    [ "$(field .money)" = "true" ]
    has RACE
    has TX
}

@test "go tests are excluded by default" {
    run "$triage" "$diffs/go-test-only.diff"
    [ "$(field .money)" = "false" ]
}

@test "a kafka consumer that commits before it applies is an idempotency candidate" {
    run "$triage" "$diffs/go-kafka-consumer.diff"
    [ "$(field .money)" = "true" ]
    has IDEM
}
