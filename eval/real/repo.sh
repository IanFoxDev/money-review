#!/usr/bin/env bash
# Prints the path of a local bare clone of a GitHub repository, cloning it or
# fetching the given commits when they are missing.
# Usage: eval/real/repo.sh OWNER/NAME [SHA...]
#
# Clones are blob-less (--filter=blob:none) and kept in EVAL_REPOS (default
# .eval-repos in the repository root), so a second run does not download again.
# EVAL_REAL_URL replaces https://github.com, for tests.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name="${1:?usage: repo.sh OWNER/NAME [SHA...]}"
shift
cache="${EVAL_REPOS:-$root/.eval-repos}"
bare="$cache/$(tr '/' '_' <<< "$name").git"

if [ ! -d "$bare" ]; then
    mkdir -p "$cache"
    git clone -q --bare --filter=blob:none "${EVAL_REAL_URL:-https://github.com}/$name" "$bare" >&2
fi
for sha in "$@"; do
    git -C "$bare" cat-file -e "$sha^{commit}" 2>/dev/null && continue
    git -C "$bare" fetch -q --filter=blob:none origin "$sha" >&2 ||
        { echo "repo: $name has no commit $sha" >&2; exit 2; }
done
echo "$bare"
