#!/usr/bin/env bash
# Builds the working copy of one real-bug case: the repository at the case's
# base commit, committed on master, with the case's files as they are at its
# head commit copied over it and left uncommitted.
# Usage: eval/real/workdir.sh CASE DIR
#
# The copy has no history, so the reviewer cannot find the later fix in it.
# CLAUDE.md, AGENTS.md, .claude/ and .mcp.json of the reviewed project are
# removed: they would steer the review, and project settings can run hooks.
# DIR should be outside any directory with a CLAUDE.md (see eval/workdir.sh).
set -euo pipefail

real_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
c="${1:?usage: workdir.sh CASE DIR}"
work="${2:?usage: workdir.sh CASE DIR}"
spec="${EVAL_REAL_CASES:-$real_dir/cases}/$c/case.json"

[ -f "$spec" ] || { echo "workdir: no case $c" >&2; exit 2; }
base="$(jq -r .base "$spec")"
head="$(jq -r .head "$spec")"
bare="$("$real_dir/repo.sh" "$(jq -r .repo "$spec")" "$base" "$head")"

rm -rf "$work"
mkdir -p "$work"
git -C "$bare" archive "$base" | tar -x -C "$work"
find "$work" \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name AGENTS.md -o -name .mcp.json \) -type f -exec rm -f {} +
find "$work" -name .claude -type d -prune -exec rm -rf {} +
git -C "$work" init -q -b master
git -C "$work" add -A
git -C "$work" -c user.name=eval -c user.email=eval@example.com commit -qm base

jq -r '.files[]' "$spec" | while IFS= read -r file; do
    if git -C "$bare" cat-file -e "$head:$file" 2>/dev/null; then
        mkdir -p "$(dirname "$work/$file")"
        git -C "$bare" show "$head:$file" > "$work/$file"
    else
        rm -f "$work/$file"
    fi
done
