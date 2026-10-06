#!/usr/bin/env bats

setup() {
    compare="$BATS_TEST_DIRNAME/../eval/compare.sh"
    cd "$BATS_TEST_TMPDIR"
}

# case found bugs runs false_positives skipped
row() {
    jq -nc --arg c "$1" --argjson f "$2" --argjson b "$3" --argjson r "$4" --argjson fp "$5" --argjson s "$6" \
        '{case: $c, found: $f, bugs: $b, runs: $r, false_positives: $fp, triage_skipped: $s}'
}

# file precision recall models-json rows...
summary_file() {
    local file="$1" p="$2" r="$3" m="$4"
    shift 4
    printf '%s\n' "$@" | jq -s --argjson p "$p" --argjson r "$r" --argjson m "$m" \
        '{precision: $p, recall: $r, clean_runs: 3, clean_runs_with_findings: 0, cost_usd: {per_reviewed_run: 0.3},
          models: $m, env: {date: "2026-10-06", money_review: "0.4.0", commit: "abc"}, cases_detail: .}' > "$file"
}

models='["claude-opus-5-5","claude-sonnet-5-5"]'

@test "the same results are no regression" {
    summary_file base.json 1 1 "$models" "$(row race-a 3 1 3 0 0)" "$(row clean-a 0 0 3 0 0)"
    cp base.json new.json
    run "$compare" base.json new.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"Every case present in both runs scored the same."* ]]
    [[ "$output" == *"No regressions."* ]]
}

@test "one run in three is noise" {
    summary_file base.json 1 1 "$models" "$(row race-a 3 1 3 0 0)"
    summary_file new.json 1 0.97 "$models" "$(row race-a 2 1 3 0 0)"
    run "$compare" base.json new.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"| race-a | 100% / 67% |"* ]]
}

@test "two runs in three lost is a regression" {
    summary_file base.json 1 1 "$models" "$(row race-a 3 1 3 0 0)"
    summary_file new.json 1 1 "$models" "$(row race-a 1 1 3 0 0)"
    run "$compare" base.json new.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"- race-a: recall 100% -> 33%"* ]]
}

@test "new false alarms on a clean case are a regression" {
    summary_file base.json 1 1 "$models" "$(row clean-a 0 0 3 0 0)"
    summary_file new.json 1 1 "$models" "$(row clean-a 0 0 3 2 0)"
    run "$compare" base.json new.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"- clean-a: false alarms per run 0 -> 0.67"* ]]
}

@test "any new triage skip is a regression" {
    summary_file base.json 1 1 "$models" "$(row race-a 3 1 3 0 0)"
    summary_file new.json 1 1 "$models" "$(row race-a 3 1 3 0 1)"
    run "$compare" base.json new.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"- race-a: skipped by triage 0 -> 1"* ]]
}

@test "a model change is called out" {
    summary_file base.json 1 1 "$models" "$(row race-a 3 1 3 0 0)"
    summary_file new.json 1 1 '["claude-opus-6-0","claude-sonnet-5-5"]' "$(row race-a 3 1 3 0 0)"
    run "$compare" base.json new.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"**The models changed.**"* ]]
}

@test "cases in only one run are listed apart" {
    summary_file base.json 1 1 "$models" "$(row race-a 3 1 3 0 0)" "$(row old-b 3 1 3 0 0)"
    summary_file new.json 1 1 "$models" "$(row race-a 3 1 3 0 0)" "$(row new-c 1 1 3 0 0)"
    run "$compare" base.json new.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"Only in base: old-b."* ]]
    [[ "$output" == *"Only in new: new-c."* ]]
}

@test "a run directory works in place of its summary" {
    summary_file base.json 1 1 "$models" "$(row race-a 3 1 3 0 0)"
    mkdir run && cp base.json run/summary.json
    run "$compare" base.json run
    [ "$status" -eq 0 ]
}
