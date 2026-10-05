# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/IanFoxDev/money-review/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/IanFoxDev/money-review/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/IanFoxDev/money-review/releases/tag/v0.1.0
