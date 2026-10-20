# Private rules

Copy this directory to `private/` next to it (`plugins/money-review/private/`). That
directory is in `.gitignore`: what you put there stays on your machine.

```
private/
  <repository name>/          the directory name of the repository you review
    config.json               same fields as .money-review.json
    rules/
      <name>.md               your checklists, one prefix per file
```

money-review picks `private/<repository name>/config.json` by the name of the
repository's top directory (`payments-api` for `~/work/payments-api`). Set
`MONEY_REVIEW_PRIVATE` to a directory to use another one.

The private config goes over the project's `.money-review.json` like that file goes over
the defaults, with one difference: its `rules` and `invariants` are added to the
project's, not put in their place. Rule file paths are relative to the config file.

See "Private rules" in the [README](../../../README.md#private-rules) for how to turn a
bug you found into a rule.
