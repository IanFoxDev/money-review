#!/usr/bin/env bash
# Decides without a model whether a diff touches money and which checklist
# categories apply. Prints JSON:
#   {"money": true, "categories": ["IDEM","TX"], "files": [...], "reasons": [...]}
#
# Usage: triage.sh [--config FILE] [DIFF_FILE]   (diff from stdin if no file)
#
# A file is in scope when it passes paths.include/exclude and either matches
# money_paths or its changed lines (with hunk context) or its path match
# "signals", in any letter case (Go fields are Amount and Balance).
# Categories are matched only in files that are in scope. Patterns are
# extended regular expressions; in path globs "*" also matches "/".
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
defaults="$here/../defaults/config.json"
config=""
diff_file=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config) config="${2:?--config needs a file}"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "triage: unknown option $1" >&2; exit 2 ;;
        *) diff_file="$1"; shift ;;
    esac
done

command -v jq >/dev/null || { echo "triage: jq is required" >&2; exit 2; }

if [ -n "$config" ]; then
    [ -r "$config" ] || { echo "triage: cannot read $config" >&2; exit 2; }
    cfg="$(jq -s '.[0] * .[1]' "$defaults" "$config")"
else
    cfg="$(cat "$defaults")"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Split the diff into one text file per changed path: added, removed and
# context lines without the leading marker. paths.txt keeps the order.
if [ -n "$diff_file" ]; then cat "$diff_file"; else cat; fi | awk -v dir="$work" '
    /^diff --git / { n++; path = ""; inhunk = 0; next }
    /^--- / && !inhunk { old = substr($0, 5); sub(/^a\//, "", old); next }
    /^\+\+\+ / && !inhunk {
        p = substr($0, 5); sub(/^b\//, "", p)
        if (p == "/dev/null") p = old
        path = p; print path > (dir "/paths.txt"); next
    }
    /^@@/ { inhunk = 1; next }
    inhunk && path != "" && /^[-+ ]/ { print substr($0, 2) > (dir "/" n ".txt"); next }
'

touch "$work/paths.txt"

matches_glob() { # path, newline separated globs
    local path="$1" glob
    while IFS= read -r glob; do
        [ -z "$glob" ] && continue
        # shellcheck disable=SC2053 # glob match is intended
        [[ "$path" == $glob ]] && return 0
    done <<< "$2"
    return 1
}

includes="$(jq -r '.paths.include[]?' <<< "$cfg")"
excludes="$(jq -r '.paths.exclude[]?' <<< "$cfg")"
money_paths="$(jq -r '.money_paths[]?' <<< "$cfg")"
signals="$(jq -r '.signals // ""' <<< "$cfg")"
categories="$(jq -r '.categories | keys[]' <<< "$cfg")"

reasons="[]"
found_cats=""
i=0
while IFS= read -r path; do
    i=$((i + 1))
    blob="$work/$i.txt"
    [ -f "$blob" ] || continue
    matches_glob "$path" "$includes" || continue
    if matches_glob "$path" "$excludes"; then continue; fi

    if matches_glob "$path" "$money_paths"; then
        why="money_paths"
    elif [ -n "$signals" ] && grep -Eiq -- "$signals" "$blob"; then
        why="signals"
    elif [ -n "$signals" ] && printf '%s\n' "$path" | grep -Eiq -- "$signals"; then
        why="path"
    else
        continue
    fi

    for cat in $categories; do
        pattern="$(jq -r --arg c "$cat" '.categories[$c]' <<< "$cfg")"
        if [ "$why" = "money_paths" ] || grep -Eq -- "$pattern" "$blob"; then
            hit="$(grep -Eo -- "$pattern" "$blob" | head -n 1 || true)"
            reasons="$(jq -c --arg f "$path" --arg c "$cat" --arg w "$why" --arg h "$hit" \
                '. + [{file: $f, category: $c, scope: $w, match: $h}]' <<< "$reasons")"
            found_cats="$found_cats $cat"
        fi
    done
done < "$work/paths.txt"

jq -n \
    --argjson reasons "$reasons" \
    --arg cats "$found_cats" \
    --arg context "$(jq -r '.context // ""' <<< "$cfg")" \
    '($cats | split(" ") | map(select(. != "")) | unique) as $c
     | {money: ($c | length > 0), categories: $c,
        files: ($reasons | map(.file) | unique), reasons: $reasons, context: $context}'
