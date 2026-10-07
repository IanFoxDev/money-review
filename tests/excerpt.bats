#!/usr/bin/env bats

setup() {
    excerpt="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/excerpt.sh"
    cd "$BATS_TEST_TMPDIR"
    mkdir -p app
    for i in 1 2 3 4 5 6 7 8 9 10; do echo "line $i"; done > app/Wallet.php
    echo "SECRET=1" > .env
    printf '+++ b/app/Wallet.php\n' > change.diff
}

report() { # file line
    jq -n --arg f "$1" --argjson l "$2" \
        '{findings: [{rule: "RACE-1", severity: "high", file: $f, line: $l, title: "t", scenario: "s", fix: "f"}], rejected: []}' > report.json
}

@test "two lines before and after the finding" {
    report app/Wallet.php 5
    run "$excerpt" report.json change.diff
    [ "$status" -eq 0 ]
    [ "$(jq -c '.findings[0].excerpt' report.json)" = '{"start":3,"text":"line 3\nline 4\nline 5\nline 6\nline 7"}' ]
}

@test "the excerpt stops at the edges of the file" {
    report app/Wallet.php 1
    "$excerpt" report.json change.diff
    [ "$(jq '.findings[0].excerpt.start' report.json)" = "1" ]
    report app/Wallet.php 10
    "$excerpt" report.json change.diff
    [ "$(jq -r '.findings[0].excerpt.text' report.json | wc -l | tr -d ' ')" = "3" ]
}

@test "files outside the diff are never read" {
    report .env 1
    "$excerpt" report.json change.diff
    [ "$(jq '.findings[0] | has("excerpt")' report.json)" = "false" ]
    report ../../etc/passwd 1
    "$excerpt" report.json change.diff
    [ "$(jq '.findings[0] | has("excerpt")' report.json)" = "false" ]
}

@test "a line past the end of the file gets no excerpt" {
    report app/Wallet.php 40
    "$excerpt" report.json change.diff
    [ "$(jq '.findings[0] | has("excerpt")' report.json)" = "false" ]
}
