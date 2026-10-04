#!/usr/bin/env bash
# Runs money-review over eval cases and scores the result.
#
# Usage: eval/run.sh [--runs N] [--out DIR] [CASE...]
#
# Every run uses your Claude subscription, about as much as one real review.
# Without CASE arguments all cases in eval/cases run. Results go to
# .eval-runs/<timestamp> unless --out is given; summary.md is printed at the end.
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
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

"$eval_dir/expected.sh" "${cases[@]}" > "$out/expected.json"

for c in "${cases[@]}"; do
    [ -d "$eval_dir/cases/$c" ] || { echo "run: no case $c" >&2; exit 2; }
    n=1
    while [ "$n" -le "$runs" ]; do
        work="$out/work/$c-$n"
        result="$out/results/$c/$n"
        rm -rf "$work" "$result"
        mkdir -p "$work" "$result"

        cp -R "$eval_dir/app/." "$work/"
        git -C "$work" init -q -b master
        git -C "$work" add .
        git -C "$work" -c user.name=eval -c user.email=eval@example.com commit -qm base
        cp -R "$eval_dir/cases/$c/files/." "$work/"

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
