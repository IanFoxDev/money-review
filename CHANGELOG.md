# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Suppression of accepted findings: a `money-review: ignore RULE reason` comment on the
  line of a finding or the line above, and `ignore` entries in `.money-review.json`
  (rule or checklist, path glob, reason). A reason is required. Suppressed findings
  move to `suppressed` in the report, do not count for `--fail-on` and are not posted.

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

[Unreleased]: https://github.com/IanFoxDev/money-review/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/IanFoxDev/money-review/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/IanFoxDev/money-review/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/IanFoxDev/money-review/releases/tag/v0.1.0
