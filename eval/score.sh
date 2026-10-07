#!/usr/bin/env bash
# Scores an eval output directory: writes summary.json and summary.md and
# prints summary.md.
# Usage: eval/score.sh OUT_DIR
set -euo pipefail

eval_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:?usage: score.sh OUT_DIR}"

# The runs go through a file: a full run is too long for a command-line argument.
# Only the fields the score needs are kept from claude.json.
runs="$out/runs.json"
for meta in "$out"/results/*/*/meta.json; do
    dir="$(dirname "$meta")"
    r="$dir/report.json"; [ -s "$r" ] || r=/dev/null
    c="$dir/claude.json"; [ -s "$c" ] || c=/dev/null
    jq -n --slurpfile m "$meta" --slurpfile r "$r" --slurpfile c "$c" \
        '$m[0] + {report: ($r[0] // null),
                  claude: ($c[0] // null | if . then {total_cost_usd, num_turns, modelUsage} else null end)}' 2>/dev/null ||
        jq -n --slurpfile m "$meta" '$m[0] + {report: null, claude: null}'
done | jq -s . > "$runs"

jq -n --slurpfile expected "$out/expected.json" --slurpfile runs "$runs" --slurpfile env <(cat "$out/env.json" 2>/dev/null || echo '{}') \
    -f "$eval_dir/score.jq" > "$out/summary.json"
jq -r -f "$eval_dir/summary-md.jq" "$out/summary.json" > "$out/summary.md"
cat "$out/summary.md"
