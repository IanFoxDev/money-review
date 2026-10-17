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

@test "money_paths put a file in scope for the four base categories" {
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

@test "money words in the path put a file in scope" {
    run "$triage" "$diffs/go-commit-before-apply.diff"
    [ "$(field .money)" = "true" ]
    has IDEM
    [ "$(field '.reasons[0].scope')" = '"path"' ]
}

@test "producing to a broker loads the idempotency checklist" {
    run "$triage" "$diffs/php-produce-without-key.diff"
    has IDEM
    has TX
}

@test "a provider notification loads the provider checklist" {
    run "$triage" "$diffs/appstore-notification.diff"
    [ "$status" -eq 0 ]
    [ "$(field '.categories | index("PSP") != null')" = "true" ]
}

@test "a private rule with a pattern is a category of its own" {
    echo '{"rules": [{"prefix": "ACME", "file": "acme.md", "match": "recordRenewal"}]}' > "$BATS_TEST_TMPDIR/c.json"
    run "$triage" --config "$BATS_TEST_TMPDIR/c.json" "$diffs/appstore-notification.diff"
    [ "$status" -eq 0 ]
    [ "$(field '.categories | index("ACME") != null')" = "true" ]
    [ "$(field '[.reasons[] | select(.category == "ACME") | .match][0]')" = '"recordRenewal"' ]
}

@test "a private rule that does not match is not loaded" {
    echo '{"rules": [{"prefix": "ACME", "file": "acme.md", "match": "nothingLikeThis"}]}' > "$BATS_TEST_TMPDIR/c.json"
    run "$triage" --config "$BATS_TEST_TMPDIR/c.json" "$diffs/appstore-notification.diff"
    [ "$(field '.categories | index("ACME")')" = "null" ]
}

@test "a private rule without a pattern applies to every money file" {
    echo '{"rules": [{"prefix": "ACME", "file": "acme.md"}]}' > "$BATS_TEST_TMPDIR/c.json"
    run "$triage" --config "$BATS_TEST_TMPDIR/c.json" "$diffs/withdrawal.diff"
    [ "$(field '.categories | index("ACME") != null')" = "true" ]
    run "$triage" --config "$BATS_TEST_TMPDIR/c.json" "$diffs/avatar.diff"
    [ "$(field .money)" = "false" ]
}

@test "a private rule cannot take a built-in or malformed prefix" {
    for p in PSP INV acme A-1 ""; do
        echo "{\"rules\": [{\"prefix\": \"$p\", \"file\": \"x.md\"}]}" > "$BATS_TEST_TMPDIR/c.json"
        run "$triage" --config "$BATS_TEST_TMPDIR/c.json" "$diffs/withdrawal.diff"
        [ "$status" -eq 2 ]
    done
    echo '{"rules": [{"prefix": "ACME", "file": "a.md"}, {"prefix": "ACME", "file": "b.md"}]}' > "$BATS_TEST_TMPDIR/c.json"
    run "$triage" --config "$BATS_TEST_TMPDIR/c.json" "$diffs/withdrawal.diff"
    [ "$status" -eq 2 ]
}

@test "a provider postback loads the provider and reversal checklists" {
    run "$triage" "$diffs/provider-postback.diff"
    [ "$(field .money)" = "true" ]
    [ "$(field '[.categories[] | select(. == "PSP" or . == "REV")]')" = '["PSP","REV"]' ]
    [ "$(field '.categories | index("SUB")')" = "null" ]
}

@test "a renewal job loads the subscription and time checklists" {
    run "$triage" "$diffs/subscription-renewal.diff"
    [ "$(field .money)" = "true" ]
    [ "$(field '[.categories[] | select(. == "SUB" or . == "TIME")]')" = '["SUB","TIME"]' ]
    [ "$(field '.categories | index("REV")')" = "null" ]
}
