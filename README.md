# vuln-hub-testbed

A small Node.js app with **known-vulnerable dependencies on purpose**, used to
test [Vulnerability Hub](https://github.com/manikumarkv/vulnerability-hub)
end to end. Never deploy it.

## What CI does

`.github/workflows/vuln-scan.yml` builds the Docker image and scans the
folder and the image with three free scanners, then sends each file to the
hub:

| File | Scanner | Target | Format sent |
|---|---|---|---|
| `trivy-fs.cdx.json` | Trivy | `.` | `cyclonedx` |
| `grype-fs.json` | Grype | `.` | `grype-json` (+ `packagesScanned`) |
| `osv-fs.json` | OSV-Scanner | `.` | `osv-json` |
| `trivy-image.cdx.json` | Trivy | `ghcr.io/manikumarkv/vuln-hub-testbed` | `cyclonedx` |
| `grype-image.json` | Grype | `ghcr.io/manikumarkv/vuln-hub-testbed` | `grype-json` (+ `packagesScanned`) |

Checkpoint by trigger:

| Trigger | Scan type |
|---|---|
| daily 05:00 UTC, or **Run workflow**, on `production` | `production` |
| pull request into `release/**` | `fix_pr` |
| push to `release/**` | `release_verify` |

Every run keeps the scanner files as the `scans-…` artifact (90 days).
Grype's CycloneDX copy is kept in `extra/` for comparison; it is not sent,
because it reports npm issues by GHSA id without the CVE.

## Connecting the hub

Until these are set, the upload step only prints the metadata it would send.

- Repository variable `HUB_URL`, e.g. `https://vuln-hub-dev.vercel.app`
- Repository secret `HUB_CI_TOKEN`, a CI token from the hub's Settings → CI tokens

## Vulnerable on purpose

axios 0.21.1, express 4.17.1, jsonwebtoken 8.5.1, lodash 4.17.20,
minimist 1.2.5, on `node:18.12.0-alpine3.16`. To test a fix, upgrade one of
them in a `feature/…` branch and open a pull request into a `release/…`
branch.
