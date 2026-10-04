#!/usr/bin/env bash
# Collects the diff to review and runs triage. Prints JSON for the skill and
# for bin/money-review:
#   {"base": "...", "diff": "/tmp/.../change.diff", "money": true,
#    "categories": [...], "checklists": [...], "files": [...], "context": "..."}
#
# Usage: prepare.sh [--base REF] [--diff FILE] [--config FILE] [--out DIR]
#
# Without --diff the change is everything between the merge base with REF and
# the working tree, so uncommitted edits and new untracked files are reviewed
# too. Without --base the base is origin/HEAD, then master, then main. The
# config defaults to .money-review.json in the repository root when it exists.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
refs="$(cd "$here/../skills/money-review/references" && pwd)"
base=""
diff_in=""
config=""
out=""

while [ $# -gt 0 ]; do
    case "$1" in
        --base) base="${2:?--base needs a ref}"; shift 2 ;;
        --diff) diff_in="${2:?--diff needs a file}"; shift 2 ;;
        --config) config="${2:?--config needs a file}"; shift 2 ;;
        --out) out="${2:?--out needs a directory}"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "prepare: unknown argument $1" >&2; exit 2 ;;
    esac
done

if [ -z "$out" ]; then
    tmp="${TMPDIR:-/tmp}"
    out="$(mktemp -d "${tmp%/}/money-review.XXXXXX")"
fi
mkdir -p "$out"
diff_file="$out/change.diff"

if [ -n "$diff_in" ]; then
    cp "$diff_in" "$diff_file"
else
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "prepare: not a git repository" >&2; exit 2; }
    if [ -z "$base" ]; then
        for candidate in origin/HEAD master main; do
            if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
                base="$candidate"
                break
            fi
        done
        [ -n "$base" ] || { echo "prepare: no base branch found, pass --base" >&2; exit 2; }
    fi
    merge_base="$(git merge-base "$base" HEAD)"
    git diff --no-color --no-ext-diff "$merge_base" > "$diff_file"
    # New files that are not added yet are part of the change too.
    git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
        git diff --no-color --no-ext-diff --no-index /dev/null "$f" >> "$diff_file" || true
    done
fi

if [ -z "$config" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    [ -f "$root/.money-review.json" ] && config="$root/.money-review.json"
fi

triage_args=()
[ -n "$config" ] && triage_args=(--config "$config")
triage="$("$here/triage.sh" ${triage_args[@]+"${triage_args[@]}"} "$diff_file")"

jq -n \
    --argjson t "$triage" \
    --arg base "$base" \
    --arg diff "$diff_file" \
    --arg refs "$refs" \
    '{
        base: $base,
        diff: $diff,
        money: $t.money,
        categories: $t.categories,
        checklists: ($t.categories | map({
            TX: "transactions.md", RACE: "races.md",
            IDEM: "idempotency.md", MONEY: "arithmetic.md"
        }[.] // empty) | map($refs + "/" + .)),
        files: $t.files,
        context: $t.context
    }'
