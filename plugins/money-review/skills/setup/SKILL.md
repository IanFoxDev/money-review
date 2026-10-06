---
name: setup
description: Install the money-review shell command (a wrapper in ~/.local/bin that runs the installed release). Run once after installing the plugin.
argument-hint: "[DIR]"
disable-model-invocation: true
allowed-tools: Bash
---

# money-review setup

Run this command once and show its output to the user as it is:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/install-cli.sh" $ARGUMENTS
```

If it printed a note about the PATH, repeat that note in one line. Do nothing else.
