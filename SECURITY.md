# Security

money-review sends the diff and the code it reads to Claude through your Claude Code
CLI, under your account. Anything the CLI may read, the review may send: do not run it
on code you are not allowed to share with Anthropic under your plan.

The code under review is untrusted input. If you find a way for a diff to make the
review do more than read files and write its report, for example run a command, write
another file, or post something other than the report to a merge request, do not open
a public issue. Report it privately through
[GitHub](https://github.com/IanFoxDev/money-review/security/advisories/new), or write to
ianfoxdeveloper@gmail.com.

Some things are by design and are not vulnerabilities:

- A diff can steer the model's findings: hide a bug, invent one, word one badly. The
  review is advice for a human reviewer, not a gate that can be trusted on its own.
- `--allow-api-key` runs on API billing when `ANTHROPIC_API_KEY` is set. That is the
  flag's purpose.

## Supported versions

Fixes go into the latest release only. Until 1.0 that is the latest `0.x` tag.
