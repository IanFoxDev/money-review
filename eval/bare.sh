#!/usr/bin/env bash
# Runs a plain review prompt over the eval cases, for comparison with money-review.
#
# Usage: eval/bare.sh [--runs N] [--model MODEL] [--out DIR] [CASE...]
#
# The diff goes to `claude -p` with a one-line prompt and no plugin. The model may
# read the repository (Read, Grep, Glob) like the money-review agents do. The only
# addition to the prompt is the answer format, so the findings can be scored.
# Default model: opus. Results go to .eval-runs/bare-<timestamp> unless --out is
# given, and are scored by eval/score.sh. Every run uses your Claude subscription.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval_dir="$root/eval"
claude="${MONEY_REVIEW_CLAUDE:-claude}"
runs=1
model=opus
out=""
cases=()

while [ $# -gt 0 ]; do
    case "$1" in
        --runs) runs="${2:?}"; shift 2 ;;
        --model) model="${2:?}"; shift 2 ;;
        --out) out="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "bare: unknown option $1" >&2; exit 2 ;;
        *) cases+=("$1"); shift ;;
    esac
done

if [ ${#cases[@]} -eq 0 ]; then
    for d in "$eval_dir"/cases/*/; do cases+=("$(basename "$d")"); done
fi
[ -n "$out" ] || out="$root/.eval-runs/bare-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work_root="${EVAL_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/money-review-bare.XXXXXX")}"
echo "bare: working copies in $work_root" >&2

prompt='Review this change. The diff against master is on stdin; the repository is the current directory. Report the bugs you find: file path relative to the repository root, line number in the new version of the file.'

schema='{
  "type": "object",
  "additionalProperties": false,
  "required": ["findings"],
  "properties": {
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["file", "line", "severity", "title", "explanation"],
        "properties": {
          "file": {"type": "string"},
          "line": {"type": "integer"},
          "severity": {"enum": ["critical", "high", "medium", "low"]},
          "title": {"type": "string"},
          "explanation": {"type": "string"}
        }
      }
    }
  }
}'

"$eval_dir/expected.sh" "${cases[@]}" > "$out/expected.json"
commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git -C "$root" diff --quiet HEAD -- eval 2>/dev/null || commit="$commit+dirty"
jq -n \
    --arg date "$(date +%Y-%m-%d)" \
    --arg claude "$("$claude" --version 2>/dev/null | awk '{print $1}')" \
    --arg commit "$commit" \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --argjson runs "$runs" \
    '{date: $date, claude_code: $claude, money_review: "bare prompt", commit: $commit, runs_per_case: $runs, model: $model, prompt: $prompt}' > "$out/env.json"

for c in "${cases[@]}"; do
    n=1
    while [ "$n" -le "$runs" ]; do
        work="$work_root/$c-$n"
        result="$out/results/$c/$n"
        rm -rf "$result"
        mkdir -p "$result"
        "$eval_dir/workdir.sh" "$c" "$work"
        git -C "$work" add -A
        git -C "$work" diff --cached master > "$result/diff.patch"

        started=$(date +%s)
        status=0
        (cd "$work" && "$claude" -p "$prompt" \
            --model "$model" \
            --output-format json \
            --json-schema "$schema" \
            --allowedTools Read Grep Glob \
            < "$result/diff.patch" > "$result/claude.json" 2>"$result/stderr") || status=$?
        seconds=$(( $(date +%s) - started ))

        # Paths as the scorer expects them: relative, without ./ or the working copy.
        jq --arg w "$work/" '{findings: [(.structured_output.findings // [])[]
            | .file |= (ltrimstr("/private") | ltrimstr($w) | ltrimstr("./"))]}' "$result/claude.json" > "$result/report.json" 2>/dev/null \
            || { rm -f "$result/report.json"; [ "$status" -ne 0 ] || status=4; }

        jq -n --arg c "$c" --argjson n "$n" --argjson s "$status" --argjson t "$seconds" \
            '{case: $c, run: $n, exit: $s, seconds: $t}' > "$result/meta.json"
        echo "bare: $c run $n: exit $status, ${seconds}s, $(jq '.findings | length' "$result/report.json" 2>/dev/null || echo '?') finding(s)" >&2
        n=$((n + 1))
    done
done

"$eval_dir/score.sh" "$out"
