# 0002. Bash, jq and a JSON config

Date: 2026-10-04. Status: accepted.

## Context

Before any model runs, the tool has to decide whether a diff touches money at all and
which checklists apply (see ADR 0003). That step runs on every merge request, on a
developer laptop and in CI images we do not control: PHP images, Node images, plain
Alpine. It must not need a build step or a language runtime of its own.

Claude Code itself is a native binary, so we cannot count on Node or Python being
there. Git and a shell are always there. `gh` and `glab`, which later steps use to
read and comment on merge requests, are separate binaries too.

## Decision

Scripts are Bash, compatible with Bash 3.2 (the macOS default): no associative arrays,
no `mapfile`. JSON is handled with `jq`, the only extra dependency.

The project config is JSON, `.money-review.json` in the repository root. YAML would be
nicer to write, but reading it from Bash needs `yq` or Python, a second dependency for
one file. The config is merged over the plugin defaults with `jq` (`defaults * config`):
objects merge by key, arrays and strings replace.

Patterns are extended regular expressions (`grep -E`). Path globs use Bash pattern
matching, where `*` also matches `/`.

Tests use bats, linting uses shellcheck. Neither is needed at runtime.

## Consequences

- Installing the plugin is enough on any machine with `jq`.
- JSON has no comments, so the documented example config lives in `docs/`.
- If the scripts outgrow Bash (GitLab and GitHub APIs, incremental review state), the
  fallback is a small Go binary shipped per platform, not a second scripting language.
