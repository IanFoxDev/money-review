# Eval

The eval answers two questions about money-review: how many of the money bugs in a
change does it find, and how often does it raise a false alarm. The numbers in the
README come from here.

## What is in it

- `eval/app/` is a small Laravel-shaped billing app on SQL: wallet accounts with a
  double-entry ledger, payments, refunds, a provider webhook, monthly partner payouts.
- `eval/app-mongo/` is the same kind of billing without a framework: PHP with the
  MongoDB library, Kafka and Redis, plus a Go worker with the MongoDB driver and
  `kafka-go`. Ledger transfers are MongoDB transactions with conditional `$inc`,
  payment events go through an outbox, consumers commit after the work.
- Both apps have no known money bugs. They are never run, only read by the reviewer.
  Before an app is used for cases, money-review reviews the whole app as new code;
  what it finds there is fixed in the app first.
- `eval/cases/<name>/` is one merge request. `files/` holds the changed and new files,
  copied over the app. `case.json` lists the bugs the change introduces.
- Cases named `clean-*` introduce no bug. Some of them touch money code on purpose
  (a ledger refactor, a correct chargeback webhook), to measure false alarms where
  they hurt most.

## case.json

```json
{
  "app": "app-mongo",
  "title": "Withdrawal checks the balance outside the transaction and without a lock",
  "bugs": [
    {
      "rules": ["RACE-1", "RACE-2"],
      "file": "app/Services/WithdrawalService.php",
      "anchor": "balance_cents < \\$amountCents",
      "anchor_end": "optional regex, turns the bug into a range of lines"
    }
  ],
  "acceptable": [
    {"rules": ["MONEY-6"], "file": "app/Services/WithdrawalService.php"}
  ]
}
```

`note` is optional and says in a few words what the bug is. A case can have more than
one bug: the planted one and a quieter one next to it. A bug can be in an app file the
case does not change, when the change makes that code wrong; its anchor is then found in
the app. `app` is optional and names the app under `eval/` the case is built on; the default is
`app`. `anchor` is an extended regular expression; its first match in the case's version of
the file is the bug's line, so cases can be edited without counting lines.
`acceptable` lists real but secondary issues that a reviewer may reasonably report.

## Scoring

A finding is a true positive when its file matches, its rule is one of the bug's
`rules`, and its line is within 5 lines of the anchor (or of the anchor range).

- right lines, other rule: counted in "recall, any rule", not in recall. It usually
  means a checklist rule is unclear;
- matches an `acceptable` entry: neither true nor false positive;
- a second finding for an already found bug: duplicate;
- anything else: false positive.

The model is not deterministic: the same case can give 4 findings in one run and 5
in the next. Run each case several times (`--runs 3`) before trusting a number.

## Running

```bash
eval/run.sh --runs 3                     # every case, three times
eval/run.sh race-lock-order clean-installments
eval/score.sh .eval-runs/<dir>           # score an existing run again
```

`eval/bare.sh` runs the same cases through a plain "review this change" prompt with no
plugin (`--model opus` by default), for comparison; its findings have no rule and are
matched by file and line. The last comparison is in
[eval-results/2026-10-07-plain-prompt.md](eval-results/2026-10-07-plain-prompt.md).

Each reviewed run uses your Claude subscription about as much as one real review;
changes that triage skips cost nothing. Results, reports and the working copies of
the app are kept in `.eval-runs/<timestamp>/`, with `summary.md` on top.

## When to run it

The reviewer and the verifier are named by alias (`sonnet`, `opus`), and an alias moves
to a new model without notice. A checklist change can also fix one case and break
another. So the eval runs on a schedule, not when someone remembers:

| When | What | Runs |
|---|---|---|
| Before a minor release (0.x.0) and before 1.0 | every case | 3 |
| Before a patch release | the cases of the checklists the change touches, and every clean case | 3 |
| A change to a checklist or an agent prompt | the cases of that checklist and every clean case, before it is merged | 3 |
| The models change | every case | 3 |

Every review prints the models it used (`money-review: 5 turns, ..., models: ...`), and
`eval/run.sh` warns when a run used other models than the baseline. When that line shows
a model id that is not in `eval/baseline/summary.json`, run the full eval before you
trust the reviews.

Each run writes the money-review version, the commit, the Claude Code version and the
model ids into `summary.json` and `summary.md`. A results file in `docs/eval-results/`
keeps that header.

### Baseline and comparison

`eval/baseline/summary.json` is the last accepted full run. Compare a new run with it:

```bash
eval/compare.sh eval/baseline/summary.json .eval-runs/<dir>
```

It prints both sides with their models, the cases that scored differently, and the
regressions; it exits with 1 when there is one. A regression is:

- a case that lost more than a third of its runs (one run in three is noise);
- a case with more than a third of a false alarm per run added;
- any case newly skipped by triage (triage has no model, so this is never noise);
- precision or recall down by more than 5 points over the same cases.

A regression blocks the release until it is fixed or explained in the results file.
When a full run is accepted, its `summary.json` replaces the baseline in the same commit
as its results file.

## Adding a case

1. Copy the files you change from `eval/app/` into `eval/cases/<name>/files/`, keeping
   the paths, and make the change. One bug per case.
2. Write `case.json` with an anchor that matches the bug's line.
3. Check the anchors: `eval/expected.sh <name>`.
4. Run it a few times and look at the false alarms before you commit it.
