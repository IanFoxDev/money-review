#!/usr/bin/env bats

setup() {
    prepare="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/prepare.sh"
    diffs="$BATS_TEST_DIRNAME/fixtures/diffs"
    repo="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$repo/app"
    cd "$repo"
    git init -q -b master
    git config user.name test
    git config user.email test@example.com
    printf '<?php\nfinal class Wallet {}\n' > app/Wallet.php
    git add . && git commit -qm init
}

field() { jq -c "$1" <<< "$output"; }

@test "a given diff is copied and triaged" {
    run "$prepare" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "true" ]
    [ "$(field .diff)" = "\"$BATS_TEST_TMPDIR/out/change.diff\"" ]
    cmp "$diffs/withdrawal.diff" "$BATS_TEST_TMPDIR/out/change.diff"
}

@test "checklists point at existing files, one per category" {
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field '.checklists | length')" = "4" ]
    for f in $(jq -r '.checklists[]' <<< "$output"); do
        [ -f "$f" ]
    done
}

@test "no money means no checklists" {
    run "$prepare" --diff "$diffs/readme-only.diff"
    [ "$(field .money)" = "false" ]
    [ "$(field .checklists)" = "[]" ]
}

@test "uncommitted edits against master are reviewed" {
    printf '<?php\nfinal class Wallet { public int $balance = 0; }\n' > app/Wallet.php
    run "$prepare"
    [ "$status" -eq 0 ]
    [ "$(field .base)" = '"master"' ]
    [ "$(field .files)" = '["app/Wallet.php"]' ]
}

@test "commits on a branch are reviewed against the merge base" {
    git checkout -q -b feature
    printf '<?php\nfinal class Payout { public int $amount = 0; }\n' > app/Payout.php
    git add . && git commit -qm payout
    run "$prepare"
    [ "$(field .files)" = '["app/Payout.php"]' ]
}

@test "new untracked files are reviewed" {
    printf '<?php\nfinal class Refund { public int $amount = 0; }\n' > app/Refund.php
    run "$prepare"
    [ "$(field .files)" = '["app/Refund.php"]' ]
}

@test "the project config is picked up from the repository root" {
    printf '{"money_paths": ["app/Wallet.php"], "context": "cents everywhere"}' > .money-review.json
    git add . && git commit -qm config
    printf '<?php\nfinal class Wallet { public function x() {} }\n' > app/Wallet.php
    run "$prepare"
    [ "$(field .money)" = "true" ]
    [ "$(field .context)" = '"cents everywhere"' ]
}

@test "an explicit base is used" {
    git checkout -q -b feature
    run "$prepare" --base feature
    [ "$(field .base)" = '"feature"' ]
}

@test "no base branch is an error" {
    git branch -m master trunk
    run "$prepare"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no base branch found"* ]]
}

@test "a diff that already sits in the output directory is used in place" {
    mkdir -p "$BATS_TEST_TMPDIR/out"
    cp "$diffs/withdrawal.diff" "$BATS_TEST_TMPDIR/out/change.diff"
    run "$prepare" --diff "$BATS_TEST_TMPDIR/out/change.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(field .money)" = "true" ]
}

@test "a large change is split into groups with coverage" {
    load helpers
    make_diff "$BATS_TEST_TMPDIR/big.diff" app/Wallet/A.php:500 app/Wallet/B.php:500 docs/x.md:5
    run "$prepare" --diff "$BATS_TEST_TMPDIR/big.diff" --out "$BATS_TEST_TMPDIR/out"
    echo "$output" | head -n 20 # shown by bats only when the test fails
    [ "$status" -eq 0 ]
    [ "$(field '.groups | length')" = "2" ]
    [ "$(field '.coverage')" = '{"files_changed":3,"files_with_money":2,"files_reviewed":2,"groups":2,"not_reviewed":[],"secrets_excluded":[]}' ]
    [ -f "$BATS_TEST_TMPDIR/out/prepared.json" ]
    [ -f "$(jq -r '.groups[1].diff' <<< "$output")" ]
}

@test "a small change is one group with the whole diff" {
    run "$prepare" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$(field '.groups | length')" = "1" ]
    [ "$(field '.groups[0].diff')" = "\"$BATS_TEST_TMPDIR/out/change.diff\"" ]
}

@test "groups over max_groups are listed as not reviewed" {
    load helpers
    make_diff "$BATS_TEST_TMPDIR/big.diff" a.php:50 b.php:50 c.php:50
    printf '{"review": {"group_lines": 60, "max_groups": 2}}' > "$BATS_TEST_TMPDIR/cfg.json"
    run "$prepare" --diff "$BATS_TEST_TMPDIR/big.diff" --config "$BATS_TEST_TMPDIR/cfg.json" --out "$BATS_TEST_TMPDIR/out"
    [ "$(field '.groups | length')" = "2" ]
    [ "$(field '.coverage.files_reviewed')" = "2" ]
    [ "$(field '.coverage.not_reviewed | length')" = "1" ]
}

@test "ignore entries from the config are passed on" {
    echo '{"ignore": [{"rule": "RACE-1", "reason": "one worker"}]}' > .money-review.json
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field '.ignore[0].rule')" = '"RACE-1"' ]
}

@test "no config means nothing is ignored" {
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field .ignore)" = '[]' ]
}

@test "a changed .env is cut from the diff and listed" {
    printf '<?php\nfinal class Wallet { public int $balance = 0; }\n' > app/Wallet.php
    printf 'DB_PASSWORD=CANARY\n' > .env
    run "$prepare" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(field .coverage.secrets_excluded)" = '[".env"]' ]
    ! grep -q CANARY "$BATS_TEST_TMPDIR/out/change.diff"
    [ "$(field '.secrets | index(".env")')" = "0" ]
}

@test "the config can replace the secret patterns" {
    echo '{"secrets": ["*.vault"]}' > .money-review.json
    printf 'x\n' > prod.vault
    run "$prepare"
    [ "$(field .secrets)" = '["*.vault"]' ]
    [ "$(field .coverage.secrets_excluded)" = '["prod.vault"]' ]
}

@test "files cut as secrets stay listed when the same diff is prepared again" {
    printf '<?php\nfinal class Wallet { public int $balance = 0; }\n' > app/Wallet.php
    printf 'DB_PASSWORD=CANARY\n' > .env
    "$prepare" --out "$BATS_TEST_TMPDIR/out" > /dev/null
    run "$prepare" --diff "$BATS_TEST_TMPDIR/out/change.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$(field .coverage.secrets_excluded)" = '[".env"]' ]
}

@test "the second look is on by default and can be turned off" {
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field .second_pass)" = "true" ]
    echo '{"review": {"second_pass": false}}' > .money-review.json
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$(field .second_pass)" = "false" ]
}

@test "the checklists of a group come as one file with every rule" {
    run "$prepare" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    f="$(jq -r '.groups[0].checklist' <<< "$output")"
    [ -f "$f" ]
    for c in $(jq -r '.groups[0].checklists[]' <<< "$output"); do
        grep -qF "$(head -1 "$c")" "$f"
    done
    [ "$(grep -c '^## [A-Z]*-[0-9]' "$f")" = "$(cat $(jq -r '.groups[0].checklists[]' <<< "$output") | grep -c '^## [A-Z]*-[0-9]')" ]
    [ -f "$(jq -r '.checklist' <<< "$output")" ]
}

@test "no money, no checklist file" {
    run "$prepare" --diff "$diffs/readme-only.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$(jq -r '.checklist' <<< "$output")" = "" ]
}

@test "a private rule file is resolved next to the config and joins the checklist" {
    mkdir -p "$BATS_TEST_TMPDIR/private/rules"
    printf '# Acme (ACME)\n\n## ACME-1. Plan cycle must match\n' > "$BATS_TEST_TMPDIR/private/rules/acme.md"
    echo '{"rules": [{"prefix": "ACME", "file": "rules/acme.md"}]}' > "$BATS_TEST_TMPDIR/private/config.json"
    run "$prepare" --diff "$diffs/withdrawal.diff" --config "$BATS_TEST_TMPDIR/private/config.json" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(field '.checklists | map(select(endswith("/private/rules/acme.md"))) | length')" = "1" ]
    grep -q '^## ACME-1\.' "$(jq -r '.groups[0].checklist' <<< "$output")"
}

@test "a missing private rule file is an error" {
    echo '{"rules": [{"prefix": "ACME", "file": "nowhere.md"}]}' > .money-review.json
    run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read rule file"* ]]
}

@test "invariants become a numbered checklist for every group" {
    echo '{"invariants": ["A user has at most one active subscription", "A refund never exceeds its payment"]}' > .money-review.json
    run "$prepare" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/out/invariants.md" ]
    grep -q '^## INV-2\. A refund never exceeds its payment$' "$BATS_TEST_TMPDIR/out/invariants.md"
    grep -q '^## INV-1\.' "$(jq -r '.groups[0].checklist' <<< "$output")"
}

@test "no money, no invariants" {
    echo '{"invariants": ["A user has at most one active subscription"]}' > .money-review.json
    run "$prepare" --diff "$diffs/readme-only.diff"
    [ "$(field .checklists)" = "[]" ]
}

@test "a private config adds its rules and invariants to the project's" {
    mkdir -p "$BATS_TEST_TMPDIR/private/rules" rules
    printf '# Acme (ACME)\n\n## ACME-1. One\n' > "$BATS_TEST_TMPDIR/private/rules/acme.md"
    printf '# Team (TEAM)\n\n## TEAM-1. Two\n' > rules/team.md
    echo '{"rules": [{"prefix": "TEAM", "file": "rules/team.md"}], "invariants": ["project one"], "context": "project"}' > .money-review.json
    echo '{"rules": [{"prefix": "ACME", "file": "rules/acme.md"}], "invariants": ["private one"], "context": "private"}' > "$BATS_TEST_TMPDIR/private/config.json"
    MONEY_REVIEW_PRIVATE="$BATS_TEST_TMPDIR/private" run "$prepare" --diff "$diffs/withdrawal.diff" --out "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(field .private_config)" = "\"$BATS_TEST_TMPDIR/private/config.json\"" ]
    [ "$(field .context)" = '"private"' ]
    f="$(jq -r '.groups[0].checklist' <<< "$output")"
    grep -q '^## ACME-1\.' "$f"
    grep -q '^## TEAM-1\.' "$f"
    grep -q '^## INV-1\. project one$' "$f"
    grep -q '^## INV-2\. private one$' "$f"
}

@test "no private config, nothing changes" {
    MONEY_REVIEW_PRIVATE="$BATS_TEST_TMPDIR/none" run "$prepare" --diff "$diffs/withdrawal.diff"
    [ "$status" -eq 0 ]
    [ "$(field .private_config)" = '""' ]
}

@test "the private folder of the plugin is ignored by git" {
    cd "$BATS_TEST_DIRNAME/.."
    git check-ignore -q plugins/money-review/private/any-repo/config.json
    ! git check-ignore -q plugins/money-review/private.example/README.md
}
