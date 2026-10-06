#!/usr/bin/env bats

setup() {
    fix="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/fix-lines.sh"
    cd "$BATS_TEST_TMPDIR"
    mkdir -p app
    printf '%s\n' '<?php' 'final class Fee' '{' '    public function x() {}' '}' > app/Fee.php
    cat > change.diff <<'DIFF'
diff --git a/app/Fee.php b/app/Fee.php
--- a/app/Fee.php
+++ b/app/Fee.php
@@ -1,3 +1,5 @@
 <?php
 final class Fee
+{
+    public function x() {}
 }
DIFF
}

report() { # line
    jq -n --argjson l "$1" '{findings: [{rule: "MONEY-1", severity: "high", file: "app/Fee.php", line: $l,
        title: "t", scenario: "s", fix: "f"}], rejected: []}' > report.json
}

@test "a line inside the file stays" {
    report 4
    run "$fix" report.json change.diff
    [ "$status" -eq 0 ]
    [ "$(jq '.findings[0].line' report.json)" = "4" ]
    [ -z "$output" ]
}

@test "a line past the end moves to the first added line" {
    report 33
    run "$fix" report.json change.diff
    [ "$(jq '.findings[0].line' report.json)" = "3" ]
    [[ "$output" == *"app/Fee.php has no line 33, moved the finding to line 3"* ]]
}

@test "line zero moves too" {
    report 0
    run "$fix" report.json change.diff
    [ "$(jq '.findings[0].line' report.json)" = "3" ]
}

@test "without added lines in the diff it moves to the last line" {
    report 99
    printf 'diff --git a/x b/x\n' > empty.diff
    run "$fix" report.json empty.diff
    [ "$(jq '.findings[0].line' report.json)" = "5" ]
}

@test "a file that is not in the repository is left alone" {
    jq '.findings[0].file = "app/Gone.php" | .findings[0].line = 500' <<< '{"findings":[{"file":"","line":1}],"rejected":[]}' > report.json
    run "$fix" report.json change.diff
    [ "$(jq '.findings[0].line' report.json)" = "500" ]
}

@test "finish attaches the coverage from prepare" {
    finish="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/finish.sh"
    report 4
    echo '{"coverage": {"files_changed": 3, "files_with_money": 1, "files_reviewed": 1, "groups": 1, "not_reviewed": []}}' > prepared.json
    run "$finish" report.json change.diff prepared.json
    [ "$status" -eq 0 ]
    [ "$(jq -c '.coverage.files_changed' report.json)" = "3" ]
    [ "$(jq '.findings[0].line' report.json)" = "4" ]
}

with_code() { # line code
    jq -n --argjson l "$1" --arg c "$2" '{findings: [{rule: "MONEY-1", severity: "high", file: "app/Fee.php", line: $l,
        code: $c, title: "t", scenario: "s", fix: "f"}], rejected: []}' > report.json
}

@test "a finding moves to the line that holds its code" {
    with_code 1 "public function x() {}"
    run "$fix" report.json change.diff
    [ "$status" -eq 0 ]
    [ "$(jq '.findings[0].line' report.json)" = "4" ]
    [[ "$output" == *"app/Fee.php:1 does not hold the code of the finding, moved it to line 4"* ]]
}

@test "a finding whose line holds its code stays" {
    with_code 4 "    public function x() {}  "
    run "$fix" report.json change.diff
    [ "$(jq '.findings[0].line' report.json)" = "4" ]
    [ -z "$output" ]
}

@test "of several matching lines the nearest wins" {
    printf '%s\n' '<?php' '{' 'x' '{' 'y' '{' > app/Fee.php
    with_code 5 "{"
    run "$fix" report.json change.diff
    [ "$(jq '.findings[0].line' report.json)" = "4" ]
}

@test "code that is not in the file leaves the line to the other checks" {
    with_code 40 "removed()"
    run "$fix" report.json change.diff
    [ "$(jq '.findings[0].line' report.json)" = "3" ]
}

@test "code with backslashes is matched as plain text" {
    printf '%s\n' '<?php' 'use App\Models\Account;' 'final class Fee {}' > app/Fee.php
    with_code 1 'use App\Models\Account;'
    run "$fix" report.json change.diff
    [ "$(jq '.findings[0].line' report.json)" = "2" ]
}
