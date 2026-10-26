# Real-bug eval

The cases in `eval/cases/` are written for this tool, against its own rules, on two
small apps. They show whether a rule works; they cannot show what the tool misses in
code nobody wrote for it. This set does: every case is a money bug that shipped in an
open-source project and was fixed there later.

## What a case is

`cases/<name>/case.json` names a repository and commits; no code of the project is kept
here. The harness clones the repository (blob-less, into `.eval-repos/`), builds a
working copy and runs money-review on it.

```json
{
  "repo": "owner/name",
  "license": "Apache-2.0",
  "mode": "introducer",
  "base": "<sha>",
  "head": "<sha>",
  "fix": "<sha of the upstream fix>",
  "date": "2026-08-09",
  "files": ["api/transactions.go"],
  "title": "What the change gets wrong",
  "bugs": [
    {
      "rules": ["MONEY-7"],
      "class": "MONEY",
      "file": "api/transactions.go",
      "anchor": "regex, first match in the file at head",
      "anchor_end": "optional regex, end of the range (first match after anchor)",
      "also": [{"file": "another place where the bug can fairly be reported", "anchor": "regex", "anchor_end": "optional"}],
      "note": "the mechanism, in our words"
    }
  ],
  "acceptable": [{"rules": ["TX-3"], "file": "a real issue the case is not about: neither a hit nor a false alarm",
                  "anchor": "optional regex: only these lines, as for a bug", "anchor_end": "optional"}]
}
```

The working copy is the tree at `base`, committed, with `files` as they are at `head`
copied over it. That uncommitted change is what money-review reviews. The copy has no
history, so the later fix is not there to find, and the project's `CLAUDE.md`,
`AGENTS.md`, `.claude/` and `.mcp.json` are removed.

Modes:

- `introducer`: `head` is the commit that brought the bug in, `base` its parent. This
  is the review the tool would have done on that pull request.
- `reverse`: there is no usable introducing commit (the bug was always there, or it came
  in with a large refactor). `base` is the fix and `head` its parent, so the change reads
  as the fix being undone. Easier than `introducer`: a removed lock or check is a hint.
- `control`: the fix itself (`base` is its parent, `head` the fix) and no bugs. A finding
  on it is a false alarm on correct money code.

`rules` are the rules of today's checklists that fit best. `class` is the family the
bug belongs to; a class such as `NEW-TIME` marks a bug no current rule covers, so the
eval also shows which families are missing.

## Scoring

The same as the synthetic eval (`eval/score.sh`): file, line within 10 lines of the anchor
range, and rule. Here the loose recall (within 5 lines, any rule) is the main number,
because the right rule often does not exist yet. Recall by family is reported by `class`, and the summary adds recall by mode, before
and after `EVAL_CUTOFF` (default 2026-06-01, a date after the models' training data),
and how many bug cases were found in every run, in some runs or never.

## Running

```bash
eval/real/run.sh --runs 3                 # every case
eval/real/run.sh blnk-inflight-dryrun-amount
eval/real/workdir.sh <case> /tmp/x        # look at a working copy
```

The first run clones the repositories; some are large. Clones stay in `.eval-repos/`
(`EVAL_REPOS` to choose another place).

## Adding a case

1. Find a fix commit for a money bug. Read its diff: the bug must be real, the fix small.
2. Find the commit that brought the bug in (`git log -S'<line the fix removes>'`). If it
   is a refactor or a rename, go further back; if there is none, use `reverse`.
3. List in `files` the source files of that commit that matter, without tests. Keep the
   change under about 400 lines.
4. Anchor the bug in the file as it is at `head`; check with `eval/real/expected.sh <case>`.
5. Describe the bug in your own words. Do not copy code or commit messages: the projects
   have their own licenses (some AGPL or Elastic), and the case stores only commit ids,
   paths and our description.
6. Prefer fixes made after the reviewing models' training cutoff: an older fix may be
   remembered. `date` is kept for that.
