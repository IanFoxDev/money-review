#!/usr/bin/env bash
# Moves findings the team has accepted from "findings" to "suppressed", without a
# model. Two ways to accept one:
#
#   a comment on the finding's line or the line above it, with the rule (or a whole
#   category) and a reason:
#       // money-review: ignore RACE-1 balance is locked by the caller
#       # money-review: ignore IDEM-3,TX-2 replayed by the nightly job, see OPS-12
#
#   an "ignore" entry in the config, for a rule in files that match a glob:
#       {"ignore": [{"rule": "MONEY-1", "path": "src/Reports/*", "reason": "..."}]}
#
# A comment or an entry without a reason is not applied: the finding stays and a
# warning goes to stderr. Run in the repository root, after fix-lines.sh.
#
# Usage: suppress.sh REPORT [PREPARED_JSON]      (edits REPORT)
set -euo pipefail

report="${1:?usage: suppress.sh REPORT [PREPARED_JSON]}"
prepared="${2:-}"

ignore="[]"
if [ -n "$prepared" ] && [ -f "$prepared" ]; then
    ignore="$(jq -c '.ignore // []' "$prepared")"
fi

rule_matches() { # list rule -> 0 when the comma-separated list names the rule or its category
    local item
    local IFS=,
    for item in $1; do
        if [ "$item" = "$2" ] || [ "$item" = "${2%%-*}" ]; then return 0; fi
    done
    return 1
}

# Prints "RULES<TAB>REASON" for an ignore comment on the line or the line above it.
comment_on() { # file line
    local from=$(( $2 > 1 ? $2 - 1 : 1 ))
    sed -n "${from},${2}p" "$1" | awk '
        match($0, /money-review: *ignore +[A-Z][A-Z0-9,-]*/) {
            head = substr($0, RSTART, RLENGTH)
            rest = substr($0, RSTART + RLENGTH)
            sub(/^.*ignore +/, "", head)
            sub(/[[:space:]]*(\*\/|-->)[[:space:]]*$/, "", rest)
            gsub(/^[[:space:]:-]+|[[:space:]]+$/, "", rest)
            print head "\t" rest
        }'
}

count="$(jq '.findings | length' "$report")"
kept="[]"
suppressed="$(jq -c '.suppressed // []' "$report")"
i=0
while [ "$i" -lt "$count" ]; do
    finding="$(jq -c ".findings[$i]" "$report")"
    i=$((i + 1))
    rule="$(jq -r .rule <<< "$finding")"
    file="$(jq -r .file <<< "$finding")"
    line="$(jq -r .line <<< "$finding")"
    by=""
    reason=""

    if [ -f "$file" ]; then
        while IFS="$(printf '\t')" read -r rules why; do
            [ -n "$rules" ] || continue
            rule_matches "$rules" "$rule" || continue
            if [ -z "$why" ]; then
                echo "money-review: ignore comment at $file:$line has no reason, $rule is kept" >&2
                continue
            fi
            by="comment"
            reason="$why"
            break
        done < <(comment_on "$file" "$line")
    fi

    if [ -z "$by" ]; then
        n="$(jq length <<< "$ignore")"
        j=0
        while [ "$j" -lt "$n" ]; do
            entry="$(jq -c ".[$j]" <<< "$ignore")"
            j=$((j + 1))
            rule_matches "$(jq -r '.rule // ""' <<< "$entry")" "$rule" || continue
            glob="$(jq -r '.path // "*"' <<< "$entry")"
            # shellcheck disable=SC2254 # the glob comes from the config on purpose
            case "$file" in $glob) ;; *) continue ;; esac
            why="$(jq -r '.reason // ""' <<< "$entry")"
            if [ -z "${why// /}" ]; then
                echo "money-review: ignore entry for $rule in $glob has no reason, it is not applied" >&2
                continue
            fi
            by="config"
            reason="$why"
            break
        done
    fi

    if [ -n "$by" ]; then
        suppressed="$(jq -c --argjson f "$finding" --arg by "$by" --arg r "$reason" \
            '. + [{rule: $f.rule, severity: $f.severity, file: $f.file, line: $f.line, title: $f.title, by: $by, reason: $r}]' <<< "$suppressed")"
    else
        kept="$(jq -c --argjson f "$finding" '. + [$f]' <<< "$kept")"
    fi
done

jq --argjson k "$kept" --argjson s "$suppressed" \
    '.findings = $k | if ($s | length) > 0 then .suppressed = $s else del(.suppressed) end' \
    "$report" > "$report.tmp"
mv "$report.tmp" "$report"
