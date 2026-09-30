#!/usr/bin/env bash
# Uploads every scan listed in $OUT/scans.tsv to the hub: one request per file,
# the scanner's own output plus a small metadata block (hub API: POST /api/v1/scans).
# Without HUB_URL (the hub isn't deployed yet) it only prints what it would send.
set -euo pipefail

OUT="${OUT:?}"
: "${SCAN_TYPE:?production | fix_pr | release_verify}"
: "${REPO_FULL:?owner/name of the scanned repository}"
: "${COMMIT_SHA:?}"
BRANCH="${BRANCH:-}"
PR_NUMBER="${PR_NUMBER:-}"; PR_HEAD="${PR_HEAD:-}"; PR_BASE="${PR_BASE:-}"
RUN_ID="${RUN_ID:?}"; RUN_REPO="${RUN_REPO:-}"; RUN_URL="${RUN_URL:-}"

while IFS=$'\t' read -r file scanner target format outcome started completed; do
  meta="$OUT/$file.meta.json"
  # Grype JSON has no package list; count packages from the CycloneDX copy
  # Grype wrote in the same run, so the hub can check the scan isn't empty.
  pkgs=""
  extra="$OUT/extra/${file%.json}.cdx.json"
  if [ "$format" = "grype-json" ] && [ -s "$extra" ]; then
    pkgs=$(jq '[.components[]? | select(.purl and .type != "file")] | length' "$extra")
  fi
  jq -n \
    --arg owner "${REPO_FULL%%/*}" --arg name "${REPO_FULL##*/}" \
    --arg commit "$COMMIT_SHA" --arg branch "$BRANCH" --arg type "$SCAN_TYPE" \
    --arg target "$target" --arg runId "$RUN_ID" --arg runRepo "$RUN_REPO" --arg runUrl "$RUN_URL" \
    --arg scanner "$scanner" --arg format "$format" --arg outcome "$outcome" \
    --arg started "$started" --arg completed "$completed" \
    --arg prNumber "$PR_NUMBER" --arg prHead "$PR_HEAD" --arg prBase "$PR_BASE" --arg pkgs "$pkgs" '
    {
      repository: { owner: $owner, name: $name },
      commitSha: $commit, type: $type, target: $target,
      runId: $runId, scanner: $scanner, format: $format, outcome: $outcome,
      startedAt: $started, completedAt: $completed
    }
    + (if $branch  != "" then { branch: $branch } else {} end)
    + (if $runRepo != "" then { runRepository: $runRepo } else {} end)
    + (if $runUrl  != "" then { runUrl: $runUrl } else {} end)
    + (if $pkgs != "" then { packagesScanned: ($pkgs | tonumber) } else {} end)
    + (if $prNumber != "" then { pullRequest: { number: ($prNumber | tonumber), headRef: $prHead, baseRef: $prBase } } else {} end)
    ' > "$meta"

  if [ -z "${HUB_URL:-}" ]; then
    echo "HUB_URL not set: not uploading $file ($scanner · $target · $outcome). Metadata:"
    cat "$meta"
    continue
  fi

  echo "Uploading $file ($scanner · $target · $outcome)"
  args=(-sS --fail-with-body -X POST "$HUB_URL/api/v1/scans"
        -H "Authorization: Bearer ${HUB_CI_TOKEN:?}"
        -F "metadata=<$meta;type=application/json")
  if [ -s "$OUT/$file" ]; then
    gzip -kf "$OUT/$file"
    args+=(-F "file=@$OUT/$file.gz;type=application/gzip")
  fi
  curl "${args[@]}"
  echo
done < "$OUT/scans.tsv"
