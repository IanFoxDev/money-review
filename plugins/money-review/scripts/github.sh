#!/usr/bin/env bash
# GitHub pull request helpers on top of gh. Run inside the repository.
# Same commands and output as gitlab.sh, so bin/money-review treats both alike.
#
#   github.sh refs PR             JSON: iid, web_url, source/target branch, base/start/head sha,
#                                 fetch_ref
#   github.sh last-reviewed PR    commit recorded by the last summary comment, or nothing
#   github.sh post PR REPORT HEAD [SINCE]
#                                 update the summary comment and add one review comment
#                                 per finding that is not on the PR yet
#
# base_sha is the tip of the base branch, not the merge base: the caller computes
# the merge base from the fetched commits. Findings are matched to existing
# review comments by rule and file, as on GitLab.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gh="${MONEY_REVIEW_GH:-gh}"
summary_marker="<!-- money-review:summary"
repo="repos/{owner}/{repo}"

api() { "$gh" api "$@"; }

# All pages of a list endpoint as one JSON array.
api_list() { api --paginate "$1" | jq -s 'flatten'; }

cmd_refs() {
    api "$repo/pulls/$1" | jq '{
        iid: .number, web_url: .html_url,
        source_branch: .head.ref, target_branch: .base.ref,
        base_sha: .base.sha, start_sha: .base.sha, head_sha: .head.sha,
        fetch_ref: "refs/pull/\(.number)/head"
    }'
}

summary_comment() { # PR -> latest summary comment as JSON, or nothing
    api_list "$repo/issues/$1/comments?per_page=100" |
        jq -c --arg m "$summary_marker" '[.[] | select(.body | contains($m))] | sort_by(.updated_at) | last // empty'
}

cmd_last_reviewed() {
    summary_comment "$1" | jq -r '.body | capture("money-review:summary sha=(?<sha>[0-9a-f]+)").sha // empty'
}

cmd_post() {
    local pr="$1" report="$2" head="$3" since="${4:-}"
    local body comment_id payload tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    # Keys of findings that already have a review comment on the PR.
    api_list "$repo/pulls/$pr/comments?per_page=100" |
        jq -r '.[].body // "" | capture("money-review:finding rule=(?<r>[A-Z]+-[0-9]+) file=(?<f>[^ ]+)") | "\(.r) \(.f)"' \
        > "$tmp/existing" || true

    local posted=0 skipped=0 outside=0
    local count i finding key
    count="$(jq '.findings | length' "$report")"
    i=0
    while [ "$i" -lt "$count" ]; do
        finding="$(jq -c ".findings[$i]" "$report")"
        i=$((i + 1))
        key="$(jq -r '"\(.rule) \(.file)"' <<< "$finding")"
        if grep -qxF -- "$key" "$tmp/existing"; then
            skipped=$((skipped + 1))
            continue
        fi
        payload="$(jq -n --argjson f "$finding" --arg head "$head" '{
            body: ("**money-review \($f.severity | ascii_upcase) \($f.rule): \($f.title)**\n\n"
                + "**What happens:** \($f.scenario)\n\n**How to fix:** \($f.fix)\n\n"
                + "<!-- money-review:finding rule=\($f.rule) file=\($f.file) -->"),
            commit_id: $head, path: $f.file, line: $f.line, side: "RIGHT"
        }')"
        echo "$payload" > "$tmp/comment.json"
        if api -X POST "$repo/pulls/$pr/comments" --input "$tmp/comment.json" --silent 2>/dev/null; then
            posted=$((posted + 1))
        else
            # GitHub answers 422 for a line that is not part of the PR diff. The
            # finding stays in the summary comment.
            outside=$((outside + 1))
        fi
        echo "$key" >> "$tmp/existing"
    done

    body="$("$here/render.sh" "$report")"
    body="$body"$'\n\n'"Reviewed commit \`${head:0:12}\`"
    [ -n "$since" ] && body="$body, changes since \`${since:0:12}\`"
    body="$body."$'\n\n'"$summary_marker sha=$head -->"
    jq -n --arg b "$body" '{body: $b}' > "$tmp/summary.json"

    comment_id="$(summary_comment "$pr" | jq -r '.id // empty')"
    if [ -n "$comment_id" ]; then
        api -X PATCH "$repo/issues/comments/$comment_id" --input "$tmp/summary.json" --silent
    else
        api -X POST "$repo/issues/$pr/comments" --input "$tmp/summary.json" --silent
    fi
    echo "money-review: posted $posted comment(s), $skipped already on the PR, $outside outside the diff (in the summary only)" >&2
}

case "${1:-}" in
    refs) cmd_refs "${2:?PR number}" ;;
    last-reviewed) cmd_last_reviewed "${2:?PR number}" ;;
    post) cmd_post "${2:?PR number}" "${3:?report file}" "${4:?head sha}" "${5:-}" ;;
    *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
