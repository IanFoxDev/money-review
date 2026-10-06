#!/usr/bin/env bash
# PreToolUse hook: stops the money-review agents from opening files that may hold
# secrets, in every way the plugin is used (the /money-review command inside Claude
# Code cannot set deny rules for its session). Other agents and the main session are
# not touched. The patterns are "secrets" from the project's .money-review.json, or
# the plugin defaults.
#
# Input: the hook JSON on stdin. Output: a deny decision, or nothing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input="$(cat)"

case "$(jq -r '.agent_type // ""' <<< "$input")" in
    money-review:*) ;;
    *) exit 0 ;;
esac

cwd="$(jq -r '.cwd // ""' <<< "$input")"
root="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null || echo "${cwd:-$PWD}")"
patterns="$(jq -c '.secrets // []' "$here/../defaults/config.json")"
if [ -f "$root/.money-review.json" ]; then
    patterns="$(jq -c --argjson d "$patterns" '.secrets // $d' "$root/.money-review.json" 2>/dev/null || echo "$patterns")"
fi

is_secret() { # path relative to the root, or a glob -> 0 when a pattern matches it
    local p name="${1##*/}"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        # shellcheck disable=SC2254 # the patterns are globs on purpose
        case "$p" in
            */*) case "$1" in $p|*/$p) return 0 ;; esac ;;
            *) case "$name" in $p) return 0 ;; esac ;;
        esac
    done < <(jq -r '.[]' <<< "$patterns")
    return 1
}

# The path arguments of each tool (Grep's "pattern" is a regex, not a path).
args="$(jq -r '.tool_name as $t | .tool_input |
    if $t == "Read" then .file_path
    elif $t == "Grep" then (.path, .glob)
    else (.path, .pattern) end | select(type == "string")' <<< "$input")"

deny=""
while IFS= read -r arg; do
    [ -n "$arg" ] || continue
    if is_secret "${arg#"$root"/}"; then deny="$arg"; break; fi
done <<< "$args"

[ -n "$deny" ] || exit 0
jq -n --arg p "$deny" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
    permissionDecisionReason: "money-review does not read files that may hold secrets (\($p)); see secrets in .money-review.json"}}'
