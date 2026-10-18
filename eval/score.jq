# Scores eval runs. Input variables, each read with --slurpfile:
#   $expected  {case: {title, bugs: [{rules, file, line, ...}], acceptable: [{rules, file}]}}
#   $runs      [{case, run, exit, seconds, report, claude}]
#   $env       what the run was measured with (eval/run.sh writes it)
#
# A finding is a true positive when file, rule and line (within 5 lines of the
# anchor, or of the anchor_end range) match an expected bug. A finding on the right lines with another rule
# counts towards the loose recall, not the strict one. A finding that matches an
# "acceptable" entry (a real but secondary issue, in its lines or anywhere in its
# file) is neither TP nor FP. Anything
# else is a false positive. A second finding for an already matched bug is a
# duplicate.
#
# A finding without a rule (eval/bare.sh: a plain review prompt knows no rules)
# matches a bug by file and line, and an "acceptable" entry by file.

def near_one($b; $f): $f.file == $b.file and $f.line >= $b.line - 5 and $f.line <= ($b.end_line // $b.line) + 5;
# A bug may name other places where it can fairly be reported ("also" in case.json).
def near($b; $f): near_one($b; $f) or any(($b.also // [])[]; near_one(.; $f));
# An acceptable entry with a line (eval/real: an anchor) covers those lines, else the file.
def acceptable_ok($a; $f): (if $a.line == null then $a.file == $f.file else near_one($a; $f) end)
  and ($f.rule == null or ($a.rules | index($f.rule)) != null);
def rule_ok($b; $f): $f.rule == null or ($b.rules | index($f.rule)) != null;
def ratio($a; $b): if $b == 0 then null else ($a / $b * 1000 | round / 1000) end;
def category: split("-")[0];
# A real-bug case can name a family that no rule has yet ("class": "NEW-TIME").
def bug_category: .class // (.rules[0] | category);

def score_run($exp; $r):
  ($exp.bugs) as $bugs
  # Runs made before fix-lines.sh made paths relative can hold absolute ones that
  # end in the case's working copy: .../<case>/app/Fee.php.
  | ((($r.report // {}).findings // []) | map(.file |= (
      if type == "string" and startswith("/") and contains("/" + $r.case + "/")
      then split("/" + $r.case + "/")[1:] | join("/" + $r.case + "/") else . end))) as $fs
  | (reduce $fs[] as $f (
      {matched: [], loose: [], tp: 0, fp: 0, duplicate: 0, acceptable: 0, wrong_rule: 0, fps: []};
      . as $s0
      # A bug not found yet wins over one already found, when several fit.
      | ([range(0; $bugs | length) | select(near($bugs[.]; $f) and rule_ok($bugs[.]; $f))]) as $fit
      | (([$fit[] | select(. as $k | $s0.matched | index($k) | not)] | first) // ($fit | first)) as $i
      | ([range(0; $bugs | length) | select(near($bugs[.]; $f))] | first) as $j
      | if $i != null then
          (if (.matched | index($i)) != null then .duplicate += 1 else .matched += [$i] | .tp += 1 end)
        elif $j != null then .wrong_rule += 1 | .loose += [$j]
        elif ($exp.acceptable | any(acceptable_ok(.; $f))) then .acceptable += 1
        else .fp += 1 | .fps += [{rule: $f.rule, file: $f.file, line: $f.line, title: $f.title}]
        end
    )) as $s
  | $s + {
      case: $r.case, run: $r.run, exit: $r.exit, seconds: $r.seconds,
      bugs: ($bugs | length),
      fn: (($bugs | length) - ($s.matched | length)),
      loose_found: (($s.matched + $s.loose) | unique | length),
      missed: [range(0; $bugs | length) as $k | select(($s.matched | index($k)) == null) | $bugs[$k] | {rules, file, line}],
      found_categories: [$s.matched[] | $bugs[.] | bug_category],
      bug_categories: [$bugs[] | bug_category],
      triage_skipped: ($r.claude == null and $r.exit == 0),
      error: ($r.report == null or $r.exit >= 2),
      cost: (($r.claude // {}).total_cost_usd // 0),
      turns: (($r.claude // {}).num_turns // 0)
    }
  | del(.matched, .loose);

$expected[0] as $expected
| $runs[0] as $runs
| [ $runs[] | score_run($expected[.case]; .) ] as $scored
| ($scored | map(.tp) | add // 0) as $tp
| ($scored | map(.fp) | add // 0) as $fp
| ($scored | map(.fn) | add // 0) as $fn
| ($scored | map(.bugs) | add // 0) as $bugs
| {
    runs: ($scored | length),
    cases: ($scored | map(.case) | unique | length),
    precision: ratio($tp; $tp + $fp),
    recall: ratio($tp; $bugs),
    loose_recall: ratio($scored | map(.loose_found) | add // 0; $bugs),
    true_positives: $tp, false_positives: $fp, missed: $fn,
    wrong_rule: ($scored | map(.wrong_rule) | add // 0),
    duplicates: ($scored | map(.duplicate) | add // 0),
    acceptable_extras: ($scored | map(.acceptable) | add // 0),
    clean_runs_with_findings: ($scored | map(select(.bugs == 0 and .fp > 0)) | length),
    clean_runs: ($scored | map(select(.bugs == 0)) | length),
    triage_misses: ($scored | map(select(.bugs > 0 and .triage_skipped)) | length),
    errors: ($scored | map(select(.error)) | length),
    by_category: (
      [$scored[] | .bug_categories[] ] as $all
      | [$scored[] | .found_categories[] ] as $found
      | $all | unique | map(. as $c | {
          category: $c,
          bugs: ($all | map(select(. == $c)) | length),
          found: ($found | map(select(. == $c)) | length)
        } | . + {recall: ratio(.found; .bugs)})
    ),
    cost_usd: {
      total: ($scored | map(.cost) | add // 0 | . * 100 | round / 100),
      per_reviewed_run: ratio($scored | map(select(.triage_skipped | not) | .cost) | add // 0;
                              $scored | map(select(.triage_skipped | not)) | length)
    },
    seconds_per_reviewed_run: ratio($scored | map(select(.triage_skipped | not) | .seconds) | add // 0;
                                    $scored | map(select(.triage_skipped | not)) | length),
    cases_detail: ($scored | group_by(.case) | map({
      case: .[0].case,
      title: $expected[.[0].case].title,
      runs: length,
      bugs: .[0].bugs,
      found: (map(.tp) | add),
      loose_found: (map(.loose_found) | add),
      false_positives: (map(.fp) | add),
      triage_skipped: (map(select(.triage_skipped)) | length),
      errors: (map(select(.error)) | length),
      runs_complete: (map(select(.fn == 0)) | length),
      mode: $expected[.[0].case].mode,
      date: $expected[.[0].case].date,
      seconds: (map(.seconds) | add / length | round),
      cost: (map(.cost) | add / length * 100 | round / 100),
      missed: (map(.missed[]) | unique),
      fps: (map(.fps[]))
    }))
  }
  | . + (
      # Real-bug cases (eval/real) carry a mode and a date: recall by mode, before and
      # after the models' training cutoff, and how steadily each bug case is found.
      [.cases_detail[] | select(.mode != null and .bugs > 0)] as $real
      | (($env[0] // {}).cutoff // "2026-06-01") as $cutoff
      | def recall_of($cs): ($cs | map(.bugs * .runs) | add // 0) as $b
          | {bugs: $b, found: ($cs | map(.found) | add // 0)} | . + {recall: ratio(.found; .bugs)};
      if $real == [] then {} else {
        by_mode: ($real | group_by(.mode) | map({mode: .[0].mode} + recall_of(.))),
        by_date: {cutoff: $cutoff,
                  before: recall_of([$real[] | select(.date < $cutoff)]),
                  after: recall_of([$real[] | select(.date >= $cutoff)])},
        stability: {cases: ($real | length),
                    every_run: ($real | map(select(.runs_complete == .runs)) | length),
                    some_runs: ($real | map(select(.found > 0 and .runs_complete < .runs)) | length),
                    never: ($real | map(select(.found == 0)) | length)}
      } end
    )
  + {env: $env[0], models: ([$runs[].claude.modelUsage // {} | keys[]] | unique)}
