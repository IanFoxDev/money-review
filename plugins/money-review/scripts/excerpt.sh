#!/usr/bin/env bash
# Adds to each finding the lines of code around it, read from the file as it is
# now: {"excerpt": {"start": N, "text": "..."}}, two lines before and after.
# The model never writes the excerpt, so it is always the real code.
# Only files of the diff are read: the path comes from the model, which reads
# untrusted input, and files cut from the diff as secrets stay unread.
# Usage: excerpt.sh REPORT DIFF      (run in the repository root; edits REPORT in place)
set -euo pipefail

report="${1:?usage: excerpt.sh REPORT DIFF}"
diff="${2:?usage: excerpt.sh REPORT DIFF}"
around="${MONEY_REVIEW_EXCERPT_LINES:-2}"
changed="$(sed -n 's|^+++ b/||p' "$diff")"

n="$(jq '.findings | length' "$report")"
i=0
while [ "$i" -lt "$n" ]; do
    file="$(jq -r ".findings[$i].file" "$report")"
    line="$(jq -r ".findings[$i].line" "$report")"
    case "$line" in ''|*[!0-9]*) i=$((i + 1)); continue ;; esac
    if grep -qxF -- "$file" <<< "$changed" && [ -f "$file" ]; then
        start=$(( line > around ? line - around : 1 ))
        end=$(( line + around ))
        text="$(sed -n "${start},${end}p" "$file")"
        if [ -n "$text" ]; then
            jq --argjson i "$i" --argjson s "$start" --arg t "$text" \
                '.findings[$i].excerpt = {start: $s, text: $t}' "$report" > "$report.tmp"
            mv "$report.tmp" "$report"
        fi
    fi
    i=$((i + 1))
done
