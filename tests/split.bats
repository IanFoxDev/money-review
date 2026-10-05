#!/usr/bin/env bats

load helpers

setup() {
    split="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/split.sh"
    d="$BATS_TEST_TMPDIR/change.diff"
    out="$BATS_TEST_TMPDIR/groups"
}

@test "files go in path order and a group closes at the line limit" {
    make_diff "$d" app/Wallet/B.php:300 app/Billing/A.php:300 app/Wallet/C.php:300
    run "$split" "$d" "$out" 650
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.[] | .files]' <<< "$output")" = '[["app/Billing/A.php","app/Wallet/B.php"],["app/Wallet/C.php"]]' ]
    [ "$(jq -c '[.[] | .lines]' <<< "$output")" = '[600,300]' ]
}

@test "each group diff holds only its files" {
    make_diff "$d" a.php:10 b.php:10
    run "$split" "$d" "$out" 15
    grep -q '^+++ b/a.php' "$out/group-1.diff"
    ! grep -q 'b.php' "$out/group-1.diff"
    grep -q '^+++ b/b.php' "$out/group-2.diff"
}

@test "a file bigger than the limit gets a group of its own" {
    make_diff "$d" a.php:5 big.php:900 c.php:5
    run "$split" "$d" "$out" 100
    [ "$(jq -c '[.[] | .files]' <<< "$output")" = '[["a.php"],["big.php"],["c.php"]]' ]
}

@test "only the given files are kept" {
    make_diff "$d" a.php:5 skip.php:5 c.php:5
    run "$split" "$d" "$out" 100 a.php c.php
    [ "$(jq -c '[.[] | .files]' <<< "$output")" = '[["a.php","c.php"]]' ]
    ! grep -q skip.php "$out/group-1.diff"
}

@test "an empty diff gives no groups" {
    : > "$d"
    run "$split" "$d" "$out" 100
    [ "$(jq -c . <<< "$output")" = '[]' ]
}
