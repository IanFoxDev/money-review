#!/usr/bin/env bash
# Final deterministic touches on a report: moves findings that point past the end
# of their file (fix-lines.sh), sets aside findings the team accepted with an
# ignore comment or config entry (suppress.sh) and attaches the coverage from
# prepare.sh.
# Usage: finish.sh REPORT DIFF PREPARED_JSON      (run in the repository root)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
report="${1:?usage: finish.sh REPORT DIFF PREPARED_JSON}"
diff="${2:?usage: finish.sh REPORT DIFF PREPARED_JSON}"
prepared="${3:?usage: finish.sh REPORT DIFF PREPARED_JSON}"

"$here/fix-lines.sh" "$report" "$diff"
"$here/suppress.sh" "$report" "$prepared"

if [ -f "$prepared" ]; then
    jq --slurpfile p "$prepared" '. + {coverage: ($p[0].coverage // null)} | if .coverage == null then del(.coverage) else . end' \
        "$report" > "$report.tmp"
    mv "$report.tmp" "$report"
fi
