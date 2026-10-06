#!/usr/bin/env bats

setup() {
    strip="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/strip-secrets.sh"
    defaults="$BATS_TEST_DIRNAME/../plugins/money-review/defaults/config.json"
    patterns="$(jq -c .secrets "$defaults")"
    cd "$BATS_TEST_TMPDIR"
    : > change.diff
    for f in app/Wallet.php .env config/server.pem deploy/secrets/db.yml .env.example app/KeyRing.php; do
        printf 'diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+CANARY %s\n' "$f" "$f" "$f" "$f" >> change.diff
    done
}

@test "files that may hold secrets leave the diff" {
    run "$strip" change.diff "$patterns"
    [ "$status" -eq 0 ]
    [ "$output" = '[".env","config/server.pem","deploy/secrets/db.yml",".env.example"]' ]
    [ "$(grep -c '^diff --git' change.diff)" = "2" ]
    grep -q '^+CANARY app/Wallet.php' change.diff
    grep -q '^+CANARY app/KeyRing.php' change.diff
    ! grep -q 'server.pem' change.diff
}

@test "a deleted secret file is matched by its old path" {
    printf 'diff --git a/.env b/.env\ndeleted file mode 100644\n--- a/.env\n+++ /dev/null\n@@ -1 +0,0 @@\n-CANARY gone\n' > change.diff
    run "$strip" change.diff "$patterns"
    [ "$output" = '[".env"]' ]
    [ ! -s change.diff ]
}

@test "a diff without secrets stays as it is" {
    printf 'diff --git a/app/A.php b/app/A.php\n--- a/app/A.php\n+++ b/app/A.php\n@@ -1 +1 @@\n-a\n+b\n' > change.diff
    cp change.diff before.diff
    run "$strip" change.diff "$patterns"
    [ "$output" = "[]" ]
    cmp change.diff before.diff
}

@test "an empty pattern list keeps everything" {
    run "$strip" change.diff '[]'
    [ "$output" = "[]" ]
    [ "$(grep -c '^diff --git' change.diff)" = "6" ]
}
