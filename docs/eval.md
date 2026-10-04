# Eval

The eval answers two questions about money-review: how many of the money bugs in a
change does it find, and how often does it raise a false alarm. The numbers in the
README come from here.

## What is in it

- `eval/app/` is a small Laravel-shaped billing app: wallet accounts with a
  double-entry ledger, payments, refunds, a provider webhook, monthly partner payouts.
  It has no known money bugs. It is never run, only read by the reviewer.
- `eval/cases/<name>/` is one merge request. `files/` holds the changed and new files,
  copied over the app. `case.json` lists the bugs the change introduces.
- Cases named `clean-*` introduce no bug. Some of them touch money code on purpose
  (a ledger refactor, a correct chargeback webhook), to measure false alarms where
  they hurt most.

## case.json

```json
{
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

`anchor` is an extended regular expression; its first match in the case's version of
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

Each reviewed run uses your Claude subscription about as much as one real review;
changes that triage skips cost nothing. Results, reports and the working copies of
the app are kept in `.eval-runs/<timestamp>/`, with `summary.md` on top.

## Adding a case

1. Copy the files you change from `eval/app/` into `eval/cases/<name>/files/`, keeping
   the paths, and make the change. One bug per case.
2. Write `case.json` with an anchor that matches the bug's line.
3. Check the anchors: `eval/expected.sh <name>`.
4. Run it a few times and look at the false alarms before you commit it.
