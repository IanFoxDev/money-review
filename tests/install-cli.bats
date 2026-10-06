#!/usr/bin/env bats

setup() {
    install="$BATS_TEST_DIRNAME/../plugins/money-review/scripts/install-cli.sh"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    bin="$HOME/.local/bin"
}

plugin_at() { # config-dir install-path: registers an installed plugin with a fake bin
    mkdir -p "$1/plugins" "$2/bin"
    jq -n --arg p "$2" '{plugins: {"money-review@money-review": [{version: "0.5.1", installPath: $p}]}}' > "$1/plugins/installed_plugins.json"
    printf '#!/bin/sh\necho "ran %s $*"\n' "$2" > "$2/bin/money-review"
    chmod +x "$2/bin/money-review"
}

@test "the wrapper runs the installed release" {
    plugin_at "$HOME/.claude" "$BATS_TEST_TMPDIR/cache/0.5.1"
    run "$install"
    [ "$status" -eq 0 ]
    [[ "$output" == *"installed: $bin/money-review"* ]]
    run "$bin/money-review" --pr 1
    [ "$output" = "ran $BATS_TEST_TMPDIR/cache/0.5.1 --pr 1" ]
}

@test "the wrapper prefers the profile in CLAUDE_CONFIG_DIR" {
    plugin_at "$HOME/.claude" "$BATS_TEST_TMPDIR/personal"
    plugin_at "$HOME/.claude-work" "$BATS_TEST_TMPDIR/work"
    "$install" > /dev/null
    CLAUDE_CONFIG_DIR="$HOME/.claude-work" run "$bin/money-review"
    [ "$output" = "ran $BATS_TEST_TMPDIR/work " ]
}

@test "without the plugin the wrapper says how to install it" {
    "$install" > /dev/null
    run "$bin/money-review"
    [ "$status" -eq 2 ]
    [[ "$output" == *"/plugin install money-review@money-review"* ]]
}

@test "a directory off the PATH gets a note" {
    PATH="/usr/bin:/bin" run "$install" "$BATS_TEST_TMPDIR/tools"
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not on your PATH"* ]]
}

@test "a foreign file is not overwritten, the wrapper is" {
    mkdir -p "$bin"
    echo "something else" > "$bin/money-review"
    run "$install"
    [ "$status" -eq 2 ]
    [ "$(cat "$bin/money-review")" = "something else" ]
    rm "$bin/money-review"
    "$install" > /dev/null
    run "$install"
    [ "$status" -eq 0 ]
}
