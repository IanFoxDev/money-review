def pct: if . == null then "n/a" else "\(. * 100 | round)%" end;
def n: if . == null then "n/a" else tostring end;
[
  "# money-review eval",
  "",
  "\(.cases) cases, \(.runs) runs.",
  "",
  "| Metric | Value |",
  "|---|---|",
  "| Precision | \(.precision | pct) (\(.true_positives) true, \(.false_positives) false) |",
  "| Recall | \(.recall | pct) (\(.missed) missed) |",
  "| Recall, any rule | \(.loose_recall | pct) (\(.wrong_rule) found under another rule) |",
  "| Clean runs with a false alarm | \(.clean_runs_with_findings) of \(.clean_runs) |",
  "| Bug cases skipped by triage | \(.triage_misses) |",
  "| Duplicates, acceptable extras | \(.duplicates), \(.acceptable_extras) |",
  "| Errors | \(.errors) |",
  "| Time per reviewed run | \(.seconds_per_reviewed_run | n) s |",
  "| API-equivalent cost per reviewed run | \(.cost_usd.per_reviewed_run | n) USD (total \(.cost_usd.total)) |",
  "",
  "## By category",
  "",
  "| Category | Bugs | Found | Recall |",
  "|---|---|---|---|",
  (.by_category[] | "| \(.category) | \(.bugs) | \(.found) | \(.recall | pct) |"),
  "",
  "## By case",
  "",
  "| Case | Runs | Found / bugs | Any rule | False alarms | Skipped | s | USD |",
  "|---|---|---|---|---|---|---|---|",
  (.cases_detail[] | "| \(.case) | \(.runs) | \(.found) / \(.bugs * .runs) | \(.loose_found) | \(.false_positives) | \(.triage_skipped) | \(.seconds) | \(.cost) |"),
  "",
  (if ([.cases_detail[] | .fps[]] | length) > 0 then
     "## False alarms", "",
     (.cases_detail[] | .case as $c | .fps[] | "- \($c): \(.rule) `\(.file):\(.line)` \(.title)"),
     ""
   else empty end),
  (if ([.cases_detail[] | .missed[]] | length) > 0 then
     "## Missed", "",
     (.cases_detail[] | .case as $c | .missed[] | "- \($c): \(.rules | join(" or ")) `\(.file):\(.line)`"),
     ""
   else empty end)
] | .[]
