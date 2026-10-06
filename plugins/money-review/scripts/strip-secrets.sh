#!/usr/bin/env bash
# Removes files that may hold secrets (.env, keys, certificates) from a diff before
# any model sees it, and prints the removed paths as a JSON array. The same patterns
# become Read deny rules for the review (see bin/money-review), so the agents cannot
# open those files either.
#
# A pattern without a slash matches the file name at any depth (".env", "*.pem");
# a pattern with a slash matches the path from the repository root or below any
# directory ("secrets/*"). As elsewhere in the config, "*" also matches "/".
#
# Usage: strip-secrets.sh DIFF PATTERNS_JSON      (edits DIFF)
set -euo pipefail

diff="${1:?usage: strip-secrets.sh DIFF PATTERNS_JSON}"
patterns="${2:?usage: strip-secrets.sh DIFF PATTERNS_JSON}"

is_secret() { # path -> 0 when a pattern matches it
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

# Block number and path of every file in the diff; the path is the new one, or the
# old one for a deleted file.
index="$(awk '
    /^diff --git / { n++; p = $0; sub(/^diff --git a\/.* b\//, "", p); path[n] = p; next }
    /^\+\+\+ b\// { path[n] = substr($0, 7) }
    END { for (i = 1; i <= n; i++) printf "%d\t%s\n", i, path[i] }
' "$diff")"

drop=""
removed="[]"
while IFS="$(printf '\t')" read -r n path; do
    [ -n "$n" ] || continue
    if is_secret "$path"; then
        drop="$drop $n"
        removed="$(jq -c --arg p "$path" '. + [$p]' <<< "$removed")"
    fi
done <<< "$index"

if [ -n "$drop" ]; then
    awk -v drop="$drop" '
        BEGIN { k = split(drop, d, " "); for (i = 1; i <= k; i++) skip[d[i]] = 1 }
        /^diff --git / { n++ }
        !(n in skip) { print }
    ' "$diff" > "$diff.tmp"
    mv "$diff.tmp" "$diff"
fi
echo "$removed"
