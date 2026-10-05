#!/usr/bin/env bash
# GitLab merge request helpers on top of glab. Run inside the repository.
#
#   gitlab.sh refs MR             JSON: iid, web_url, source/target branch, base/start/head sha,
#                                 fetch_ref
#   gitlab.sh last-reviewed MR    commit recorded by the last summary note, or nothing
#   gitlab.sh post MR REPORT HEAD [SINCE]
#                                 update the summary note and open one discussion
#                                 per finding that is not on the MR yet
#
# Findings are matched to existing discussions by rule and file, so a re-run does
# not repeat a comment even when the model words it differently.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
glab="${MONEY_REVIEW_GLAB:-glab}"
summary_marker="<!-- money-review:summary"

api() { "$glab" api "$@"; }

# All pages of a list endpoint as one JSON array.
api_list() { api --paginate --output ndjson "$1" | jq -s 'flatten'; }

mr_path() { echo "projects/:id/merge_requests/$1"; }

cmd_refs() {
    api "$(mr_path "$1")" | jq '{
        iid, web_url, source_branch, target_branch,
        base_sha: .diff_refs.base_sha,
        start_sha: .diff_refs.start_sha,
        head_sha: .diff_refs.head_sha,
        fetch_ref: "refs/merge-requests/\(.iid)/head"
    }'
}

summary_note() { # MR -> latest summary note as JSON, or nothing
    api_list "$(mr_path "$1")/notes?per_page=100&sort=desc&order_by=updated_at" |
        jq -c --arg m "$summary_marker" '[.[] | select(.body | contains($m))] | first // empty'
}

cmd_last_reviewed() {
    summary_note "$1" | jq -r '.body | capture("money-review:summary sha=(?<sha>[0-9a-f]+)").sha // empty'
}

finding_key() { jq -r '"\(.rule) \(.file)"'; }

cmd_post() {
    local mr="$1" report="$2" head="$3" since="${4:-}"
    local refs body note_id payload tmp
    refs="$(cmd_refs "$mr")"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    # Keys of findings that already have a discussion on the MR.
    api_list "$(mr_path "$mr")/discussions?per_page=100" |
        jq -r '.[].notes[0].body // "" | capture("money-review:finding rule=(?<r>[A-Z]+-[0-9]+) file=(?<f>[^ ]+)") | "\(.r) \(.f)"' \
        > "$tmp/existing" || true

    local posted=0 skipped=0 outside=0
    local count i finding key
    count="$(jq '.findings | length' "$report")"
    i=0
    while [ "$i" -lt "$count" ]; do
        finding="$(jq -c ".findings[$i]" "$report")"
        i=$((i + 1))
        key="$(finding_key <<< "$finding")"
        if grep -qxF -- "$key" "$tmp/existing"; then
            skipped=$((skipped + 1))
            continue
        fi
        payload="$(jq -n --argjson f "$finding" --argjson r "$refs" '{
            body: ("**money-review \($f.severity | ascii_upcase) \($f.rule): \($f.title)**\n\n"
                + "**What happens:** \($f.scenario)\n\n**Fix:** \($f.fix)\n\n"
                + "<!-- money-review:finding rule=\($f.rule) file=\($f.file) -->"),
            position: {
                position_type: "text",
                base_sha: $r.base_sha, start_sha: $r.start_sha, head_sha: $r.head_sha,
                old_path: $f.file, new_path: $f.file, new_line: $f.line
            }
        }')"
        echo "$payload" > "$tmp/discussion.json"
        if api -X POST "$(mr_path "$mr")/discussions" --input "$tmp/discussion.json" \
            -H "Content-Type: application/json" --silent 2>/dev/null; then
            posted=$((posted + 1))
        else
            # The line is not part of the MR diff, GitLab refuses an inline
            # position there. The finding stays in the summary note.
            outside=$((outside + 1))
        fi
        echo "$key" >> "$tmp/existing"
    done

    body="$("$here/render.sh" "$report")"
    body="$body"$'\n\n'"Reviewed commit \`${head:0:12}\`"
    [ -n "$since" ] && body="$body, changes since \`${since:0:12}\`"
    body="$body."$'\n\n'"$summary_marker sha=$head -->"
    jq -n --arg b "$body" '{body: $b}' > "$tmp/note.json"

    note_id="$(summary_note "$mr" | jq -r '.id // empty')"
    if [ -n "$note_id" ]; then
        api -X PUT "$(mr_path "$mr")/notes/$note_id" --input "$tmp/note.json" \
            -H "Content-Type: application/json" --silent
    else
        api -X POST "$(mr_path "$mr")/notes" --input "$tmp/note.json" \
            -H "Content-Type: application/json" --silent
    fi
    echo "money-review: posted $posted comment(s), $skipped already on the MR, $outside outside the diff (in the summary only)" >&2
}

case "${1:-}" in
    refs) cmd_refs "${2:?MR number}" ;;
    last-reviewed) cmd_last_reviewed "${2:?MR number}" ;;
    post) cmd_post "${2:?MR number}" "${3:?report file}" "${4:?head sha}" "${5:-}" ;;
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
