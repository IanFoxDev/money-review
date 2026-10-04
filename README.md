# money-review

Code review for changes that move money. A Claude Code plugin that reads a diff and
looks only for the bugs that cost money: an HTTP call to the payment provider inside a
database transaction, check-then-act without a lock, a webhook handler that credits
twice when the provider retries, a float where cents should be.

Every finding comes with a failure scenario: what happens, in which order, and what it
costs. A finding without one is dropped.

It runs on your Claude subscription through the Claude Code CLI. No API key, no extra
bill per merge request.

Status: early development, nothing to install yet.

## License

MIT
