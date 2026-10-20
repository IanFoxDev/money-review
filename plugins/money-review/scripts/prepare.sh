#!/usr/bin/env bash
# Collects the diff to review and runs triage. Prints JSON for the skill and
# for bin/money-review:
#   {"base": "...", "diff": "/tmp/.../change.diff", "money": true,
#    "categories": [...], "checklists": [...], "files": [...], "context": "...",
#    "groups": [{"diff", "checklists", "checklist", "files", "lines"}], "checklist": "...",
#    "second_pass": true, "coverage": {...},
#    "ignore": [...], "secrets": [...], "private_config": "..."}
# A change bigger than review.group_lines changed lines is split into groups of
# files, each reviewed on its own (see split.sh); a copy goes to OUT/prepared.json.
#
# Usage: prepare.sh [--base REF | --commits RANGE | --diff FILE] [--config FILE] [--out DIR]
#
# Without --diff the change is everything between the merge base with REF and
# the working tree, so uncommitted edits and new untracked files are reviewed
# too. Without --base the base is origin/HEAD, then master, then main.
# --commits takes one commit or a range (A..B, A..) and reviews only what is
# committed there; see range.sh. The config defaults to .money-review.json in
# the repository root when it exists. Its "rules" add checklists of your own and its
# "invariants" one more checklist; private/<repository name>/config.json next to the
# plugin adds more of both and is never committed. See docs/config.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
refs="$(cd "$here/../skills/money-review/references" && pwd)"
base=""
commits=""
diff_in=""
config=""
out=""

while [ $# -gt 0 ]; do
    case "$1" in
        --base) base="${2:?--base needs a ref}"; shift 2 ;;
        --commits) commits="${2:?--commits needs a commit or a range}"; shift 2 ;;
        --diff) diff_in="${2:?--diff needs a file}"; shift 2 ;;
        --config) config="${2:?--config needs a file}"; shift 2 ;;
        --out) out="${2:?--out needs a directory}"; shift 2 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
elif [ -n "$commits" ]; then
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "prepare: not a git repository" >&2; exit 2; }
    r="$("$here/range.sh" "$commits")" || exit 2
    git diff --no-color --no-ext-diff "$(jq -r .start <<< "$r")" "$(jq -r .head <<< "$r")" > "$diff_file"
    base="$(jq -r .start <<< "$r")"
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

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -z "$config" ]; then
    [ -f "$root/.money-review.json" ] && config="$root/.money-review.json"
fi

# Private rules live next to the plugin, out of git: private/<repository name>/config.json
# (see private.example/), or the directory in MONEY_REVIEW_PRIVATE. That config goes
# over the project config; its rules and invariants are added to the project's.
private_config="${MONEY_REVIEW_PRIVATE:-$here/../private/$(basename "$root")}/config.json"
if [ -f "$private_config" ]; then
    with_abs_rules() { # config file -> JSON with absolute rule file paths
        local d
        d="$(cd "$(dirname "$1")" && pwd)"
        jq --arg d "$d" '.rules = [.rules // [] | .[]
            | .file = (if (.file // "") | startswith("/") then .file else $d + "/" + (.file // "") end)]' "$1"
    }
    project_cfg="{}"
    [ -n "$config" ] && project_cfg="$(with_abs_rules "$config")"
    jq -n --argjson a "$project_cfg" --argjson b "$(with_abs_rules "$private_config")" \
        '($a * $b) + {rules: (($a.rules // []) + ($b.rules // [])),
                      invariants: (($a.invariants // []) + ($b.invariants // []))}' > "$out/config.json"
    config="$out/config.json"
    private_config="$(cd "$(dirname "$private_config")" && pwd)/config.json"
else
    private_config=""
fi

# Files that may hold secrets leave the diff here, before triage and before any
# model; the same patterns are passed on as Read deny rules.
if [ -n "$config" ]; then
    secrets="$(jq -cs '.[1].secrets // .[0].secrets // []' "$here/../defaults/config.json" "$config")"
else
    secrets="$(jq -c '.secrets // []' "$here/../defaults/config.json")"
fi
secrets_excluded="$("$here/strip-secrets.sh" "$diff_file" "$secrets")"
# bin/money-review prepares the change, then the skill prepares the same diff file
# again; the files cut the first time must stay in the report.
if [ -n "$diff_in" ] && [ "$diff_in" -ef "$diff_file" ] && [ -f "$out/secrets-excluded.json" ]; then
    secrets_excluded="$(jq -c --slurpfile p "$out/secrets-excluded.json" '$p[0] + . | unique' <<< "$secrets_excluded")"
fi
echo "$secrets_excluded" > "$out/secrets-excluded.json"

triage_args=()
[ -n "$config" ] && triage_args=(--config "$config")
triage="$("$here/triage.sh" ${triage_args[@]+"${triage_args[@]}"} "$diff_file")"

# Private rules and invariants come from the project config. A rule file path is
# relative to the config file.
private="{}"
invariants="[]"
if [ -n "$config" ]; then
    config_dir="$(cd "$(dirname "$config")" && pwd)"
    private="$(jq -c --arg d "$config_dir" '[.rules // [] | .[]
        | {(.prefix): (if (.file // "") | startswith("/") then .file else $d + "/" + (.file // "") end)}]
        | add // {}' "$config")"
    while IFS= read -r f; do
        if [ ! -f "$f" ] || [ ! -r "$f" ]; then
            echo "prepare: cannot read rule file $f" >&2
            exit 2
        fi
    done < <(jq -r '.[]' <<< "$private")
    invariants="$(jq -c '.invariants // [] | map(select(type == "string" and . != ""))' "$config")"
fi

# Invariants become one more checklist, INV-1, INV-2, ..., given to every reviewer.
invariants_file=""
if [ "$(jq length <<< "$invariants")" -gt 0 ]; then
    invariants_file="$out/invariants.md"
    {
        printf '# Invariants of this project (INV)\n\n'
        printf 'The team says these statements about money always hold. For each one, ask: can\n'
        printf 'this change make it false, directly or by making an old path reachable? Report under\n'
        printf 'the INV id with a concrete scenario, the same bar as any other rule. Do not report an\n'
        printf 'invariant that the change does not touch.\n'
        jq -r 'to_entries[] | "\n## INV-\(.key + 1). \(.value)"' <<< "$invariants"
    } > "$invariants_file"
fi

checklists_of() { # categories JSON -> checklist paths JSON
    jq -c --arg refs "$refs" --argjson p "$private" --arg inv "$invariants_file" 'map({
        TX: "transactions.md", RACE: "races.md",
        IDEM: "idempotency.md", MONEY: "arithmetic.md", PSP: "providers.md"
    }[.] as $b | if $b then $refs + "/" + $b else $p[.] // empty end)
    | if length > 0 and $inv != "" then . + [$inv] else . end' <<< "$1"
}

if [ -n "$config" ]; then
    review="$(jq -s '(.[0].review // {}) * (.[1].review // {})' "$here/../defaults/config.json" "$config")"
    ignore="$(jq -c '.ignore // []' "$config")"
else
    review="$(jq '.review // {}' "$here/../defaults/config.json")"
    ignore="[]"
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

# The checklists of a group go to the reviewer as one file. Given several paths, the
# reviewer often read only the ones it judged relevant and missed the rest.
combine() { # checklist paths JSON, output file
    : > "$2"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        cat "$f" >> "$2"
        printf '\n' >> "$2"
    done < <(jq -r '.[]' <<< "$1")
}
checklist=""
if [ "$(jq length <<< "$groups")" -gt 0 ]; then
    checklist="$out/checklists.md"
    combine "$(checklists_of "$(jq -c .categories <<< "$triage")")" "$checklist"
    n="$(jq length <<< "$groups")"
    i=0
    with_files="[]"
    while [ "$i" -lt "$n" ]; do
        g_file="$out/checklists-$((i + 1)).md"
        combine "$(jq -c ".[$i].checklists" <<< "$groups")" "$g_file"
        with_files="$(jq -c --argjson g "$(jq -c ".[$i]" <<< "$groups")" --arg f "$g_file" \
            '. + [$g + {checklist: $f}]' <<< "$with_files")"
        i=$((i + 1))
    done
    groups="$with_files"
fi

jq -n \
    --argjson t "$triage" \
    --arg base "$base" \
    --arg diff "$diff_file" \
    --argjson checklists "$(checklists_of "$(jq -c .categories <<< "$triage")")" \
    --arg checklist "$checklist" \
    --argjson groups "$groups" \
    --argjson not_reviewed "$not_reviewed" \
    --argjson files_changed "$files_changed" \
    --argjson ignore "$ignore" \
    --argjson secrets "$secrets" \
    --argjson secrets_excluded "$secrets_excluded" \
    --argjson review "$review" \
    --arg private_config "$private_config" \
    '{
        base: $base,
        diff: $diff,
        money: $t.money,
        categories: $t.categories,
        checklists: $checklists,
        checklist: $checklist,
        files: $t.files,
        context: $t.context,
        groups: $groups,
        second_pass: ($review.second_pass != false),
        coverage: {
            files_changed: $files_changed,
            files_with_money: ($t.files | length),
            files_reviewed: ([$groups[].files[]] | length),
            groups: ($groups | length),
            not_reviewed: $not_reviewed,
            secrets_excluded: $secrets_excluded
        },
        ignore: $ignore,
        secrets: $secrets,
        private_config: $private_config
    }' | tee "$out/prepared.json"
