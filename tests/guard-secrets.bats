#!/usr/bin/env bats

setup() {
    guard="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/guard-secrets.sh"
    repo="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
}

# agent tool tool_input-json -> prints the decision: deny or allow
decide() {
    local out
    out="$(jq -nc --arg a "$1" --arg t "$2" --argjson i "$3" --arg c "$repo" \
        '{agent_type: $a, tool_name: $t, tool_input: $i, cwd: $c} | if $a == "" then del(.agent_type) else . end' | "$guard")"
    if [ -n "$out" ]; then jq -r .hookSpecificOutput.permissionDecision <<< "$out"; else echo allow; fi
}

@test "the review agents cannot read .env or keys" {
    [ "$(decide money-review:money-reviewer Read "{\"file_path\": \"$repo/.env\"}")" = deny ]
    [ "$(decide money-review:money-verifier Read "{\"file_path\": \"$repo/config/server.pem\"}")" = deny ]
    [ "$(decide money-review:money-reviewer Read "{\"file_path\": \"$repo/deploy/secrets/db.yml\"}")" = deny ]
}

@test "the review agents can read code" {
    [ "$(decide money-review:money-reviewer Read "{\"file_path\": \"$repo/app/KeyRing.php\"}")" = allow ]
}

@test "searches aimed at secrets are denied, a regex is not a path" {
    [ "$(decide money-review:money-reviewer Grep "{\"pattern\": \"FEE\", \"path\": \"$repo/.env\"}")" = deny ]
    [ "$(decide money-review:money-reviewer Grep '{"pattern": "x", "glob": "*.pem"}')" = deny ]
    [ "$(decide money-review:money-verifier Glob '{"pattern": "**/.env.*"}')" = deny ]
    [ "$(decide money-review:money-reviewer Grep '{"pattern": ".env"}')" = allow ]
}

@test "other agents and the main session are not touched" {
    [ "$(decide general-purpose Read "{\"file_path\": \"$repo/.env\"}")" = allow ]
    [ "$(decide "" Read "{\"file_path\": \"$repo/.env\"}")" = allow ]
}

@test "the project config replaces the patterns" {
    echo '{"secrets": ["*.vault"]}' > "$repo/.money-review.json"
    [ "$(decide money-review:money-reviewer Read "{\"file_path\": \"$repo/prod.vault\"}")" = deny ]
    [ "$(decide money-review:money-reviewer Read "{\"file_path\": \"$repo/.env\"}")" = allow ]
}

@test "the reason names the file and the setting" {
    out="$(jq -nc --arg r "$repo" '{agent_type: "money-review:money-reviewer", tool_name: "Read", tool_input: {file_path: ($r + "/.env")}, cwd: $r}' | "$guard")"
    [[ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<< "$out")" == *"/.env"*"secrets"* ]]
}
