#!/usr/bin/env bats

setup() {
    github="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/github.sh"
    reports="$BATS_TEST_DIRNAME/fixtures/reports"
    export MONEY_REVIEW_GH="$BATS_TEST_DIRNAME/fake/gh"
    export FAKE_GH_DIR="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$FAKE_GH_DIR"
    cat > "$FAKE_GH_DIR/pr.json" <<'JSON'
{"number": 7, "html_url": "https://github.com/acme/shop/pull/7",
 "head": {"ref": "payout", "sha": "ccc333"}, "base": {"ref": "master", "sha": "aaa111"}}
JSON
}

body() { jq -r .body "$FAKE_GH_DIR/bodies/$1.json"; }

@test "refs maps the pull request to the common shape" {
    run "$github" refs 7
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.iid, .head_sha, .base_sha, .target_branch, .fetch_ref]' <<< "$output")" = '[7,"ccc333","aaa111","master","refs/pull/7/head"]' ]
}

@test "last-reviewed reads the newest summary comment" {
    cat > "$FAKE_GH_DIR/issue_comments.json" <<'JSON'
[{"id": 1, "updated_at": "2026-10-05T10:00:00Z", "body": "LGTM"},
 {"id": 2, "updated_at": "2026-10-05T11:00:00Z", "body": "x\n<!-- money-review:summary sha=0123abcd -->"}]
JSON
    run "$github" last-reviewed 7
    [ "$output" = "0123abcd" ]
}

@test "last-reviewed is empty when the PR was never reviewed" {
    run "$github" last-reviewed 7
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "post adds a review comment per finding and a summary comment" {
    run "$github" post 7 "$reports/mixed.json" ccc333
    [ "$status" -eq 0 ]
    [ "$(grep -c '^POST repos/{owner}/{repo}/pulls/7/comments$' "$FAKE_GH_DIR/calls")" -eq 2 ]
    grep -q '^POST repos/{owner}/{repo}/issues/7/comments$' "$FAKE_GH_DIR/calls"
    [ "$(jq -c '[.path, .line, .side, .commit_id]' "$FAKE_GH_DIR/bodies/1.json")" = '["app/WithdrawalService.php",4,"RIGHT","ccc333"]' ]
    [[ "$(body 2)" == *"money-review HIGH RACE-1: Balance check and debit are not atomic"* ]]
    [[ "$(body 2)" == *"<!-- money-review:finding rule=RACE-1 file=app/WithdrawalService.php -->"* ]]
    [[ "$(body 3)" == *"<!-- money-review:summary sha=ccc333 -->"* ]]
    [[ "$output" == *"posted 2 comment(s), 0 already on the PR, 0 outside the diff"* ]]
}

@test "post edits the existing summary comment" {
    echo '[{"id": 42, "updated_at": "2026-10-05T11:00:00Z", "body": "old\n<!-- money-review:summary sha=0123abcd -->"}]' > "$FAKE_GH_DIR/issue_comments.json"
    run "$github" post 7 "$reports/empty.json" ccc333 0123abcd
    grep -q '^PATCH repos/{owner}/{repo}/issues/comments/42$' "$FAKE_GH_DIR/calls"
    [[ "$(body 1)" == *'changes since `0123abcd`'* ]]
}

@test "post does not repeat a finding that already has a review comment" {
    echo '[{"id": 5, "body": "earlier\n<!-- money-review:finding rule=RACE-1 file=app/WithdrawalService.php -->"}]' > "$FAKE_GH_DIR/review_comments.json"
    run "$github" post 7 "$reports/mixed.json" ccc333
    [ "$(grep -c '^POST repos/{owner}/{repo}/pulls/7/comments$' "$FAKE_GH_DIR/calls")" -eq 1 ]
    [[ "$output" == *"posted 1 comment(s), 1 already on the PR"* ]]
}

@test "a finding outside the diff stays in the summary only" {
    jq '.findings[0].line = 999' "$reports/mixed.json" > "$BATS_TEST_TMPDIR/outside.json"
    run "$github" post 7 "$BATS_TEST_TMPDIR/outside.json" ccc333
    [ "$status" -eq 0 ]
    [[ "$output" == *"posted 1 comment(s), 0 already on the PR, 1 outside the diff"* ]]
}
