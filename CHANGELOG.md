# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-27

### Added

- Four checklists: refunds and reversals (REV), subscription lifecycle (SUB), periods
  and dates (TIME), data completeness for syncs, backfills and aggregates (DATA).
- The provider checklist reads provider messages too: loose values (PSP-5), pending
  results taken as final (PSP-6), amounts not checked against the order (PSP-7),
  unsigned messages (PSP-8), late events (PSP-9), events acknowledged and never applied
  (PSP-10); PSP-3 also covers a default branch that maps unknown events to a charge.
- MONEY-8 (amounts in different units or scales), MONEY-9 (a missing value that
  defaults to moving money), IDEM-12 (a dedup check that can never match), TX-10 (a
  second write path that skips the side effects of the main one).
- A category also matches on the path of a file in scope, so a `PostbackController.php`
  gets the provider checklist when the changed lines do not name the provider.

### Changed

- The verifier treats a scenario that a comment at the code states as a decision (a
  paid purchase stands, only the counter is capped) as already weighed: it keeps only
  what the decision leaves out, such as money with no trace in data or a docblock that
  promises the opposite, with severity `low`, and rejects the rest. A rule stated in a
  repository doc (README, a module's notes, `docs/`) or in a named constant counts the
  same, and the verifier reads the module's notes before it calls a behaviour
  unintended, also when the diff does not touch them.
- IDEM-1 covers an API endpoint that moves money with no idempotency key while the
  other money endpoints of the same API take one, and a stored key whose saved answer
  is replayed for a request with a different body.
- A file in scope only through `money_paths` gets the four base checklists (TX, RACE,
  IDEM, MONEY); the others load when the file matches their patterns.
- `REV`, `SUB`, `TIME` and `DATA` are built-in prefixes and cannot name private rules.
- "Do not report" cases for DATA-5 (a migration the default branch has not run),
  SUB-4 (an expired subscription renewed from now with no access in the gap), MONEY-9
  (a fallback that money paths cannot reach), IDEM-12 (a type the write layer casts),
  IDEM-5 (an action a person starts by hand, where running it again is a new request)
  and PSP-3 (a handler behind a provider setting that sends one event type, when the
  code or its configuration shows that setting).
- Eval: a finding with the right rule counts when its line is within 10 lines of the
  anchor range (was 5). Reviews that point at the start of the function or the
  missing guard were scored as false alarms. The stored runs of the real set
  (0.8.3 baseline, 0.9.1) score the same with the new window.
- Eval: new baselines for both sets from a full run before this release
  ([docs/eval-results/2026-10-27-1.0.md](docs/eval-results/2026-10-27-1.0.md)). Gaps in
  the synthetic cases that the reviewer found are fixed in the cases; findings that
  are the same bug under a newer rule are accepted.

## [0.9.1] - 2026-10-20

### Fixed

- `--pr`, `--mr` and `--commits` did not load the private config: the review runs in a
  temporary worktree, and the private folder was looked up by the worktree's directory
  name instead of the repository's. Any linked worktree now uses the main checkout's name.

## [0.9.0] - 2026-10-20

### Added

- Payment providers checklist (PSP): a provider change marked done because the request
  was accepted (PSP-1), our expiry or status taken as "the provider will not charge"
  (PSP-2), notifications turned into payments whatever their type (PSP-3), a fix for one
  provider or path while the siblings keep the bug (PSP-4).
- IDEM-11: a dedup key (unique index, upsert filter, `ReplacingMergeTree` key) with a
  field that is filled later, so two versions of one event become two rows.
- Private rules: `rules` in the config adds your own checklists with their own prefix,
  loaded by a pattern or for every money change; the file stays with your config.
- Private folder: `plugins/money-review/private/<repository name>/config.json` (in
  `.gitignore`, template in `private.example/`) goes over the project config and adds its
  rules and invariants; `MONEY_REVIEW_PRIVATE` points at another directory. The README
  shows how a bug becomes a public rule, a private rule or an invariant.
- Invariants: `invariants` in the config become a checklist (`INV-1`, ...) that every
  review checks the change against.
- The reviewer looks for siblings of a provider-specific change and for what the
  provider does regardless of our state; the verifier gets the config context and takes
  provider behaviour stated there or in the project's rules as fact.
- Eval: cases for PSP-1, PSP-2, PSP-3 and IDEM-11 and a clean retention case; on the
  real-bug set recall stays at 61%, cost per run 0.39 USD
  ([results](docs/eval-results/2026-10-19-providers.md)).
- `eval/real/run.sh --resume` keeps the finished runs of a stopped run.

### Fixed

- A finding whose file is an absolute path inside the repository is reported with the
  relative path, so comments land on the file and suppressions match it.

## [0.8.3] - 2026-10-17

### Added

- Shell command: `--quiet` suppresses the usage summary on stderr. Thanks @Sinkleberg (#9).

## [0.8.2] - 2026-10-13

### Fixed

- The reviewer reads every rule it was given. It used to get the path of each chosen
  checklist and often opened only the ones it judged relevant; now the checklists of a
  group come as one file, read in full before the diff. On the eval: recall 91% to 94%,
  second bugs 32 to 37 of 45, precision 100% and no alarm on clean code as before
  ([eval](docs/eval-results/2026-10-12-checklist-file.md)).

## [0.8.1] - 2026-10-09

### Added

- `--timeout SECONDS` (default 1200, `0` for no limit, or `MONEY_REVIEW_TIMEOUT`): a review
  that runs longer is stopped and exits with 4, and is not tried again. A run that waits
  for a background agent never ends by itself; the skill already says to run agents in
  the foreground, this is the guard when that is not followed.

## [0.8.0] - 2026-10-08

### Added

- A second look: when the reviewer finds something, it reviews the change once more,
  told what it already found, for other money bugs next to it. One more reviewer pass,
  only on changes with a finding; `review.second_pass: false` turns it off.

### Eval

- A bug in `case.json` can name other places where it can fairly be reported (`also`).
- New baseline: recall 91% (87% without the second look), precision 100%, second bugs
  31 of 45 (25), no false alarm in 36 runs of clean cases.

## [0.7.0] - 2026-10-08

### Added

- Rules: MONEY-7 (an amount from the wrong source, such as the full amount after a
  partial refund), TX-9 (an event that stops carrying what money consumers read, or is
  published when the state did not change), IDEM-10 (a provider decline or business
  error with no path). MONEY-5 also covers negative input amounts and reversals booked
  in the wrong direction.
- `MONEY-0`: a money bug no rule covers, reported when there is a concrete failure
  scenario. Before, the reviewer could only report what the checklists named.

### Changed

- The verifier moves a real finding to the rule that fits (or `MONEY-0`) instead of
  rejecting it for the wrong rule.

### Fixed

- The skill runs its agents in the foreground. A reviewer started in the background
  left a headless run waiting for over an hour and ending with no report.

### Eval

- Ten cases have a second, quieter bug that a plain review prompt found next to the
  planted one; a new case books a chargeback for the full amount in the wrong direction.
  `clean-chargeback-webhook` and `clean-commission-rounding` had real bugs and are fixed.
- New baseline, 50 cases three times: recall 87% (80% before on the same cases),
  precision 100%, no false alarm in 36 runs of clean cases.

## [0.6.0] - 2026-10-07

### Added

- `--commits` reviews one commit or a range of commits (`abc1234`, `HEAD~3..`,
  `master..feature`) before there is a pull or merge request. Uncommitted edits stay
  out; from a shell the review runs in a temporary worktree at the end of the range.
- Each finding in the report shows the code around its line, numbered, with the line
  marked. The code is read from the file after the review (only files in the diff),
  and is kept in the JSON report as `excerpt`.
- A report with more than one finding starts with a table: severity, rule, file and
  line, problem.

### Changed

- Findings are numbered, and "Fix" is now "How to fix", also in pull and merge
  request comments.

### Eval

- The working copies of the eval cases are built in a temporary directory, so no
  CLAUDE.md from the directories above the repository gets into a review.
- `eval/bare.sh` runs the same cases through a plain "review this change" prompt, for
  comparison.
- New baseline, 2026-10-07: every case three times, recall 100%, precision 98%, no
  false alarm in 36 runs of clean cases. No regression against 2026-10-06.

## [0.5.2] - 2026-10-06

### Added

- `/money-review:setup` puts the shell command on the `PATH`: a wrapper in
  `~/.local/bin` that runs the installed release, in the Claude profile of
  `CLAUDE_CONFIG_DIR` or the default one.
- Inside Claude Code the review agents cannot open files that may hold secrets either:
  a plugin hook refuses their `Read`, `Grep` and `Glob` calls on paths that match
  `secrets`. Before, only the shell command set deny rules, and `/money-review` needed
  them in the user's settings.

### Fixed

- README: the shell command is a wrapper that runs the installed release. The link into
  the marketplace clone it suggested before runs the tip of `master`, which is not the
  release since the marketplace serves tags.

## [0.5.1] - 2026-10-06

### Added

- Files that may hold secrets stay away from the model: `.env`, keys, certificates and
  the other `secrets` patterns in the config are cut from the diff, listed in the
  report, and denied to the agents' `Read` (which also covers `Grep` and subagents) in
  the shell command.

### Changed

- The marketplace installs the tagged release, not the tip of `master`: the plugin
  source is the `plugins/money-review` directory at tag `v0.5.1`.
- README: a seat on a Team or Enterprise plan works too; deny rules for
  `/money-review` inside Claude Code.

## [0.5.0] - 2026-10-06

### Added

- Eval schedule in `docs/eval.md`: when to run which cases (releases, checklist and
  prompt changes, model changes) and what counts as a regression.
- `eval/compare.sh BASE NEW`: compares two eval runs case by case, calls out a model
  change and exits with 1 on a regression.
- Eval summaries record the money-review version, the commit, the Claude Code version
  and the model ids that ran; `eval/run.sh` warns when the models differ from the
  baseline.
- The usage line of every review names the models it used.
- `eval/baseline/summary.json`: a full run of all 49 cases, three times each, to
  compare later runs with. 111 of 111 planted bugs found, one low false alarm, no
  false alarm in 36 runs on clean code (`docs/eval-results/2026-10-06-baseline.md`).

## [0.4.0] - 2026-10-06

### Added

- Suppression of accepted findings: a `money-review: ignore RULE reason` comment on the
  line of a finding or the line above, and `ignore` entries in `.money-review.json`
  (rule or checklist, path glob, reason). A reason is required. Suppressed findings
  move to `suppressed` in the report, do not count for `--fail-on` and are not posted.
- `docs/team.md`: how a team runs it by hand on pull requests, without a CI token.
- Eval cases for MONEY-3, MONEY-5 and TX-5, each with a clean pair.
- `--retries N` (default 1): when Claude ends without a report (an overloaded API, a
  crash), the review runs again after 30 seconds. A usage or rate limit is not retried.
- Findings carry `code`, the text of their line. `fix-lines.sh` moves a finding to the
  line that holds that text when the model counted lines in the diff instead of the
  file (seen as line 1 for a bug further down).

### Changed

- Two IDEM eval cases rebuilt so the guard the change removes is the only one;
  `idem-payout-rerun` is replaced by `idem-cashback-rerun`.

### Fixed

- Paths with spaces in `--out`, `--diff` and `--config`: the shell command quotes
  the arguments it passes to the skill (#8).

## [0.3.0] - 2026-10-05

### Added

- Checklists for MongoDB, Redis and message brokers: conditional updates instead of
  row locks, multi-document transactions, writes followed by a Kafka produce, BSON
  doubles. New rules: TX-7 (a call inside a transaction without the session), TX-8
  (side effects in a retried transaction callback), RACE-7 (Redis locks that do not
  hold), RACE-8 (money decisions read from a secondary or a cache), IDEM-7 (offset
  commit or ack before the work), IDEM-8 (events of one account out of order), IDEM-9
  (a duplicate key error caught inside a MongoDB transaction, which aborts it).
- Large changes are reviewed in groups of files: one reviewer pass per group, in
  parallel, then one verifier pass. Limits in `review.group_lines` (800) and
  `review.max_groups` (6). The report says how many files touch money, how many were
  reviewed, and lists the files over the limit.
- A second eval app in PHP and Go on MongoDB, Kafka and Redis, with 18 cases; cases
  can name the app they run on.

### Changed

- Triage covers Go (`*.go`, without tests, mocks and generated files), MongoDB drivers
  for PHP and Go, Kafka and RabbitMQ clients and Redis locks. A read with `findOne`
  followed by `updateOne` now loads the race checklist; before, such a file only got
  the arithmetic one, and Go files were never reviewed.
- Money words in triage match in any letter case, so Go's `Amount` and `Balance` count.
- Triage also looks for money words in the file path, so a Kafka consumer in
  `credits/` is reviewed even when the changed lines only commit offsets.
- Producing to Kafka or RabbitMQ loads the idempotency checklist too (message keys,
  ordering, dedup).

### Fixed

- Triage no longer prints "grep: write error: Broken pipe" where SIGPIPE is ignored
  (CI runners, some containers). The lines went to stderr, which the skill reads
  together with the JSON from `prepare.sh`.

## [0.2.0] - 2026-10-05

### Added

- GitHub pull requests: `--pr N`, with `--post` and `--full` working as for GitLab.
  Findings become review comments on the line, the summary is one conversation
  comment that is edited in place.

## [0.1.0] - 2026-10-05

First release.

### Added

- Plugin and marketplace manifests.
- Checklists for transaction boundaries, races, idempotency and money arithmetic.
- `money-reviewer` and `money-verifier` agents and the report JSON Schema.
- Triage without a model: changes that do not touch money are not sent to Claude.
- `/money-review:money-review` skill: review the current branch against its base.
- `bin/money-review` for shell use: refuses to run with `ANTHROPIC_API_KEY` set, never
  starts Claude for a change without money, prints Markdown or JSON, `--fail-on` exit
  code.
- GitLab merge requests: `--mr N` reviews the MR in a temporary worktree, `--post`
  opens a discussion per finding and keeps one summary note, later runs check only
  commits added since the last review (`--full` to review everything again).
- Eval: a billing app with 25 cases (20 bugs, 5 clean), a runner and scoring with
  precision and recall per category (`eval/`, `docs/eval.md`).
- The verifier keeps a bug that only the current callers hide (an outer transaction
  in every caller, another safety layer) as `low`, and says what protects it today.
- A finding that points past the end of its file moves to the first added line of
  that file.

[Unreleased]: https://github.com/IanFoxDev/money-review/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/IanFoxDev/money-review/compare/v0.9.1...v1.0.0
[0.9.1]: https://github.com/IanFoxDev/money-review/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/IanFoxDev/money-review/compare/v0.8.3...v0.9.0
[0.8.3]: https://github.com/IanFoxDev/money-review/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/IanFoxDev/money-review/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/IanFoxDev/money-review/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/IanFoxDev/money-review/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/IanFoxDev/money-review/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/IanFoxDev/money-review/compare/v0.5.2...v0.6.0
[0.5.2]: https://github.com/IanFoxDev/money-review/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/IanFoxDev/money-review/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/IanFoxDev/money-review/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/IanFoxDev/money-review/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/IanFoxDev/money-review/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/IanFoxDev/money-review/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/IanFoxDev/money-review/releases/tag/v0.1.0
