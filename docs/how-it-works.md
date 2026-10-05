# How it works

```
diff --> prepare.sh --> triage.sh --> no money? stop, Claude is never started
                             |
                             v
              large change? split.sh: groups of files
                             |
                             v
                   checklists that apply
                             |
                             v
         money-reviewer (Sonnet): candidates with failure scenarios
                             |
                no candidates? report is empty
                             |
                             v
         money-verifier (Opus): refute each one against the code
                             |
                             v
                report.json --> render.sh --> Markdown, MR comments
```

## Stages

**prepare.sh** collects the change. By default that is everything between the merge
base with `origin/HEAD` (or `master`, or `main`) and the working tree, including
uncommitted edits and new files that are not added to git yet. With `--diff FILE` it
takes a ready diff. It then runs triage and prints one JSON object with the diff path,
the decision, the checklist paths and the project context.

**triage.sh** splits the diff by file and uses only extended regular expressions from
the config (see [config.md](config.md)). A file is in scope when it matches
`money_paths` or its changed lines match `signals`. Removed lines count: dropping a
`lockForUpdate()` is a reason to look for races. Checklists are chosen only from files
in scope.

**Groups.** When the money files of a change have more than `review.group_lines`
changed lines (800 by default), `scripts/split.sh` splits them into groups of files in
path order, and triage picks the checklists for each group. A single reviewer over
dozens of files spreads its attention: it finds some bugs and walks past others. A
reviewer per group looks at fewer files at a time. The report says how many files
were reviewed and lists any that were not.

**money-reviewer** gets the diff path, the checklists and the context. With groups,
one reviewer runs per group, in parallel, and also gets the path of the full diff. It reads the
diff once, then the code around each suspicious hunk: the whole function, its callers,
the transaction wrapper, the migration for the table, the base class of a handler. It
reports only what it can describe as a concrete failure scenario.

**money-verifier** gets the candidates and tries to prove each one wrong: a lock taken
earlier in the transaction, a unique index, an outer transaction opened by the caller,
dedup in a middleware, a guard on the current state. Every candidate ends up either in
`findings` or in `rejected`, with the code that prevents it. It does not add findings
of its own. When the guard may live outside the repository it keeps the finding with
a lower severity and says what to check.

**finish.sh** makes the last changes to the report without a model: it moves a
finding that points past the end of its file to a line that exists, and moves
findings accepted with an `ignore` comment or config entry to `suppressed` (see
[config.md](config.md#ignore)).

**render.sh** turns `report.json` (see `plugins/money-review/schemas/report.schema.json`)
into Markdown. The same JSON drives the merge request comments.

## Why two models

The reviewer reads a lot: the diff and the code it touches. Sonnet is good enough to
spot the pattern and much cheaper per token. The verifier reads little, a few
functions around each candidate, but its decision is what people see, so it gets
Opus. Both are set in the agent files (`plugins/money-review/agents/`) and can be
changed there.

The coordinator, the skill that passes paths between the stages, never opens the
diff. The shell command starts it with `--model sonnet`.

## Subscription, not API

Everything runs through the `claude` CLI. Without `ANTHROPIC_API_KEY` in the
environment the CLI uses the logged-in subscription. `money-review` refuses to start
when the key is set, because the run would silently move to API billing.

`--bare` is not used: bare mode skips the subscription login and does not load
plugins.

## What the model is allowed to do

The diff is untrusted input: anyone who can open a merge request controls its text,
and a comment in the code can try to give the model instructions.

- `money-reviewer` and `money-verifier` have `Read`, `Grep` and `Glob` only. They cannot
  run commands or change files.
- In the shell command the coordinator gets the two plugin scripts (`prepare.sh`,
  `render.sh`), the agents, read tools, and write access to exactly one file,
  `report.json` in the output directory. It has no general shell.
- Posting is done by `scripts/gitlab.sh` or `scripts/github.sh` after the model has
  finished, from the JSON report, not by the model.

## Merge request state

The tool keeps no database. Its state lives in the merge request or pull request:

- the summary comment ends with `<!-- money-review:summary sha=<commit> -->`, the last
  reviewed commit;
- each comment on a line ends with `<!-- money-review:finding rule=<rule> file=<path> -->`.

On GitLab these are a note and discussions on the diff (`glab api`). On GitHub they are
a conversation comment and review comments on the right side of the diff (`gh api`).
The diff starts at the merge base of the head and the target branch: GitLab reports it,
GitHub reports the tip of the base branch, so the tool computes it from the fetched
commits (`refs/merge-requests/N/head` or `refs/pull/N/head`).

On the next run, if the recorded commit is an ancestor of the merge request head, only
the commits after it are reviewed. After a force push it is not an ancestor any more
and the whole merge request is reviewed again. A finding with the same rule and file
as an existing discussion is not posted again, because the model words the same bug
differently from run to run and line numbers move.

## Files of a run

`--out DIR` keeps them; otherwise they go to a temporary directory.

| File | What |
|---|---|
| `change.diff` | the diff that was reviewed |
| `report.json` | findings and rejected candidates |
| `claude.json` | the CLI's JSON output: turns, duration, API-equivalent cost |
| `worktree/` | with `--mr` or `--pr`, the checkout of the head; removed at the end |
