#!/usr/bin/env bash
# Builds the working copy of one eval case: the case's app committed on master,
# with the case's files copied over it and left uncommitted.
# Usage: eval/workdir.sh CASE DIR
#
# DIR should be outside any directory with a CLAUDE.md: Claude Code loads the
# CLAUDE.md files of every parent directory, and they would become part of the review.
set -euo pipefail

eval_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
c="${1:?usage: workdir.sh CASE DIR}"
work="${2:?usage: workdir.sh CASE DIR}"

[ -d "$eval_dir/cases/$c" ] || { echo "workdir: no case $c" >&2; exit 2; }
rm -rf "$work"
mkdir -p "$work"
app="$(jq -r '.app // "app"' "$eval_dir/cases/$c/case.json")"
cp -R "$eval_dir/$app/." "$work/"
git -C "$work" init -q -b master
git -C "$work" add .
git -C "$work" -c user.name=eval -c user.email=eval@example.com commit -qm base
cp -R "$eval_dir/cases/$c/files/." "$work/"
