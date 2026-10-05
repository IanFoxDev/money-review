#!/usr/bin/env bash
# Splits a diff into groups of files for separate reviewer passes. Prints JSON:
#   [{"diff": "OUT/group-1.diff", "files": [...], "lines": 412}, ...]
#
# Usage: split.sh DIFF OUT_DIR MAX_LINES [FILE...]
#
# Only the given files are kept (all files of the diff when none are given).
# Files go in path order, so the files of one module stay together; a group is
# closed when the next file would take it over MAX_LINES changed lines. A file
# bigger than MAX_LINES gets a group of its own.
set -euo pipefail

diff="${1:?usage: split.sh DIFF OUT_DIR MAX_LINES [FILE...]}"
out="${2:?usage: split.sh DIFF OUT_DIR MAX_LINES [FILE...]}"
max="${3:?usage: split.sh DIFF OUT_DIR MAX_LINES [FILE...]}"
shift 3

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# One chunk per file of the diff, named by its order; index.tsv maps
# order -> changed lines -> path.
awk -v dir="$work" '
    /^diff --git / {
        n++; file = dir "/" n ".chunk"; changed[n] = 0; inhunk = 0
        print > file; next
    }
    n == 0 { next }
    /^--- / && !inhunk { old = substr($0, 5); sub(/^a\//, "", old); print > file; next }
    /^\+\+\+ / && !inhunk {
        p = substr($0, 5); sub(/^b\//, "", p); if (p == "/dev/null") p = old
        path[n] = p; print > file; next
    }
    /^@@/ { inhunk = 1; print > file; next }
    inhunk && /^[-+]/ { changed[n]++ }
    { print > file }
    END { for (i = 1; i <= n; i++) if (i in path) printf "%d\t%d\t%s\n", i, changed[i], path[i] > (dir "/index.tsv") }
' "$diff"
touch "$work/index.tsv"

if [ $# -gt 0 ]; then
    printf '%s\n' "$@" > "$work/keep"
    awk -F'\t' 'NR == FNR { keep[$0] = 1; next } ($3 in keep)' "$work/keep" "$work/index.tsv" > "$work/selected.tsv"
else
    cp "$work/index.tsv" "$work/selected.tsv"
fi
sort -t$'\t' -k3,3 "$work/selected.tsv" > "$work/sorted.tsv"

groups="[]"
g=0
lines=0
files="[]"
flush() {
    [ "$files" = "[]" ] && return 0
    groups="$(jq -c --arg d "$out/group-$g.diff" --argjson f "$files" --argjson l "$lines" \
        '. + [{diff: $d, files: $f, lines: $l}]' <<< "$groups")"
}
while IFS=$'\t' read -r idx changed path; do
    if [ "$files" != "[]" ] && [ $((lines + changed)) -gt "$max" ]; then
        flush
        files="[]"
        lines=0
    fi
    if [ "$files" = "[]" ]; then
        g=$((g + 1))
        : > "$out/group-$g.diff"
    fi
    cat "$work/$idx.chunk" >> "$out/group-$g.diff"
    files="$(jq -c --arg p "$path" '. + [$p]' <<< "$files")"
    lines=$((lines + changed))
done < "$work/sorted.tsv"
flush

jq . <<< "$groups"
