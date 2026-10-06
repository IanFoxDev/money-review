#!/usr/bin/env bash
# Puts the money-review shell command on the PATH: a small wrapper in DIR (default
# ~/.local/bin) that runs the installed release of the plugin. The wrapper looks the
# plugin up at run time, so it keeps working after updates and in every Claude
# profile (CLAUDE_CONFIG_DIR) the plugin is installed in.
#
# Usage: install-cli.sh [DIR]
set -euo pipefail

dir="${1:-$HOME/.local/bin}"
target="$dir/money-review"
mkdir -p "$dir"

if [ -e "$target" ] && ! grep -q 'installed release of money-review' "$target" 2>/dev/null; then
    echo "install-cli: $target exists and is not the money-review wrapper; move it away first" >&2
    exit 2
fi

cat > "$target" <<'EOF'
#!/bin/sh
# Runs the installed release of money-review, from this or the default Claude profile.
for dir in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$HOME/.claude"; do
    p="$(jq -r '.plugins["money-review@money-review"][0].installPath // empty' "$dir/plugins/installed_plugins.json" 2>/dev/null)"
    [ -n "$p" ] && exec "$p/bin/money-review" "$@"
done
echo "money-review: the plugin is not installed (/plugin install money-review@money-review)" >&2
exit 2
EOF
chmod +x "$target"
echo "installed: $target"

case ":$PATH:" in
    *":$dir:"*) ;;
    *) echo "note: $dir is not on your PATH; add it to your shell profile, for example: export PATH=\"$dir:\$PATH\"" ;;
esac
command -v jq >/dev/null || echo "note: jq is required and was not found"
