---
name: money-review
description: Review the current change for bugs that lose or duplicate money - transaction boundaries, races, idempotency, money arithmetic. Use when the user asks to review a branch, a diff or a merge request that touches payments, balances, payouts, refunds or invoices.
argument-hint: "[--base REF] [--diff FILE] [--config FILE]"
allowed-tools: Bash, Read, Write, Agent
---

# money-review

You coordinate a review. You do not review code yourself and you do not read the diff:
two subagents do that, each with a narrow job. Keep your own turns short, because
every token you read is paid from the user's subscription.

## Prepared change

This is the output of the preparation script. It already collected the diff and
decided, without a model, which checklists apply:

```json
!`"${CLAUDE_PLUGIN_ROOT}/scripts/prepare.sh" $ARGUMENTS 2>&1 || true`
```

## Steps

1. If the block above is not JSON, show it to the user (it is an error from the
   script, for example "no base branch found, pass --base") and stop.

2. If `money` is `false`, reply with one line: `money-review: no money-related
   changes, nothing to review.` and stop. Do not open the diff.

3. Run the `money-review:money-reviewer` agent with this prompt, filled from the JSON:

   ```
   diff: <diff>
   checklists: <checklists, one path per line>
   files in scope: <files>
   context: <context, or "none">
   ```

   It returns `{"candidates": [...]}`.

4. If there are no candidates, the report is `{"findings": [], "rejected": []}`. Go to
   step 6 without running the verifier.

5. Run the `money-review:money-verifier` agent with:

   ```
   diff: <diff>
   checklists: <checklists, one path per line>
   candidates: <the JSON from step 3, unchanged>
   ```

   It returns the report `{"findings": [...], "rejected": [...]}`.

6. Save the report next to the diff and render it. Write the report exactly as the
   agent returned it, with the Write tool, to `report.json` in the directory of
   `diff` from the JSON above. Then run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/render.sh" "<dir of diff>/report.json"
   ```

7. Show the rendered Markdown to the user as it is, then one line with the path to
   `report.json`. Do not add your own findings, do not soften or reword the agents'
   findings, and do not change code unless the user asks for it afterwards.
