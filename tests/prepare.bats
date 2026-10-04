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
