#!/usr/bin/env bash
# Collects the diff to review and runs triage. Prints JSON for the skill and
# for bin/money-review:
#   {"base": "...", "diff": "/tmp/.../change.diff", "money": true,
#    "categories": [...], "checklists": [...], "files": [...], "context": "...",
#    "groups": [{"diff", "checklists", "files", "lines"}], "coverage": {...}}
# A change bigger than review.group_lines changed lines is split into groups of
# files, each reviewed on its own (see split.sh); a copy goes to OUT/prepared.json.
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
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
    [ "$diff_in" -ef "$diff_file" ] || cp "$diff_in" "$diff_file"
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

checklists_of() { # categories JSON -> checklist paths JSON
    jq -c --arg refs "$refs" 'map({
        TX: "transactions.md", RACE: "races.md",
        IDEM: "idempotency.md", MONEY: "arithmetic.md"
    }[.] // empty) | map($refs + "/" + .)' <<< "$1"
}

if [ -n "$config" ]; then
    review="$(jq -s '(.[0].review // {}) * (.[1].review // {})' "$here/../defaults/config.json" "$config")"
else
    review="$(jq '.review // {}' "$here/../defaults/config.json")"
fi
group_lines="$(jq -r '.group_lines // 800' <<< "$review")"
max_groups="$(jq -r '.max_groups // 6' <<< "$review")"

files_changed="$(grep -c '^diff --git ' "$diff_file" || true)"
groups="[]"
not_reviewed="[]"
if [ "$(jq -r .money <<< "$triage")" = "true" ]; then
    in_scope=()
    while IFS= read -r f; do in_scope+=("$f"); done < <(jq -r '.files[]' <<< "$triage")
    split="$("$here/split.sh" "$diff_file" "$out/groups" "$group_lines" ${in_scope[@]+"${in_scope[@]}"})"

    if [ "$(jq length <<< "$split")" -le 1 ]; then
        # A change that fits one pass is reviewed as a whole, as before.
        groups="$(jq -c --arg d "$diff_file" --argjson c "$(checklists_of "$(jq -c .categories <<< "$triage")")" \
            --argjson t "$triage" --argjson s "$split" \
            '[{diff: $d, checklists: $c, files: $t.files, lines: ($s[0].lines // 0)}]' <<< '{}')"
    else
        # Each group gets the checklists its own files call for. When there are more
        # groups than max_groups, the ones that match the most checklists win.
        scored="[]"
        n="$(jq length <<< "$split")"
        i=0
        while [ "$i" -lt "$n" ]; do
            g="$(jq -c ".[$i]" <<< "$split")"
            cats="$("$here/triage.sh" ${triage_args[@]+"${triage_args[@]}"} "$(jq -r .diff <<< "$g")" | jq -c .categories)"
            scored="$(jq -c --argjson g "$g" --argjson c "$(checklists_of "$cats")" --argjson k "$cats" --argjson i "$i" \
                '. + [$g + {checklists: $c, score: ($k | length), order: $i}]' <<< "$scored")"
            i=$((i + 1))
        done
        groups="$(jq -c --argjson m "$max_groups" \
            'sort_by(-.score, -.lines, .order) | .[:$m] | sort_by(.order) | map(del(.score, .order))' <<< "$scored")"
        not_reviewed="$(jq -c --argjson m "$max_groups" \
            'sort_by(-.score, -.lines, .order) | .[$m:] | map(.files[]) | sort' <<< "$scored")"
    fi
fi

jq -n \
    --argjson t "$triage" \
    --arg base "$base" \
    --arg diff "$diff_file" \
    --argjson checklists "$(checklists_of "$(jq -c .categories <<< "$triage")")" \
    --argjson groups "$groups" \
    --argjson not_reviewed "$not_reviewed" \
    --argjson files_changed "$files_changed" \
    '{
        base: $base,
        diff: $diff,
        money: $t.money,
        categories: $t.categories,
        checklists: $checklists,
        files: $t.files,
        context: $t.context,
        groups: $groups,
        coverage: {
            files_changed: $files_changed,
            files_with_money: ($t.files | length),
            files_reviewed: ([$groups[].files[]] | length),
            groups: ($groups | length),
            not_reviewed: $not_reviewed
        }
    }' | tee "$out/prepared.json"
