#!/usr/bin/env bash
# Renders a money-review report (schemas/report.schema.json) as Markdown.
# Usage: render.sh [REPORT_JSON]   (report from stdin if no file)
set -euo pipefail

if [ $# -gt 0 ]; then report="$(cat "$1")"; else report="$(cat)"; fi

jq -r '
  def sev: {high: 0, medium: 1, low: 2}[.severity];
  def cell: gsub("\\|"; "\\|");
  def lang: (.file | capture("\\.(?<x>[A-Za-z0-9]+)$").x // "" | ascii_downcase)
    | {php: "php", go: "go", js: "javascript", ts: "typescript", py: "python", rb: "ruby",
       java: "java", kt: "kotlin", cs: "csharp", sql: "sql", rs: "rust"}[.] // "";
  # The code around the finding, numbered, with ">" on its line.
  def excerpt: . as $f
    | ($f.excerpt.text | split("\n")) as $lines
    | (($f.excerpt.start + ($lines | length) - 1) | tostring | length) as $w
    | (if ($f.excerpt.text | contains("```")) then "~~~~" else "```" end) as $fence
    | "\($fence)\($f | lang)",
      ($lines | to_entries[] | (.key + $f.excerpt.start) as $n
        | (if $n == $f.line then "> " else "  " end)
          + ((" " * ($w - ($n | tostring | length))) // "") + ($n | tostring) + " | " + .value),
      $fence,
      "";
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
      (if ($f | length) > 1 then
        "| # | Severity | Rule | Where | Problem |",
        "|---|---|---|---|---|",
        ($f | to_entries[] | "| \(.key + 1) | \(.value.severity) | \(.value.rule) | `\(.value.file):\(.value.line)` | \(.value.title | cell) |"),
        ""
       else empty end),
      ($f | to_entries[] | .key as $k | .value |
        "### \($k + 1). \(.severity | ascii_upcase) \(.rule): \(.title)",
        "",
        "`\(.file):\(.line)`",
        "",
        (if .excerpt then excerpt else empty end),
        "**What happens:** \(.scenario)",
        "",
        "**How to fix:** \(.fix)",
        ""),
      (if .coverage then
        "\(.coverage.files_with_money) of \(.coverage.files_changed) changed file(s) touch money; "
        + (if .coverage.files_reviewed == .coverage.files_with_money then "all of them" else "\(.coverage.files_reviewed)" end)
        + " reviewed"
        + (if .coverage.groups > 1 then " in \(.coverage.groups) groups of files." else "." end),
        "",
        (if ((.coverage.secrets_excluded // []) | length) > 0 then
          "**Left out as possible secrets** (not sent to the model; see `secrets` in the config): "
          + (.coverage.secrets_excluded | map("`\(.)`") | join(", ")),
          ""
         else empty end),
        (if (.coverage.not_reviewed | length) > 0 then
          "**Not reviewed** (over the group limit, review them by hand or raise review.max_groups): "
          + (.coverage.not_reviewed | map("`\(.)`") | join(", ")),
          ""
         else empty end)
       else empty end),
      (if ((.suppressed // []) | length) > 0 then
        "<details><summary>\(.suppressed | length) finding(s) suppressed by the team</summary>",
        "",
        (.suppressed[] | "- \(.rule) `\(.file):\(.line)` \(.title). Ignored by \(.by): \(.reason)"),
        "",
        "</details>",
        ""
       else empty end),
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
