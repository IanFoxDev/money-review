#!/usr/bin/env bash
# Corrects line numbers of findings. Models sometimes count lines in the diff
# instead of the file: line 33 in a 30-line file, or line 1 for a bug further down.
# GitLab then refuses the comment and a reader looks in the wrong place.
#
# A finding with "code" (the text of its line) moves to the line of the file that
# holds that text, the nearest one when there are several. A finding that still
# points past the end of its file moves to the first added line of that file in
# the diff, or to the last line of the file when the diff adds none.
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

line_with() { # file line code -> number of the line nearest to line that contains code
    CODE="$3" awk -v want="$2" '
        index($0, ENVIRON["CODE"]) {
            d = NR - want; if (d < 0) d = -d
            if (best == "" || d < bestd) { best = NR; bestd = d }
        }
        END { if (best != "") print best }
    ' "$1"
}

set_line() { # index line
    jq --argjson i "$1" --argjson l "$2" '.findings[$i].line = $l' "$report" > "$report.tmp"
    mv "$report.tmp" "$report"
}

count="$(jq '.findings | length' "$report")"
i=0
while [ "$i" -lt "$count" ]; do
    file="$(jq -r ".findings[$i].file" "$report")"
    line="$(jq -r ".findings[$i].line" "$report")"
    code="$(jq -r --argjson i "$i" '.findings[$i].code // "" | (split("\n")[0] // "") | sub("^\\s+"; "") | sub("\\s+$"; "")' "$report")"
    if [ -f "$file" ] && [ -n "$code" ]; then
        new="$(line_with "$file" "$line" "$code")"
        if [ -n "$new" ] && [ "$new" != "$line" ]; then
            set_line "$i" "$new"
            echo "money-review: $file:$line does not hold the code of the finding, moved it to line $new" >&2
            line="$new"
        fi
    fi
    if [ -f "$file" ]; then
        total="$(awk 'END { print NR }' "$file")"
        if [ "$line" -lt 1 ] || [ "$line" -gt "$total" ]; then
            new="$(first_added_line "$file")"
            [ -n "$new" ] || new="$total"
            set_line "$i" "$new"
            echo "money-review: $file has no line $line, moved the finding to line $new" >&2
        fi
    fi
    i=$((i + 1))
done
exit 0
