#!/usr/bin/env bash
# Runs money-review over the real-bug cases and scores the result.
#
# Usage: eval/real/run.sh [--runs N] [--out DIR] [--resume] [CASE...]
#
# --resume with the --out of a run that stopped keeps the runs that finished
# (meta.json with exit 0) and does only the rest.
#
# A case is a commit from an open-source project that introduced a money bug,
# fixed later upstream (see eval/real/README.md). The repository is cloned on
# the first run; no code of those projects is stored here. Every reviewed run
# uses your Claude subscription. Results go to .eval-runs/real-<timestamp>.
# Recall is also split at EVAL_CUTOFF (default 2026-06-01): bugs fixed later
# than the models' training data cannot be remembered.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
real_dir="$root/eval/real"
cases_dir="${EVAL_REAL_CASES:-$real_dir/cases}"
bin="$root/plugins/money-review/bin/money-review"
runs=1
out=""
resume=0
cases=()

while [ $# -gt 0 ]; do
    case "$1" in
        --runs) runs="${2:?}"; shift 2 ;;
        --out) out="${2:?}"; shift 2 ;;
        --resume) resume=1; shift ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "run: unknown option $1" >&2; exit 2 ;;
        *) cases+=("$1"); shift ;;
    esac
done

if [ ${#cases[@]} -eq 0 ]; then
    for d in "$cases_dir"/*/; do cases+=("$(basename "$d")"); done
fi
[ -n "$out" ] || out="$root/.eval-runs/real-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work_root="${EVAL_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/money-review-real.XXXXXX")}"
echo "eval: working copies in $work_root" >&2

"$real_dir/expected.sh" "${cases[@]}" > "$out/expected.json"

commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git -C "$root" diff --quiet HEAD -- plugins eval 2>/dev/null || commit="$commit+dirty"
jq -n \
    --arg date "$(date +%Y-%m-%d)" \
    --arg claude "$("${MONEY_REVIEW_CLAUDE:-claude}" --version 2>/dev/null | awk '{print $1}')" \
    --arg version "$(jq -r .version "$root/plugins/money-review/.claude-plugin/plugin.json")" \
    --arg commit "$commit" \
    --argjson runs "$runs" \
    --arg cutoff "${EVAL_CUTOFF:-2026-06-01}" \
    '{set: "real", date: $date, claude_code: $claude, money_review: $version, commit: $commit, runs_per_case: $runs, cutoff: $cutoff}' > "$out/env.json"

for c in "${cases[@]}"; do
    work="$work_root/$c"
    "$real_dir/workdir.sh" "$c" "$work"
    config=()
    [ ! -f "$cases_dir/$c/config.json" ] || config=(--config "$cases_dir/$c/config.json")
    n=1
    while [ "$n" -le "$runs" ]; do
        result="$out/results/$c/$n"
        if [ "$resume" = 1 ] && [ "$(jq -r '.exit' "$result/meta.json" 2>/dev/null)" = 0 ]; then
            echo "eval: $c run $n: kept" >&2
            n=$((n + 1))
            continue
        fi
        rm -rf "$result"
        mkdir -p "$result"
        started=$(date +%s)
        status=0
        (cd "$work" && "$bin" --base master --format json --out "$result" ${config[@]+"${config[@]}"} >/dev/null 2>"$result/stderr") || status=$?
        seconds=$(( $(date +%s) - started ))
        jq -n --arg c "$c" --argjson n "$n" --argjson s "$status" --argjson t "$seconds" \
            '{case: $c, run: $n, exit: $s, seconds: $t}' > "$result/meta.json"
        echo "eval: $c run $n: exit $status, ${seconds}s, $(jq '.findings | length' "$result/report.json" 2>/dev/null || echo '?') finding(s)" >&2
        n=$((n + 1))
    done
done

"$root/eval/score.sh" "$out"
