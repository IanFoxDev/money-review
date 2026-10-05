#!/usr/bin/env bash
# Prints the expected findings of the given cases as one JSON object, with each
# bug's anchor regex resolved to a line number in the case's version of the file.
# An optional anchor_end turns the bug into a range of lines.
set -euo pipefail

eval_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
result="{}"
for c in "$@"; do
    dir="$eval_dir/cases/$c"
    spec="$(jq -c . "$dir/case.json")"
    bugs="[]"
    count="$(jq '.bugs | length' <<< "$spec")"
    i=0
    while [ "$i" -lt "$count" ]; do
        bug="$(jq -c ".bugs[$i]" <<< "$spec")"
        file="$(jq -r .file <<< "$bug")"
        anchor="$(jq -r .anchor <<< "$bug")"
        line="$(grep -nE -m 1 -- "$anchor" "$dir/files/$file" | cut -d: -f1 || true)"
        [ -n "$line" ] || { echo "expected: $c: anchor /$anchor/ not found in $file" >&2; exit 2; }
        end="$line"
        anchor_end="$(jq -r '.anchor_end // empty' <<< "$bug")"
        if [ -n "$anchor_end" ]; then
            end="$(grep -nE -m 1 -- "$anchor_end" "$dir/files/$file" | cut -d: -f1 || true)"
            [ -n "$end" ] || { echo "expected: $c: anchor_end /$anchor_end/ not found in $file" >&2; exit 2; }
        fi
        bugs="$(jq -c --argjson b "$bug" --argjson l "$line" --argjson e "$end" '. + [$b + {line: $l, end_line: $e}]' <<< "$bugs")"
        i=$((i + 1))
    done
    result="$(jq -c --arg c "$c" --argjson s "$spec" --argjson b "$bugs" \
        '. + {($c): {title: $s.title, bugs: $b, acceptable: ($s.acceptable // [])}}' <<< "$result")"
done
jq . <<< "$result"
