#!/usr/bin/env bash
# Runs money-review over eval cases and scores the result.
#
# Usage: eval/run.sh [--runs N] [--out DIR] [CASE...]
#
# Every run uses your Claude subscription, about as much as one real review.
# Without CASE arguments all cases in eval/cases run. Results go to
# .eval-runs/<timestamp> unless --out is given; summary.md is printed at the end.
# A case runs on eval/app unless its case.json names another app ("app": "app-mongo").
# The working copies go to a temporary directory (EVAL_WORK to choose another), so
# that no CLAUDE.md from the directories above the repository gets into the review.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval_dir="$root/eval"
bin="$root/plugins/money-review/bin/money-review"
runs=1
out=""
cases=()

while [ $# -gt 0 ]; do
    case "$1" in
        --runs) runs="${2:?}"; shift 2 ;;
        --out) out="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "run: unknown option $1" >&2; exit 2 ;;
        *) cases+=("$1"); shift ;;
    esac
done

if [ ${#cases[@]} -eq 0 ]; then
    for d in "$eval_dir"/cases/*/; do cases+=("$(basename "$d")"); done
fi
[ -n "$out" ] || out="$root/.eval-runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work_root="${EVAL_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/money-review-eval.XXXXXX")}"
echo "eval: working copies in $work_root" >&2

"$eval_dir/expected.sh" "${cases[@]}" > "$out/expected.json"

# What the numbers were measured with. The models themselves come from each run's
# claude.json, because the aliases in the agents (sonnet, opus) move without notice.
commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git -C "$root" diff --quiet HEAD -- plugins eval 2>/dev/null || commit="$commit+dirty"
jq -n \
    --arg date "$(date +%Y-%m-%d)" \
    --arg claude "$("${MONEY_REVIEW_CLAUDE:-claude}" --version 2>/dev/null | awk '{print $1}')" \
    --arg version "$(jq -r .version "$root/plugins/money-review/.claude-plugin/plugin.json")" \
    --arg commit "$commit" \
    --argjson runs "$runs" \
    '{date: $date, claude_code: $claude, money_review: $version, commit: $commit, runs_per_case: $runs}' > "$out/env.json"

for c in "${cases[@]}"; do
    n=1
    while [ "$n" -le "$runs" ]; do
        work="$work_root/$c-$n"
        result="$out/results/$c/$n"
        rm -rf "$result"
        mkdir -p "$result"
        "$eval_dir/workdir.sh" "$c" "$work"

        started=$(date +%s)
        status=0
        (cd "$work" && "$bin" --base master --format json --out "$result" >/dev/null 2>"$result/stderr") || status=$?
        seconds=$(( $(date +%s) - started ))

        jq -n --arg c "$c" --argjson n "$n" --argjson s "$status" --argjson t "$seconds" \
            '{case: $c, run: $n, exit: $s, seconds: $t}' > "$result/meta.json"
        echo "eval: $c run $n: exit $status, ${seconds}s, $(jq '.findings | length' "$result/report.json" 2>/dev/null || echo '?') finding(s)" >&2
        n=$((n + 1))
    done
done

"$eval_dir/score.sh" "$out"

baseline="$eval_dir/baseline/summary.json"
if [ -f "$baseline" ] && [ "$(jq -c '.models // []' "$baseline")" != "$(jq -c '.models // []' "$out/summary.json")" ]; then
    echo "" >&2
    echo "run: the models differ from the baseline ($(jq -r '.models | join(", ")' "$baseline")). Compare with eval/compare.sh $baseline $out" >&2
fi
