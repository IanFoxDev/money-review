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
    # race-withdraw-no-lock has two more bugs (no ledger entry, negative amount) left unfound.
    [ "$(summary '[.true_positives, .false_positives, .missed]')" = "[2,1,2]" ]
    [ "$(summary '.wrong_rule')" = "1" ]
    [ "$(summary '.duplicates')" = "1" ]
    [ "$(summary '.acceptable_extras')" = "1" ]
    [ "$(summary '.precision')" = "0.667" ]
    [ "$(summary '.recall')" = "0.5" ]
    [ "$(summary '.clean_runs_with_findings')" = "0" ]
    [ "$(summary '.cost_usd.total')" = "0.7" ]
    [[ "$output" == *"- race-withdraw-no-lock: IDEM-3 \`app/Services/Ledger.php:10\` t"* ]]
}

@test "a finding outside the range misses the bug" {
    result race-withdraw-no-lock 1 0 "{\"findings\": [$(finding RACE-1 app/Services/WithdrawalService.php 40)], \"rejected\": []}" '{}'
    "$eval_dir/expected.sh" race-withdraw-no-lock > "$out/expected.json"
    run "$eval_dir/score.sh" "$out"
    [ "$(summary '[.true_positives, .false_positives, .missed]')" = "[0,1,3]" ]
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

@test "the summary records the models and the environment" {
    echo '{"date": "2026-10-06", "claude_code": "2.1.289", "money_review": "0.4.0", "commit": "abc1234", "runs_per_case": 1}' > "$out/env.json"
    w=app/Services/WithdrawalService.php
    result race-withdraw-no-lock 1 0 "{\"findings\": [$(finding RACE-1 $w 19)], \"rejected\": []}" \
        '{"total_cost_usd": 0.4, "modelUsage": {"claude-sonnet-5-5": {}, "claude-opus-5-5": {}}}'
    result clean-installments 1 0 '{"findings": [], "rejected": []}' '{"total_cost_usd": 0.2, "modelUsage": {"claude-sonnet-5-5": {}}}'
    run "$eval_dir/score.sh" "$out"
    [ "$status" -eq 0 ]
    [ "$(summary .models)" = '["claude-opus-5-5","claude-sonnet-5-5"]' ]
    [ "$(summary .env.commit)" = '"abc1234"' ]
    [[ "$output" == *"Measured 2026-10-06 with money-review 0.4.0 (abc1234), Claude Code 2.1.289."* ]]
    [[ "$output" == *"Models: claude-opus-5-5, claude-sonnet-5-5."* ]]
}

@test "a finding without a rule matches a bug by file and line" {
    "$eval_dir/expected.sh" race-withdraw-no-lock > "$out/expected.json"
    w=app/Services/WithdrawalService.php
    near="$(jq -nc --arg f $w '{file: $f, line: 21, title: "t"}')"
    extra="$(jq -nc --arg f $w '{file: $f, line: 60, title: "t"}')"
    other="$(jq -nc '{file: "app/Models/User.php", line: 3, title: "t"}')"
    result race-withdraw-no-lock 1 0 "{\"findings\": [$near, $extra, $other]}" '{}'
    run "$eval_dir/score.sh" "$out"
    [ "$(summary '[.true_positives, .acceptable_extras, .false_positives, .missed]')" = "[1,1,1,2]" ]
}

@test "a second finding goes to a bug that is not found yet" {
    "$eval_dir/expected.sh" money-chargeback-wrong-amount > "$out/expected.json"
    c=app/Http/Controllers/ChargebackWebhookController.php
    result money-chargeback-wrong-amount 1 0 "{\"findings\": [$(finding MONEY-0 $c 42), $(finding MONEY-0 $c 41)], \"rejected\": []}" '{}'
    run "$eval_dir/score.sh" "$out"
    [ "$(summary '[.true_positives, .duplicates, .missed]')" = "[2,0,0]" ]
}
