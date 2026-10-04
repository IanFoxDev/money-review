#!/usr/bin/env bash
# Renders a money-review report (schemas/report.schema.json) as Markdown.
# Usage: render.sh [REPORT_JSON]   (report from stdin if no file)
set -euo pipefail

if [ $# -gt 0 ]; then report="$(cat "$1")"; else report="$(cat)"; fi

jq -r '
  def sev: {high: 0, medium: 1, low: 2}[.severity];
  (.findings | sort_by(sev, .file, .line)) as $f
  | (.rejected // []) as $r
  | [
      "## money-review",
      "",
      (if ($f | length) == 0
       then "No money bugs found in this change."
       else "\($f | length) finding(s): \([$f[] | select(.severity == "high")] | length) high, \([$f[] | select(.severity == "medium")] | length) medium, \([$f[] | select(.severity == "low")] | length) low."
       end),
      "",
      ($f[] |
        "### \(.severity | ascii_upcase) \(.rule): \(.title)",
        "",
        "`\(.file):\(.line)`",
        "",
        "**What happens:** \(.scenario)",
        "",
        "**Fix:** \(.fix)",
        ""),
      (if ($r | length) > 0 then
        "<details><summary>\($r | length) candidate(s) dropped by the verifier</summary>",
        "",
        ($r[] | "- \(.rule) `\(.file):\(.line)`: \(.reason)"),
        "",
        "</details>"
       else empty end)
    ]
  | .[]
' <<< "$report"
