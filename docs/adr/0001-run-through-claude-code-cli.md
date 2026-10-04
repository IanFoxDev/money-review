# 0001. Run through the Claude Code CLI, not the API

Date: 2026-10-04. Status: accepted.

## Context

The tool reviews merge requests that touch money. The people who run it are the
reviewers of that code: engineers and their lead. Most of them already pay for a
Claude subscription and use Claude Code every day.

A review bot built on the Anthropic API needs an API key, a billing account and a
budget owner. Every MR costs money on top of the subscription the team already has,
and someone has to approve that spend before the tool is even tried.

Claude Code can run non-interactively (`claude -p`). Without `ANTHROPIC_API_KEY` in
the environment it uses the subscription of the logged-in user. It also loads plugins
(`--plugin-dir`), validates output against a JSON Schema (`--json-schema`) and limits
turns (`--max-turns`).

## Decision

money-review is a Claude Code plugin. It runs in two ways, both through the CLI:

- interactively, as `/money-review` in the reviewer's own Claude Code session;
- from a shell or a script, as `bin/money-review`, which calls `claude -p` with the
  plugin directory and a JSON Schema for findings.

There is no code path that calls the Anthropic API directly.

`bin/money-review` refuses to start when `ANTHROPIC_API_KEY` is set, because the CLI
would silently switch to paid API billing. The flag `--allow-api-key` turns the check
off for people who want exactly that.

`--bare` is not used: bare mode skips the subscription login and does not load
plugins.

## Consequences

- Trying the tool costs nothing extra: install the plugin and run one command.
- A review still uses the reviewer's subscription limits. Keeping that usage low is a
  design goal of its own (see ADR 0003).
- Running in CI needs a token tied to one person's subscription
  (`claude setup-token`). That is fine for a personal repository; for a team it is a
  question for the team's plan, so CI mode is documented but not the default.
- The tool depends on Claude Code flags. The minimum supported CLI version is checked
  at start.
