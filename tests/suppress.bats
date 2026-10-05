#!/usr/bin/env bats

setup() {
    suppress="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/suppress.sh"
    render="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/render.sh"
    cd "$BATS_TEST_TMPDIR"
    mkdir -p app src/Reports
    cp "$BATS_TEST_DIRNAME/fixtures/reports/mixed.json" report.json
    # mixed.json: MONEY-2 at app/WithdrawalService.php:4, RACE-1 at :7.
    printf '%s\n' '<?php' 'final class WithdrawalService {' '    public function withdraw(' \
        '        int $amount,' '    ): void {' '        $balance = $this->balance();' \
        '        $this->debit($amount);' '    }' '}' > app/WithdrawalService.php
    echo '{"ignore": []}' > prepared.json
}

comment_at() { # line text: replaces that line of the service
    awk -v n="$1" -v t="$2" 'NR == n { print t; next } { print }' app/WithdrawalService.php > f.tmp
    mv f.tmp app/WithdrawalService.php
}

rules() { jq -c "[.$1[].rule]" report.json; }

@test "nothing to ignore keeps the report as it is" {
    run "$suppress" report.json prepared.json
    [ "$status" -eq 0 ]
    [ "$(rules findings)" = '["MONEY-2","RACE-1"]' ]
    [ "$(jq 'has("suppressed")' report.json)" = "false" ]
}

@test "a comment on the line above suppresses the rule" {
    comment_at 6 '        // money-review: ignore RACE-1 the caller holds lockForUpdate on the wallet'
    run "$suppress" report.json prepared.json
    [ "$status" -eq 0 ]
    [ "$(rules findings)" = '["MONEY-2"]' ]
    [ "$(jq -c '.suppressed[0] | [.rule, .by, .reason]' report.json)" = '["RACE-1","comment","the caller holds lockForUpdate on the wallet"]' ]
}

@test "a comment at the end of the line counts too" {
    comment_at 7 '        $this->debit($amount); # money-review: ignore RACE-1: single worker, see OPS-12'
    run "$suppress" report.json prepared.json
    [ "$(rules suppressed)" = '["RACE-1"]' ]
    [ "$(jq -r '.suppressed[0].reason' report.json)" = "single worker, see OPS-12" ]
}

@test "a category and a list of rules both match" {
    comment_at 3 '    /* money-review: ignore TX-2,MONEY amounts are always in the wallet currency */'
    comment_at 6 '        // money-review: ignore RACE balance is advisory'
    run "$suppress" report.json prepared.json
    [ "$(rules findings)" = '[]' ]
    [ "$(jq -r '.suppressed[] | select(.rule == "MONEY-2") | .reason' report.json)" = "amounts are always in the wallet currency" ]
}

@test "a comment for another rule does not suppress" {
    comment_at 6 '        // money-review: ignore RACE-2 not this one'
    run "$suppress" report.json prepared.json
    [ "$(rules findings)" = '["MONEY-2","RACE-1"]' ]
}

@test "a comment two lines above does not suppress" {
    comment_at 5 '    ): void { // money-review: ignore RACE-1 too far away'
    run "$suppress" report.json prepared.json
    [ "$(rules findings)" = '["MONEY-2","RACE-1"]' ]
}

@test "a comment without a reason is not applied and says so" {
    comment_at 6 '        // money-review: ignore RACE-1'
    run "$suppress" report.json prepared.json
    [ "$status" -eq 0 ]
    [ "$(rules findings)" = '["MONEY-2","RACE-1"]' ]
    [[ "$output" == *"ignore comment at app/WithdrawalService.php:7 has no reason, RACE-1 is kept"* ]]
}

@test "a config entry suppresses a rule in matching files" {
    echo '{"ignore": [{"rule": "MONEY-2", "path": "app/*", "reason": "single-currency product"}]}' > prepared.json
    run "$suppress" report.json prepared.json
    [ "$(rules findings)" = '["RACE-1"]' ]
    [ "$(jq -c '.suppressed[0] | [.by, .reason, .severity]' report.json)" = '["config","single-currency product","low"]' ]
}

@test "a config entry for other paths does not suppress" {
    echo '{"ignore": [{"rule": "MONEY", "path": "src/Reports/*", "reason": "reports only"}]}' > prepared.json
    run "$suppress" report.json prepared.json
    [ "$(rules findings)" = '["MONEY-2","RACE-1"]' ]
}

@test "a config entry without a path covers every file" {
    echo '{"ignore": [{"rule": "RACE-1", "reason": "one worker per wallet"}]}' > prepared.json
    run "$suppress" report.json prepared.json
    [ "$(rules findings)" = '["MONEY-2"]' ]
}

@test "a config entry without a reason is not applied" {
    echo '{"ignore": [{"rule": "RACE-1", "reason": " "}]}' > prepared.json
    run "$suppress" report.json prepared.json
    [ "$(rules findings)" = '["MONEY-2","RACE-1"]' ]
    [[ "$output" == *"ignore entry for RACE-1 in * has no reason"* ]]
}

@test "a finding in a file that is gone is kept" {
    rm app/WithdrawalService.php
    run "$suppress" report.json
    [ "$status" -eq 0 ]
    [ "$(rules findings)" = '["MONEY-2","RACE-1"]' ]
}

@test "suppressed findings are folded in the rendered report" {
    comment_at 6 '        // money-review: ignore RACE-1 the caller holds the lock'
    "$suppress" report.json prepared.json
    run "$render" report.json
    [[ "$output" == *"1 finding(s): 0 high, 0 medium, 1 low."* ]]
    [[ "$output" == *"1 finding(s) suppressed by the team"* ]]
    [[ "$output" == *'- RACE-1 `app/WithdrawalService.php:7` Balance check and debit are not atomic. Ignored by comment: the caller holds the lock'* ]]
}
