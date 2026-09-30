#!/usr/bin/env bash
# Runs Trivy, Grype and OSV-Scanner on the repo folder and the Docker image.
# Writes one file per scan to $OUT, plus $OUT/scans.tsv:
#   file <TAB> scanner <TAB> target <TAB> format <TAB> outcome <TAB> startedAt <TAB> completedAt
# Scan files go outside the repo folder so no scanner reads another scanner's output.
set -uo pipefail

SRC="${SRC:-$PWD}"
OUT="${OUT:?set OUT to an output folder}"
LOCAL_IMAGE="${LOCAL_IMAGE:?set LOCAL_IMAGE to the image built by CI}"
TARGET_IMAGE="${TARGET_IMAGE:?set TARGET_IMAGE to the image name the hub should track}"
TRIVY="${TRIVY_IMAGE:-aquasec/trivy:latest}"
GRYPE="${GRYPE_IMAGE:-anchore/grype:latest}"
OSV="${OSV_IMAGE:-ghcr.io/google/osv-scanner:latest}"
SOCK=(-v /var/run/docker.sock:/var/run/docker.sock)

mkdir -p "$OUT" "$OUT/extra"
: > "$OUT/scans.tsv"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# run <file> <scanner> <target> <format> <max-ok-exit-code> <command...>
run() {
  local file="$1" scanner="$2" target="$3" format="$4" okmax="$5"; shift 5
  local started; started="$(now)"
  echo "::group::$scanner · $target → $file"
  "$@"
  local rc=$?
  echo "::endgroup::"
  local outcome=success
  if [ "$rc" -gt "$okmax" ] || [ ! -s "$OUT/$file" ]; then
    outcome=failed
    echo "::warning::$scanner on $target failed (exit $rc); the hub will record it as failed and change no statuses"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$file" "$scanner" "$target" "$format" "$outcome" "$started" "$(now)" >> "$OUT/scans.tsv"
}

# Folder (lockfiles)
run trivy-fs.cdx.json  trivy "." cyclonedx 0 \
  docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" "$TRIVY" fs --scanners vuln --format cyclonedx --output /out/trivy-fs.cdx.json /src
# Grype: native JSON is sent (it links each GHSA to its CVE); the CycloneDX
# copy is kept in the artifact for comparison only.
run grype-fs.json      grype "." grype-json 0 \
  docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" "$GRYPE" dir:/src -o json=/out/grype-fs.json -o cyclonedx-json=/out/extra/grype-fs.cdx.json
# OSV-Scanner exits 1 when it finds vulnerabilities: that is a successful scan.
run osv-fs.json        osv   "." osv-json  1 \
  docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" "$OSV" scan source --all-packages --format json --output /out/osv-fs.json -r /src

# Docker image
run trivy-image.cdx.json trivy "$TARGET_IMAGE" cyclonedx 0 \
  docker run --rm "${SOCK[@]}" -v "$OUT:/out" "$TRIVY" image --scanners vuln --format cyclonedx --output /out/trivy-image.cdx.json "$LOCAL_IMAGE"
run grype-image.json grype "$TARGET_IMAGE" grype-json 0 \
  docker run --rm "${SOCK[@]}" -v "$OUT:/out" "$GRYPE" "docker:$LOCAL_IMAGE" -o json=/out/grype-image.json -o cyclonedx-json=/out/extra/grype-image.cdx.json

echo "Scans:"; column -t -s $'\t' "$OUT/scans.tsv" || cat "$OUT/scans.tsv"
