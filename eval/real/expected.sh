#!/usr/bin/env bash
# Prints the expected findings of the given real-bug cases as one JSON object,
# in the shape eval/score.sh reads (see eval/expected.sh). Each anchor regex is
# resolved to a line number in the file as it is at the case's head commit.
# Usage: eval/real/expected.sh CASE...
set -euo pipefail

real_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# line BARE HEAD CASE FILE REGEX [FROM]: the first line of FILE at HEAD that
# matches, at line FROM or after it.
line() {
    local n from="${6:-1}"
    n="$(git -C "$1" show "$2:$4" | tail -n "+$from" | grep -nE -m 1 -- "$5" | cut -d: -f1 || true)"
    [ -n "$n" ] || { echo "expected: $3: anchor /$5/ not found in $4" >&2; exit 2; }
    echo $((n + from - 1))
}

result="{}"
for c in "$@"; do
    spec="$(jq -c . "${EVAL_REAL_CASES:-$real_dir/cases}/$c/case.json")"
    head="$(jq -r .head <<< "$spec")"
    bare="$("$real_dir/repo.sh" "$(jq -r .repo <<< "$spec")" "$(jq -r .base <<< "$spec")" "$head")"
    bugs="[]"
    count="$(jq '.bugs | length' <<< "$spec")"
    i=0
    while [ "$i" -lt "$count" ]; do
        bug="$(jq -c ".bugs[$i]" <<< "$spec")"
        file="$(jq -r .file <<< "$bug")"
        start="$(line "$bare" "$head" "$c" "$file" "$(jq -r .anchor <<< "$bug")")"
        end="$start"
        anchor_end="$(jq -r '.anchor_end // empty' <<< "$bug")"
        [ -z "$anchor_end" ] || end="$(line "$bare" "$head" "$c" "$file" "$anchor_end" "$start")"
        also="[]"
        n_also="$(jq '.also // [] | length' <<< "$bug")"
        k=0
        while [ "$k" -lt "$n_also" ]; do
            a_file="$(jq -r ".also[$k].file" <<< "$bug")"
            a_line="$(line "$bare" "$head" "$c" "$a_file" "$(jq -r ".also[$k].anchor" <<< "$bug")")"
            a_end="$a_line"
            a_anchor_end="$(jq -r ".also[$k].anchor_end // empty" <<< "$bug")"
            [ -z "$a_anchor_end" ] || a_end="$(line "$bare" "$head" "$c" "$a_file" "$a_anchor_end" "$a_line")"
            also="$(jq -c --arg f "$a_file" --argjson l "$a_line" --argjson e "$a_end" '. + [{file: $f, line: $l, end_line: $e}]' <<< "$also")"
            k=$((k + 1))
        done
        bugs="$(jq -c --argjson b "$bug" --argjson l "$start" --argjson e "$end" --argjson a "$also" \
            '. + [$b + {line: $l, end_line: $e, also: $a}]' <<< "$bugs")"
        i=$((i + 1))
    done
    result="$(jq -c --arg c "$c" --argjson s "$spec" --argjson b "$bugs" \
        '. + {($c): {title: $s.title, repo: $s.repo, mode: $s.mode, date: $s.date, bugs: $b, acceptable: ($s.acceptable // [])}}' <<< "$result")"
done
jq . <<< "$result"
