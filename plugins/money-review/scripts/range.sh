#!/usr/bin/env bash
# Resolves the commits to review into the start and the head of the change.
# Prints {"start": "<sha>", "head": "<sha>"}.
#
# Usage: range.sh RANGE
#   SHA       that one commit (against its first parent)
#   A..B      the commits on B since it left A: from their merge base to B
#   A...B     the same
#   A..       A to HEAD
set -euo pipefail

range="${1:?usage: range.sh RANGE}"
die() { echo "range: $1" >&2; exit 2; }

commit() { # ref -> sha
    git rev-parse --verify --quiet "${1:-HEAD}^{commit}" || die "no commit ${1:-HEAD}"
}

case "$range" in
    *...*) from="${range%%...*}"; to="${range#*...}" ;;
    *..*) from="${range%%..*}"; to="${range#*..}" ;;
    *) from="" ; to="$range" ;;
esac

head="$(commit "$to")"
if [ "$range" = "$to" ]; then
    # One commit. A root commit has no parent: compare it with the empty tree.
    start="$(git rev-parse --verify --quiet "$head^1^{commit}" || git hash-object -t tree /dev/null)"
else
    start="$(git merge-base "$(commit "$from")" "$head")" || die "no common commit in $range"
fi
[ "$start" != "$head" ] || die "$range has no commits"

jq -n --arg s "$start" --arg h "$head" '{start: $s, head: $h}'
