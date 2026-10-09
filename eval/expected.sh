#!/usr/bin/env bash
# Prints the expected findings of the given cases as one JSON object, with each
# bug's anchor regex resolved to a line number in the case's version of the file
# (or in the app, for a file the case does not change).
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
        # A bug can sit in app code that the change leaves as it is but makes wrong.
        src="$dir/files/$file"
        [ -f "$src" ] || src="$eval_dir/$(jq -r '.app // "app"' "$dir/case.json")/$file"
        line="$(grep -nE -m 1 -- "$anchor" "$src" | cut -d: -f1 || true)"
        [ -n "$line" ] || { echo "expected: $c: anchor /$anchor/ not found in $file" >&2; exit 2; }
        end="$line"
        anchor_end="$(jq -r '.anchor_end // empty' <<< "$bug")"
        if [ -n "$anchor_end" ]; then
            end="$(grep -nE -m 1 -- "$anchor_end" "$src" | cut -d: -f1 || true)"
            [ -n "$end" ] || { echo "expected: $c: anchor_end /$anchor_end/ not found in $file" >&2; exit 2; }
        fi
        # Another place where the same bug can fairly be reported: {file, anchor}.
        also="[]"
        n_also="$(jq '.also // [] | length' <<< "$bug")"
        k=0
        while [ "$k" -lt "$n_also" ]; do
            a_file="$(jq -r ".also[$k].file" <<< "$bug")"
            a_anchor="$(jq -r ".also[$k].anchor" <<< "$bug")"
            a_src="$dir/files/$a_file"
            [ -f "$a_src" ] || a_src="$eval_dir/$(jq -r '.app // "app"' "$dir/case.json")/$a_file"
            a_line="$(grep -nE -m 1 -- "$a_anchor" "$a_src" | cut -d: -f1 || true)"
            [ -n "$a_line" ] || { echo "expected: $c: anchor /$a_anchor/ not found in $a_file" >&2; exit 2; }
            also="$(jq -c --arg f "$a_file" --argjson l "$a_line" '. + [{file: $f, line: $l, end_line: $l}]' <<< "$also")"
            k=$((k + 1))
        done
        bugs="$(jq -c --argjson b "$bug" --argjson l "$line" --argjson e "$end" --argjson a "$also" '. + [$b + {line: $l, end_line: $e, also: $a}]' <<< "$bugs")"
        i=$((i + 1))
    done
    result="$(jq -c --arg c "$c" --argjson s "$spec" --argjson b "$bugs" \
        '. + {($c): {title: $s.title, bugs: $b, acceptable: ($s.acceptable // [])}}' <<< "$result")"
done
jq . <<< "$result"
