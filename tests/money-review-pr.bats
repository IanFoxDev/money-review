#!/usr/bin/env bats

setup() {
    bin="$BATS_TEST_DIRNAME/../plugins/money-review/bin/money-review"
    reports="$BATS_TEST_DIRNAME/fixtures/reports"
    export MONEY_REVIEW_CLAUDE="$BATS_TEST_DIRNAME/fake/claude"
    export MONEY_REVIEW_GH="$BATS_TEST_DIRNAME/fake/gh"
    export FAKE_LOG="$BATS_TEST_TMPDIR/claude.args"
    export FAKE_REPORT="$reports/mixed.json"
    export FAKE_GH_DIR="$BATS_TEST_TMPDIR/gh"
    unset ANTHROPIC_API_KEY
    mkdir -p "$FAKE_GH_DIR"
    out="$BATS_TEST_TMPDIR/out"

    # origin has master and pull request 1 with one commit on top. Then master
    # moves on, so the tip of the base branch is not the merge base any more.
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
    git checkout -q -b payout
    printf '<?php\nfinal class Payout { public int $amount = 0; }\n' > app/Payout.php
    git add . && git commit -qm payout
    head1="$(git rev-parse HEAD)"
    git push -q origin "HEAD:refs/pull/1/head"
    git checkout -q master
    printf '<?php\nfinal class Invoice { public int $amount = 0; }\n' > app/Invoice.php
    git add . && git commit -qm invoice
    git push -q origin master
    tip="$(git rev-parse HEAD)"
    write_pr "$head1"
}

write_pr() {
    printf '{"number": 1, "html_url": "x", "head": {"ref": "payout", "sha": "%s"}, "base": {"ref": "master", "sha": "%s"}}' \
        "$1" "$tip" > "$FAKE_GH_DIR/pr.json"
}

@test "reviews the pull request against the merge base, not the base tip" {
    run "$bin" --pr 1 --out "$out"
    [ "$status" -eq 0 ]
    grep -q '^+final class Payout' "$out/change.diff"
    ! grep -q 'Invoice' "$out/change.diff"
    [ "$(cat "$FAKE_LOG.cwd")" = "$(cd "$out" && pwd)/worktree" ]
    [ ! -d "$out/worktree" ]
}

@test "--post comments on the pull request with the head commit" {
    run "$bin" --pr 1 --post --out "$out"
    [ "$status" -eq 0 ]
    grep -q '^POST repos/{owner}/{repo}/pulls/1/comments$' "$FAKE_GH_DIR/calls"
    grep -rq "money-review:summary sha=$head1" "$FAKE_GH_DIR/bodies"
}

@test "an already reviewed head does not start claude" {
    echo "[{\"id\": 5, \"updated_at\": \"2026-10-05T10:00:00Z\", \"body\": \"<!-- money-review:summary sha=$head1 -->\"}]" > "$FAKE_GH_DIR/issue_comments.json"
    run "$bin" --pr 1 --out "$out"
    [[ "$output" == *"#1 at ${head1:0:12} is already reviewed"* ]]
    [ ! -f "$FAKE_LOG" ]
}

@test "after a review only new commits are checked" {
    echo "[{\"id\": 5, \"updated_at\": \"2026-10-05T10:00:00Z\", \"body\": \"<!-- money-review:summary sha=$head1 -->\"}]" > "$FAKE_GH_DIR/issue_comments.json"
    git checkout -q payout
    printf '<?php\nfinal class Refund { public int $amount = 0; }\n' > app/Refund.php
    git add . && git commit -qm refund
    head2="$(git rev-parse HEAD)"
    git push -q origin "HEAD:refs/pull/1/head" --force
    git checkout -q master
    write_pr "$head2"
    run "$bin" --pr 1 --out "$out"
    [[ "$output" == *"#1, reviewing commits since ${head1:0:12}"* ]]
    grep -q '^+final class Refund' "$out/change.diff"
    ! grep -q 'Payout' "$out/change.diff"
}

@test "--mr and --pr together are a usage error" {
    run "$bin" --mr 1 --pr 1
    [ "$status" -eq 2 ]
    [[ "$output" == *"not both"* ]]
    run "$bin" --pr x
    [ "$status" -eq 2 ]
}
