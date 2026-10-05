#!/usr/bin/env bats

setup() {
    eval_dir="$BATS_TEST_DIRNAME/../eval"
    out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    "$eval_dir/expected.sh" race-withdraw-no-lock tx-payout-batch-one-transaction clean-installments > "$out/expected.json"
}

result() { # case run exit report-json [claude-json]
    local dir="$out/results/$1/$2"
    mkdir -p "$dir"
    jq -n --arg c "$1" --argjson n "$2" --argjson e "$3" '{case: $c, run: $n, exit: $e, seconds: 60}' > "$dir/meta.json"
    echo "$4" > "$dir/report.json"
    [ -z "${5:-}" ] || echo "$5" > "$dir/claude.json"
}

finding() { # rule file line
    jq -nc --arg r "$1" --arg f "$2" --argjson l "$3" \
        '{rule: $r, severity: "high", file: $f, line: $l, title: "t", scenario: "s", fix: "f"}'
}

summary() { jq -c "$1" "$out/summary.json"; }

@test "true positive, wrong rule, acceptable extra and false alarm are told apart" {
    w=app/Services/WithdrawalService.php
    tp="$(finding RACE-1 $w 19)"
    acceptable="$(finding MONEY-6 $w 40)"
    fp="$(finding IDEM-3 app/Services/Ledger.php 10)"
    result race-withdraw-no-lock 1 0 "{\"findings\": [$tp, $acceptable, $fp], \"rejected\": []}" '{"total_cost_usd": 0.4, "num_turns": 5}'

    j=app/Jobs/RunMonthlyPayouts.php
    wrong="$(finding IDEM-6 $j 40)"
    dup1="$(finding TX-1 $j 39)"
    dup2="$(finding TX-6 $j 27)"
    result tx-payout-batch-one-transaction 1 1 "{\"findings\": [$wrong, $dup1, $dup2], \"rejected\": []}" '{"total_cost_usd": 0.2, "num_turns": 4}'

    result clean-installments 1 0 '{"findings": [], "rejected": []}' '{"total_cost_usd": 0.1, "num_turns": 3}'

    run "$eval_dir/score.sh" "$out"
    [ "$status" -eq 0 ]
    [ "$(summary '[.true_positives, .false_positives, .missed]')" = "[2,1,0]" ]
    [ "$(summary '.wrong_rule')" = "1" ]
    [ "$(summary '.duplicates')" = "1" ]
    [ "$(summary '.acceptable_extras')" = "1" ]
    [ "$(summary '.precision')" = "0.667" ]
    [ "$(summary '.recall')" = "1" ]
    [ "$(summary '.clean_runs_with_findings')" = "0" ]
    [ "$(summary '.cost_usd.total')" = "0.7" ]
    [[ "$output" == *"- race-withdraw-no-lock: IDEM-3 \`app/Services/Ledger.php:10\` t"* ]]
}

@test "a finding outside the range misses the bug" {
    result race-withdraw-no-lock 1 0 "{\"findings\": [$(finding RACE-1 app/Services/WithdrawalService.php 40)], \"rejected\": []}" '{}'
    "$eval_dir/expected.sh" race-withdraw-no-lock > "$out/expected.json"
    run "$eval_dir/score.sh" "$out"
    [ "$(summary '[.true_positives, .false_positives, .missed]')" = "[0,1,1]" ]
}

@test "a bug case that triage skipped is counted" {
    "$eval_dir/expected.sh" race-withdraw-no-lock > "$out/expected.json"
    result race-withdraw-no-lock 1 0 '{"findings": [], "rejected": []}'
    run "$eval_dir/score.sh" "$out"
    [ "$(summary '.triage_misses')" = "1" ]
    [ "$(summary '.recall')" = "0" ]
}

@test "a false alarm on a clean case is counted" {
    "$eval_dir/expected.sh" clean-installments > "$out/expected.json"
    result clean-installments 1 0 "{\"findings\": [$(finding MONEY-4 app/Services/InstallmentPlan.php 18)], \"rejected\": []}" '{}'
    run "$eval_dir/score.sh" "$out"
    [ "$(summary '.clean_runs_with_findings')" = "1" ]
    [ "$(summary '.precision')" = "0" ]
}
