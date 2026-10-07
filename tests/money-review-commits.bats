#!/usr/bin/env bats

setup() {
    bin="$BATS_TEST_DIRNAME/../plugins/money-review/bin/money-review"
    range="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/range.sh"
    prepare="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/prepare.sh"
    export MONEY_REVIEW_CLAUDE="$BATS_TEST_DIRNAME/fake/claude"
    export FAKE_LOG="$BATS_TEST_TMPDIR/claude.args"
    export FAKE_REPORT="$BATS_TEST_DIRNAME/fixtures/reports/mixed.json"
    unset ANTHROPIC_API_KEY
    out="$BATS_TEST_TMPDIR/out"

    # master: init, invoice. feature (from init): payout, refund. Then an
    # uncommitted edit that must stay out of a --commits review.
    repo="$BATS_TEST_TMPDIR/repo"
    git init -q -b master "$repo"
    cd "$repo"
    git config user.name test
    git config user.email test@example.com
    mkdir app
    printf '<?php\nfinal class Wallet {}\n' > app/Wallet.php
    git add . && git commit -qm init
    root="$(git rev-parse HEAD)"
    git checkout -q -b feature
    printf '<?php\nfinal class Payout { public int $amount = 0; }\n' > app/Payout.php
    git add . && git commit -qm payout
    payout="$(git rev-parse HEAD)"
    printf '<?php\nfinal class Refund { public int $amount = 0; }\n' > app/Refund.php
    git add . && git commit -qm refund
    refund="$(git rev-parse HEAD)"
    git checkout -q master
    printf '<?php\nfinal class Invoice { public int $amount = 0; }\n' > app/Invoice.php
    git add . && git commit -qm invoice
    git checkout -q feature
    printf '<?php\nfinal class Wallet { public int $balance = 0; }\n' > app/Wallet.php
}

field() { jq -r "$1" <<< "$output"; }

@test "one commit is compared with its parent" {
    run "$range" "$payout"
    [ "$status" -eq 0 ]
    [ "$(field .start)" = "$root" ]
    [ "$(field .head)" = "$payout" ]
}

@test "a range starts at the merge base, not at the tip of master" {
    run "$range" master..feature
    [ "$(field .start)" = "$root" ]
    [ "$(field .head)" = "$refund" ]
    run "$range" master...feature
    [ "$(field .start)" = "$root" ]
}

@test "a range without an end runs to HEAD" {
    run "$range" "$payout.."
    [ "$(field .start)" = "$payout" ]
    [ "$(field .head)" = "$refund" ]
}

@test "the root commit is compared with the empty tree" {
    run "$range" "$root"
    [ "$status" -eq 0 ]
    [ "$(field .head)" = "$root" ]
    [ "$(git diff --name-only "$(field .start)" "$(field .head)")" = "app/Wallet.php" ]
}

@test "unknown commits and empty ranges are errors" {
    run "$range" nosuchref
    [ "$status" -eq 2 ]
    run "$range" feature..feature
    [ "$status" -eq 2 ]
}

@test "prepare reviews only what the commits changed" {
    run "$prepare" --commits master..feature --out "$out"
    [ "$status" -eq 0 ]
    [ "$(jq -c .files <<< "$output")" = '["app/Payout.php","app/Refund.php"]' ]
    [ "$(field .base)" = "$root" ]
}

@test "commits are reviewed in a worktree at their head, the working tree untouched" {
    run "$bin" --commits "$payout" --out "$out"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^diff --git' "$out/change.diff")" = "1" ]
    grep -q 'app/Payout.php' "$out/change.diff"
    [[ "$(cat "$FAKE_LOG.cwd")" == */out/worktree ]]
    [ ! -d "$out/worktree" ]
    [ -z "$(git worktree list --porcelain | grep "$out" || true)" ]
    grep -q 'balance' app/Wallet.php
}

@test "--commits does not mix with --base, --diff or --pr" {
    run "$bin" --commits HEAD --base master
    [ "$status" -eq 2 ]
    run "$bin" --commits HEAD --diff /dev/null
    [ "$status" -eq 2 ]
    run "$bin" --commits HEAD --pr 1
    [ "$status" -eq 2 ]
    run "$bin" --commits HEAD --post
    [ "$status" -eq 2 ]
}
