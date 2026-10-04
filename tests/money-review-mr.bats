#!/usr/bin/env bats

setup() {
    bin="$BATS_TEST_DIRNAME/../plugins/money-review/bin/money-review"
    reports="$BATS_TEST_DIRNAME/fixtures/reports"
    export MONEY_REVIEW_CLAUDE="$BATS_TEST_DIRNAME/fake/claude"
    export MONEY_REVIEW_GLAB="$BATS_TEST_DIRNAME/fake/glab"
    export FAKE_LOG="$BATS_TEST_TMPDIR/claude.args"
    export FAKE_REPORT="$reports/mixed.json"
    export FAKE_GLAB_DIR="$BATS_TEST_TMPDIR/glab"
    unset ANTHROPIC_API_KEY
    mkdir -p "$FAKE_GLAB_DIR"
    out="$BATS_TEST_TMPDIR/out"

    # origin has master and merge request 1 with one commit on top.
    git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
    repo="$BATS_TEST_TMPDIR/repo"
    git init -q -b master "$repo"
    cd "$repo"
    git config user.name test
    git config user.email test@example.com
    git remote add origin "$BATS_TEST_TMPDIR/origin.git"
    mkdir app
    printf '<?php\nfinal class Wallet {}\n' > app/Wallet.php
    git add . && git commit -qm init
    git push -q origin master
    base_sha="$(git rev-parse HEAD)"
    git checkout -q -b payout
    printf '<?php\nfinal class Payout { public int $amount = 0; }\n' > app/Payout.php
    git add . && git commit -qm payout
    head1="$(git rev-parse HEAD)"
    git push -q origin "HEAD:refs/merge-requests/1/head"
    git checkout -q master
    write_mr "$head1"
}

write_mr() {
    printf '{"iid": 1, "web_url": "x", "source_branch": "payout", "target_branch": "master", "diff_refs": {"base_sha": "%s", "start_sha": "%s", "head_sha": "%s"}}' \
        "$base_sha" "$base_sha" "$1" > "$FAKE_GLAB_DIR/mr.json"
}

@test "reviews the merge request in a worktree at its head" {
    run "$bin" --mr 1 --out "$out"
    [ "$status" -eq 0 ]
    [ "$(cat "$FAKE_LOG.cwd")" = "$(cd "$out" && pwd)/worktree" ]
    grep -q '^+final class Payout' "$out/change.diff"
    [ ! -d "$out/worktree" ]
    [ "$(git -C "$repo" branch --show-current)" = "master" ]
}

@test "does not post without --post" {
    run "$bin" --mr 1 --out "$out"
    ! grep -q '^POST' "$FAKE_GLAB_DIR/calls"
}

@test "--post comments on the merge request with the head commit" {
    run "$bin" --mr 1 --post --out "$out"
    [ "$status" -eq 0 ]
    grep -q '^POST projects/:id/merge_requests/1/discussions$' "$FAKE_GLAB_DIR/calls"
    grep -rq "money-review:summary sha=$head1" "$FAKE_GLAB_DIR/bodies"
}

@test "an already reviewed head does not start claude" {
    echo "{\"id\": 5, \"body\": \"<!-- money-review:summary sha=$head1 -->\"}" > "$FAKE_GLAB_DIR/notes.ndjson"
    run "$bin" --mr 1 --out "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already reviewed"* ]]
    [ ! -f "$FAKE_LOG" ]
}

@test "--full reviews an already reviewed head again" {
    echo "{\"id\": 5, \"body\": \"<!-- money-review:summary sha=$head1 -->\"}" > "$FAKE_GLAB_DIR/notes.ndjson"
    run "$bin" --mr 1 --full --out "$out"
    [ -f "$FAKE_LOG" ]
}

@test "after a review only new commits are checked" {
    echo "{\"id\": 5, \"body\": \"<!-- money-review:summary sha=$head1 -->\"}" > "$FAKE_GLAB_DIR/notes.ndjson"
    git checkout -q payout
    printf '<?php\nfinal class Refund { public int $amount = 0; }\n' > app/Refund.php
    git add . && git commit -qm refund
    head2="$(git rev-parse HEAD)"
    git push -q origin "HEAD:refs/merge-requests/1/head" --force
    git checkout -q master
    write_mr "$head2"
    run "$bin" --mr 1 --out "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"reviewing commits since ${head1:0:12}"* ]]
    grep -q '^+final class Refund' "$out/change.diff"
    ! grep -q 'Payout' "$out/change.diff"
}

@test "a merge request without money does not start claude" {
    git checkout -q payout
    printf 'docs\n' > README.md
    git add . && git commit -qm docs
    git push -q origin "HEAD:refs/merge-requests/2/head"
    head_docs="$(git rev-parse HEAD)"
    git checkout -q master
    printf '{"iid": 2, "web_url": "x", "source_branch": "docs", "target_branch": "master", "diff_refs": {"base_sha": "%s", "start_sha": "%s", "head_sha": "%s"}}' \
        "$head1" "$head1" "$head_docs" > "$FAKE_GLAB_DIR/mr.json"
    run "$bin" --mr 2 --post --out "$out"
    [[ "$output" == *"no money-related changes"* ]]
    [ ! -f "$FAKE_LOG" ]
    ! grep -q '^POST' "$FAKE_GLAB_DIR/calls"
}

@test "--post and --full need --mr, --mr takes a number" {
    run "$bin" --post
    [ "$status" -eq 2 ]
    run "$bin" --mr abc
    [ "$status" -eq 2 ]
    run "$bin" --mr 1 --base master
    [ "$status" -eq 2 ]
}
