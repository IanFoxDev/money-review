# Compares two eval summaries ($base, $new; summary.json from score.sh).
# Output: {models_changed, overall, cases, regressions}. Rates are per run, so runs
# with a different --runs count compare fairly. One run in three is noise for a
# model, so a case regresses only when it moves by more than a third.
def rate(a; b): if b == 0 then null else a / b end;
def byname: map({key: .case, value: .}) | from_entries;

($base.cases_detail | byname) as $b
| ($new.cases_detail | byname) as $n
| [($b | keys[]), ($n | keys[])] | unique
| map(. as $c | {
    case: $c,
    base: $b[$c], new: $n[$c],
    base_recall: (if $b[$c] then rate($b[$c].found; $b[$c].bugs * $b[$c].runs) else null end),
    new_recall: (if $n[$c] then rate($n[$c].found; $n[$c].bugs * $n[$c].runs) else null end),
    base_fp: (if $b[$c] then rate($b[$c].false_positives; $b[$c].runs) else null end),
    new_fp: (if $n[$c] then rate($n[$c].false_positives; $n[$c].runs) else null end),
    base_skip: ($b[$c].triage_skipped // null),
    new_skip: ($n[$c].triage_skipped // null)
  })
| . as $cases
| {
    models_changed: (($base.models // []) != ($new.models // [])),
    base: {env: ($base.env // {}), models: ($base.models // []), precision: $base.precision, recall: $base.recall,
           clean: "\($base.clean_runs_with_findings) of \($base.clean_runs)", cost: $base.cost_usd.per_reviewed_run},
    new: {env: ($new.env // {}), models: ($new.models // []), precision: $new.precision, recall: $new.recall,
          clean: "\($new.clean_runs_with_findings) of \($new.clean_runs)", cost: $new.cost_usd.per_reviewed_run},
    only_base: [$cases[] | select(.new == null) | .case],
    only_new: [$cases[] | select(.base == null) | .case],
    cases: ($cases | map(select(.base != null and .new != null
        and (.base_recall != .new_recall or .base_fp != .new_fp or .base_skip != .new_skip)))),
    regressions: (
        [$cases[] | select(.base != null and .new != null) |
          (select(.base_recall != null and .new_recall != null and (.base_recall - .new_recall) > 0.34)
            | "\(.case): recall \(.base_recall * 100 | round)% -> \(.new_recall * 100 | round)%"),
          (select((.new_fp - .base_fp) > 0.34)
            | "\(.case): false alarms per run \(.base_fp * 100 | round / 100) -> \(.new_fp * 100 | round / 100)"),
          (select(.new_skip > .base_skip)
            | "\(.case): skipped by triage \(.base_skip) -> \(.new_skip)")]
        + (if ($base.precision - $new.precision) > 0.05 then ["precision \($base.precision * 100 | round)% -> \($new.precision * 100 | round)%"] else [] end)
        + (if ($base.recall - $new.recall) > 0.05 then ["recall \($base.recall * 100 | round)% -> \($new.recall * 100 | round)%"] else [] end)
    )
  }
