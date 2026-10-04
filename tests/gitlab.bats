#!/usr/bin/env bats

setup() {
    gitlab="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/gitlab.sh"
    reports="$BATS_TEST_DIRNAME/fixtures/reports"
    export MONEY_REVIEW_GLAB="$BATS_TEST_DIRNAME/fake/glab"
    export FAKE_GLAB_DIR="$BATS_TEST_TMPDIR/glab"
    mkdir -p "$FAKE_GLAB_DIR"
    cat > "$FAKE_GLAB_DIR/mr.json" <<'JSON'
{"iid": 7, "web_url": "https://gitlab.example/shop/-/merge_requests/7",
 "source_branch": "payout", "target_branch": "master",
 "diff_refs": {"base_sha": "aaa111", "start_sha": "bbb222", "head_sha": "ccc333"}}
JSON
}

body() { jq -r .body "$FAKE_GLAB_DIR/bodies/$1.json"; }

@test "refs flattens diff_refs" {
    run "$gitlab" refs 7
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.head_sha, .base_sha, .start_sha, .target_branch]' <<< "$output")" = '["ccc333","aaa111","bbb222","master"]' ]
}

@test "last-reviewed reads the commit from the summary note" {
    printf '%s\n' \
        '{"id": 1, "body": "LGTM"}' \
        '{"id": 2, "body": "## money-review\n<!-- money-review:summary sha=0123abcd -->"}' \
        > "$FAKE_GLAB_DIR/notes.ndjson"
    run "$gitlab" last-reviewed 7
    [ "$output" = "0123abcd" ]
}

@test "last-reviewed is empty when the MR was never reviewed" {
    run "$gitlab" last-reviewed 7
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "post opens a discussion per finding and a summary note" {
    run "$gitlab" post 7 "$reports/mixed.json" ccc333
    [ "$status" -eq 0 ]
    [ "$(grep -c '^POST projects/:id/merge_requests/7/discussions$' "$FAKE_GLAB_DIR/calls")" -eq 2 ]
    grep -q '^POST projects/:id/merge_requests/7/notes$' "$FAKE_GLAB_DIR/calls"
    [ "$(jq -c '.position | [.new_path, .new_line, .head_sha, .base_sha]' "$FAKE_GLAB_DIR/bodies/1.json")" = '["app/WithdrawalService.php",4,"ccc333","aaa111"]' ]
    [[ "$(body 2)" == *"money-review HIGH RACE-1: Balance check and debit are not atomic"* ]]
    [[ "$(body 2)" == *"<!-- money-review:finding rule=RACE-1 file=app/WithdrawalService.php -->"* ]]
    [[ "$(body 3)" == *"<!-- money-review:summary sha=ccc333 -->"* ]]
    [[ "$output" == *"posted 2 comment(s), 0 already on the MR, 0 outside the diff"* ]]
}

@test "post updates the existing summary note" {
    echo '{"id": 42, "body": "old\n<!-- money-review:summary sha=0123abcd -->"}' > "$FAKE_GLAB_DIR/notes.ndjson"
    run "$gitlab" post 7 "$reports/empty.json" ccc333 0123abcd
    grep -q '^PUT projects/:id/merge_requests/7/notes/42$' "$FAKE_GLAB_DIR/calls"
    [[ "$(body 1)" == *'changes since `0123abcd`'* ]]
}

@test "post does not repeat a finding that already has a discussion" {
    echo '{"id": "x", "notes": [{"body": "earlier\n<!-- money-review:finding rule=RACE-1 file=app/WithdrawalService.php -->"}]}' \
        > "$FAKE_GLAB_DIR/discussions.ndjson"
    run "$gitlab" post 7 "$reports/mixed.json" ccc333
    [ "$(grep -c 'discussions$' "$FAKE_GLAB_DIR/calls")" -eq 1 ]
    [[ "$output" == *"posted 1 comment(s), 1 already on the MR"* ]]
}

@test "a finding outside the diff stays in the summary only" {
    jq '.findings[0].line = 999' "$reports/mixed.json" > "$BATS_TEST_TMPDIR/outside.json"
    run "$gitlab" post 7 "$BATS_TEST_TMPDIR/outside.json" ccc333
    [ "$status" -eq 0 ]
    [[ "$output" == *"posted 1 comment(s), 0 already on the MR, 1 outside the diff"* ]]
}
