#!/usr/bin/env bats

setup() {
    prepare="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/prepare.sh"
    diffs="$BATS_TEST_DIRNAME/fixtures/diffs"
    repo="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$repo/app"
    cd "$repo"
    git init -q -b master
    git config user.name test
    git config user.email test@example.com
    printf '<?php\nfinal class Wallet {}\n' > app/Wallet.php
    git add . && git commit -qm init
}

field() { jq -c "$1" <<< "$output"; }

@test "a given diff is copied and triaged" {
    run "$prepare" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "true" ]
    [ "$(field .diff)" = "\"$BATS_TEST_TMPDIR/out/change.diff\"" ]
    cmp "$diffs/withdrawal.diff" "$BATS_TEST_TMPDIR/out/change.diff"
}

@test "checklists point at existing files, one per category" {
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field '.checklists | length')" = "4" ]
    for f in $(jq -r '.checklists[]' <<< "$output"); do
        [ -f "$f" ]
    done
}

@test "no money means no checklists" {
    run "$prepare" --diff "$diffs/readme-only.diff"
    [ "$(field .money)" = "false" ]
    [ "$(field .checklists)" = "[]" ]
}

@test "uncommitted edits against master are reviewed" {
    printf '<?php\nfinal class Wallet { public int $balance = 0; }\n' > app/Wallet.php
    run "$prepare"
    [ "$status" -eq 0 ]
    [ "$(field .base)" = '"master"' ]
    [ "$(field .files)" = '["app/Wallet.php"]' ]
}

@test "commits on a branch are reviewed against the merge base" {
    git checkout -q -b feature
    printf '<?php\nfinal class Payout { public int $amount = 0; }\n' > app/Payout.php
    git add . && git commit -qm payout
    run "$prepare"
    [ "$(field .files)" = '["app/Payout.php"]' ]
}

@test "new untracked files are reviewed" {
    printf '<?php\nfinal class Refund { public int $amount = 0; }\n' > app/Refund.php
    run "$prepare"
    [ "$(field .files)" = '["app/Refund.php"]' ]
}

@test "the project config is picked up from the repository root" {
    printf '{"money_paths": ["app/Wallet.php"], "context": "cents everywhere"}' > .money-review.json
    git add . && git commit -qm config
    printf '<?php\nfinal class Wallet { public function x() {} }\n' > app/Wallet.php
    run "$prepare"
    [ "$(field .money)" = "true" ]
    [ "$(field .context)" = '"cents everywhere"' ]
}

@test "an explicit base is used" {
    git checkout -q -b feature
    run "$prepare" --base feature
    [ "$(field .base)" = '"feature"' ]
}

@test "no base branch is an error" {
    git branch -m master trunk
    run "$prepare"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no base branch found"* ]]
}

@test "a diff that already sits in the output directory is used in place" {
    mkdir -p "$BATS_TEST_TMPDIR/out"
    cp "$diffs/withdrawal.diff" "$BATS_TEST_TMPDIR/out/change.diff"
    run "$prepare" --diff "$BATS_TEST_TMPDIR/out/change.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "true" ]
}

@test "a large change is split into groups with coverage" {
    load helpers
    make_diff "$BATS_TEST_TMPDIR/big.diff" app/Wallet/A.php:500 app/Wallet/B.php:500 docs/x.md:5
    run "$prepare" --diff "$BATS_TEST_TMPDIR/big.diff" --out "$BATS_TEST_TMPDIR/out"
    echo "$output" | head -n 20 # shown by bats only when the test fails
    [ "$status" -eq 0 ]
    [ "$(field '.groups | length')" = "2" ]
    [ "$(field '.coverage')" = '{"files_changed":3,"files_with_money":2,"files_reviewed":2,"groups":2,"not_reviewed":[]}' ]
    [ -f "$BATS_TEST_TMPDIR/out/prepared.json" ]
    [ -f "$(jq -r '.groups[1].diff' <<< "$output")" ]
}

@test "a small change is one group with the whole diff" {
    run "$prepare" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$(field '.groups | length')" = "1" ]
    [ "$(field '.groups[0].diff')" = "\"$BATS_TEST_TMPDIR/out/change.diff\"" ]
}

@test "groups over max_groups are listed as not reviewed" {
    load helpers
    make_diff "$BATS_TEST_TMPDIR/big.diff" a.php:50 b.php:50 c.php:50
    printf '{"review": {"group_lines": 60, "max_groups": 2}}' > "$BATS_TEST_TMPDIR/cfg.json"
    run "$prepare" --diff "$BATS_TEST_TMPDIR/big.diff" --config "$BATS_TEST_TMPDIR/cfg.json" --out "$BATS_TEST_TMPDIR/out"
    [ "$(field '.groups | length')" = "2" ]
    [ "$(field '.coverage.files_reviewed')" = "2" ]
    [ "$(field '.coverage.not_reviewed | length')" = "1" ]
}

@test "ignore entries from the config are passed on" {
    echo '{"ignore": [{"rule": "RACE-1", "reason": "one worker"}]}' > .money-review.json
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field '.ignore[0].rule')" = '"RACE-1"' ]
}

@test "no config means nothing is ignored" {
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field .ignore)" = '[]' ]
}
