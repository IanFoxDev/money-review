#!/usr/bin/env bash
# Compares two eval runs and lists regressions. Use it after a model change or
# before a release: BASE is the last accepted run (eval/baseline/summary.json),
# NEW is the run to check.
#
# Usage: eval/compare.sh BASE NEW      (a summary.json or a run directory)
#
# Exit codes: 0 no regression, 1 regressions found, 2 usage error.
set -euo pipefail

eval_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
summary() { if [ -d "$1" ]; then echo "$1/summary.json"; else echo "$1"; fi; }
base="$(summary "${1:?usage: compare.sh BASE NEW}")"
new="$(summary "${2:?usage: compare.sh BASE NEW}")"
for f in "$base" "$new"; do
    [ -r "$f" ] || { echo "compare: cannot read $f" >&2; exit 2; }
done

result="$(jq -n --argjson base "$(cat "$base")" --argjson new "$(cat "$new")" -f "$eval_dir/compare.jq")"

jq -r '
  def pct: if . == null then "n/a" else "\(. * 100 | round)%" end;
  def num: if . == null then "-" else (. * 100 | round / 100 | tostring) end;
  def side(s): "\(s.env.date // "?") money-review \(s.env.money_review // "?") (\(s.env.commit // "?")), \(s.models | join(", "))";
  "# Eval comparison",
  "",
  "- base: " + side(.base),
  "- new:  " + side(.new),
  (if .models_changed then "", "**The models changed.** Read the differences below as the effect of the new models." else empty end),
  "",
  "| | base | new |",
  "|---|---|---|",
  "| Precision | \(.base.precision | pct) | \(.new.precision | pct) |",
  "| Recall | \(.base.recall | pct) | \(.new.recall | pct) |",
  "| Clean runs with a false alarm | \(.base.clean) | \(.new.clean) |",
  "| API-equivalent cost per reviewed run | \(.base.cost) | \(.new.cost) |",
  "",
  (if (.only_base | length) > 0 or (.only_new | length) > 0 then
    "The case sets differ, so the totals above are not comparable; compare the cases below.",
    (if (.only_base | length) > 0 then "Only in base: " + (.only_base | join(", ")) + "." else empty end),
    (if (.only_new | length) > 0 then "Only in new: " + (.only_new | join(", ")) + "." else empty end),
    ""
   else empty end),
  (if (.cases | length) == 0 then "Every case present in both runs scored the same." else
    "| Case | Recall base / new | False alarms per run base / new | Skipped base / new |",
    "|---|---|---|---|",
    (.cases[] | "| \(.case) | \(.base_recall | pct) / \(.new_recall | pct) | \(.base_fp | num) / \(.new_fp | num) | \(.base_skip // "-") / \(.new_skip // "-") |")
   end),
  "",
  (if (.regressions | length) == 0 then "No regressions." else
    "## Regressions", "", (.regressions[] | "- " + .) end)
' <<< "$result"

[ "$(jq '.regressions | length' <<< "$result")" -eq 0 ]
