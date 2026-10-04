# 0003. Keep subscription usage low

Date: 2026-10-04. Status: accepted.

## Context

money-review runs on the reviewer's Claude subscription (ADR 0001). A subscription has
usage limits, and a review that eats a big part of them will be switched off after a
week. Most merge requests in a billing codebase do not touch money at all: config,
UI, tests, refactoring of unrelated code.

The obvious design, one agent per category running in parallel on every merge
request, reads the same diff and the same code four times.

## Decision

The review is a pipeline where each stage is cheaper than the next and can stop the
run:

1. **Triage without a model.** `scripts/prepare.sh` collects the diff and
   `scripts/triage.sh` decides with regular expressions whether any changed file
   touches money and which checklists apply. `bin/money-review` stops here when
   nothing matches and never starts Claude. Inside an interactive session the skill
   still costs one short turn to say so.
2. **One reviewer pass** (`money-reviewer`, Sonnet) with only the matched checklists.
   It reads the diff once and the code around it as needed.
3. **Verifier only on candidates** (`money-verifier`, Opus). No candidates, no
   verifier. The verifier is the expensive model, but it reads little: the candidate
   lines and what guards them.
4. **The coordinator does not read code.** It passes paths between stages and renders
   the report with `scripts/render.sh`. In headless runs it is started with
   `--model sonnet`.

A deeper mode with one agent per category is planned as `--deep`, opt in.

## Measurements

On 2026-10-04, `claude -p` on a subscription, numbers from `--output-format json`
(`total_cost_usd` is what the same run would cost on the API, not what is charged):

| Change | Turns | Time | API-equivalent cost |
|---|---|---|---|
| PHP change without money, interactive skill | 1 | a few seconds | 0.05 USD |
| 12-line wallet withdrawal (race, payout after commit), full pipeline | 4 | 97 s | 0.37 USD (Sonnet 0.20, Opus 0.16) |

The withdrawal run found 5 issues (2 high, 2 medium, 1 low), each with a scenario.

## Consequences

- A quiet merge request costs nothing in headless mode and almost nothing
  interactively.
- Triage can miss a money change that uses none of the configured words. Projects
  close the gap with `money_paths` in `.money-review.json`; the eval (step 8 of the
  plan) measures how often it happens.
- Re-reviewing only commits added since the last review is the next saving, once the
  tool posts to merge requests and can store the last reviewed commit.
