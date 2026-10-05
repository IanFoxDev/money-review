#!/usr/bin/env bash
# Moves findings that point at a line the file does not have. Models sometimes
# report line 33 in a 30-line file; GitLab then refuses the comment and a reader
# looks in the wrong place. Such a finding moves to the first added line of that
# file in the diff, or to the last line of the file when the diff adds none.
#
# Usage: fix-lines.sh REPORT DIFF      (run in the repository root; edits REPORT)
set -euo pipefail

report="${1:?usage: fix-lines.sh REPORT DIFF}"
diff="${2:?usage: fix-lines.sh REPORT DIFF}"

first_added_line() { # file -> first added line number in the new version, or nothing
    awk -v want="$1" '
        /^\+\+\+ / { p = substr($0, 5); sub(/^b\//, "", p); cur = (p == want); next }
        /^diff --git / { cur = 0; next }
        cur && /^@@/ { match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) - 1; next }
        cur && /^\+/ { print n + 1; exit }
        cur && /^ / { n++ }
    ' "$diff"
}

count="$(jq '.findings | length' "$report")"
i=0
while [ "$i" -lt "$count" ]; do
    file="$(jq -r ".findings[$i].file" "$report")"
    line="$(jq -r ".findings[$i].line" "$report")"
    if [ -f "$file" ]; then
        total="$(awk 'END { print NR }' "$file")"
        if [ "$line" -lt 1 ] || [ "$line" -gt "$total" ]; then
            new="$(first_added_line "$file")"
            [ -n "$new" ] || new="$total"
            jq --argjson i "$i" --argjson l "$new" '.findings[$i].line = $l' "$report" > "$report.tmp"
            mv "$report.tmp" "$report"
            echo "money-review: $file has no line $line, moved the finding to line $new" >&2
        fi
    fi
    i=$((i + 1))
done
exit 0
