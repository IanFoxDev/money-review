#!/usr/bin/env bash
# Scores an eval output directory: writes summary.json and summary.md and
# prints summary.md.
# Usage: eval/score.sh OUT_DIR
set -euo pipefail

eval_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:?usage: score.sh OUT_DIR}"

runs="$(for meta in "$out"/results/*/*/meta.json; do
    dir="$(dirname "$meta")"
    jq -n --slurpfile m "$meta" \
        --argjson r "$(cat "$dir/report.json" 2>/dev/null || echo null)" \
        --argjson c "$(cat "$dir/claude.json" 2>/dev/null || echo null)" \
        '$m[0] + {report: $r, claude: $c}'
done | jq -s .)"

env="$(cat "$out/env.json" 2>/dev/null || echo '{}')"
jq -n --argjson expected "$(cat "$out/expected.json")" --argjson runs "$runs" \
    -f "$eval_dir/score.jq" |
    jq --argjson env "$env" --argjson runs "$runs" \
        '. + {env: $env, models: ([$runs[].claude.modelUsage // {} | keys[]] | unique)}' > "$out/summary.json"
jq -r -f "$eval_dir/summary-md.jq" "$out/summary.json" > "$out/summary.md"
cat "$out/summary.md"
