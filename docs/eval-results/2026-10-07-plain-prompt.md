# Eval run 2026-10-07, money-review against a plain review prompt

The question: what does money-review give over asking Claude to review the change?

## Setup

All 49 cases, three times each, three ways:

- **money-review**: the baseline run of the same day
  ([2026-10-07-baseline.md](2026-10-07-baseline.md)), `claude-sonnet-5-5` as the
  reviewer and `claude-opus-5-5` as the verifier.
- **plain prompt, opus** and **plain prompt, sonnet**: `eval/bare.sh`. The diff goes to
  `claude -p` on stdin with "Review this change. [...] Report the bugs you find", no
  plugin. The model may read the repository (Read, Grep, Glob), like the money-review
  agents. The only addition is the answer format (file, line, severity, title,
  explanation), so the findings can be scored.

The working copies are outside any directory with a CLAUDE.md, so no run gets hints
from the environment. Claude Code 2.1.292.

## Planted bugs

All three found every planted bug: 111 of 111. A plain finding has no rule, so it
counts when its file and line match the bug (within 5 lines); money-review findings also
need the rule to match. The cases are small changes with one bug each, and on those the
recall does not tell the tools apart.

## Everything else a reviewer reads

Every finding that is not the first hit on a planted bug (355 in all) was sorted by
reading the code of its case. Findings of the three tools were mixed and had no name on
them, so the judge did not know whose finding it was. Findings that say the same thing
were grouped into one issue, and each issue got one label:

- the planted bug again, at another line or in other words;
- a real money problem beyond the planted bug: a concrete sequence that loses,
  duplicates or misstates money;
- real, not about money: a crash, a query that fails on the database, a lost email;
- a nit: style, docs, speculative hardening, a design opinion;
- wrong: the failure it describes cannot happen in this code.

The labels come from Claude (Opus) agents reading the code, not from a person. Five of
the money labels and one of the wrong ones were checked again against the code, and
all held. The labels and the reasons are in
[2026-10-07-plain-prompt-issues.json](2026-10-07-plain-prompt-issues.json).

| | money-review | plain prompt, opus | plain prompt, sonnet |
|---|---|---|---|
| Planted bugs found | 111 of 111 | 111 of 111 | 111 of 111 |
| Findings, all runs | 141 | 317 | 230 |
| Findings per reviewed run | 1.0 | 2.2 | 1.6 |
| The planted bug again | 8 | 80 | 46 |
| Real money problems beyond the planted bug (findings / distinct) | 17 / 7 | 32 / 12 | 18 / 10 |
| Real, not about money | 3 | 44 | 24 |
| Nits | 2 | 42 | 22 |
| Wrong | 0 | 8 | 9 |
| Findings on clean changes (36 runs) | 0 | 31 | 32 |
| Time per run | 54 s | 17 s | 22 s |
| API-equivalent cost per run | 0.27 USD | 0.15 USD | 0.07 USD |

money-review skips 6 of the 147 runs (two cases with no money) without starting Claude;
"per reviewed run" counts the 141 it reviewed.

## What this says

**money-review is quiet and right.** None of its findings is wrong, two are nits, and it
said nothing on any clean change. A plain prompt on opus raises twice as many findings;
one in six of them is a nit or wrong, and it flags 11 of the 36 clean runs (sonnet: 20).

**A plain prompt sees more around the planted bug.** Over the 17 distinct money problems
that are not the planted bug, money-review found 7, opus 12, sonnet 10. Two were found
only by money-review (a fee and a withdrawal that change the balance without a ledger
entry). Ten were found only by a plain prompt, among them:

- a payment event that no longer carries `partner_id` and the amount, so the commission
  consumer skips every payment (`mongo-tx2-produce-after-write`);
- a chargeback that is rolled back when the user has already spent the money, while the
  provider has taken it (`idem-chargeback-webhook-no-dedup`);
- a payout retry that does not handle a decline, so the money stays in flight
  (`idem-retry-fresh-key`);
- a withdrawal that accepts a negative amount and credits the wallet
  (`race-withdraw-no-lock`, `mongo-race8-secondary-balance`).

The cause is mostly the reviewer, not the verifier: money-review's reviewer works from
the checklists, and most of these problems sit outside them or at their edge (partial
amounts, what an event must carry, provider outcomes a change forgets, the sign of an
amount, which MONEY-5 covers but the reviewer did not raise in these runs). The verifier dropped one of them
(`refunded_cents` left stale in `race-refund-cap-sum`) because it did not fit the rule
it was reported under.

**One clean case is not clean.** `clean-chargeback-webhook` books a chargeback for the
full payment amount, also after a partial refund: 100.00 paid, 40.00 refunded, a
chargeback of 100.00 is booked. Opus reported it in all three runs, money-review never.
The case will be fixed; until then the "no false alarms on clean changes" number of
money-review includes this miss.

**Cost.** money-review costs more and takes longer per review than a plain prompt, for
the coordinator and the verifier. It costs nothing on a change without money.

## What changes

- `clean-chargeback-webhook` gets a correct chargeback amount, or becomes a bug case.
- The checklists get rules for the gaps above, measured with this eval.
- The verifier keeps a real problem under the right rule instead of dropping it.
- Harder cases: changes with a planted bug and a second, quieter one, where recall can
  tell tools apart.
