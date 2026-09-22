# Testing and Validation

zOS separates source validation from live runtime verification.

## Repository baseline

~~~bash
make validate
make docs
./zOS/bin/zos help
~~~

`make validate` checks required files, production-safety invariants, shell syntax/static analysis, and selected hardening expectations. `make docs` checks project-document presence, local Markdown references, and common documentation drift.

## Evidence

~~~bash
make evidence
make security-evidence
~~~

`make evidence` validates deterministic committed fixtures. `make security-evidence` generates repository-derived file-inventory/secret-audit SPDX/SARIF artifacts. The `security-scan.yml` workflow separately generates Trivy filesystem/image vulnerability SARIF plus a package-aware CycloneDX SBOM for the controller image, retains them as a 30-day Actions artifact, and gates HIGH/CRITICAL findings. None of these repository checks proves live-production health.

## CORE runtime

~~~bash
make core-status
make core-check
make core-find-conflict
~~~

After network/SSH recovery, include an external SSH key-login test and a reboot persistence test.

## Optional Cloudflare boundary

For Cloudflare changes, validate the secret-free template and local links, then separately verify connector persistence, tunnel connectivity, hostname-to-origin routing, Access enforcement, origin health, and recovery when Cloudflare is unavailable. Do not use credentials or live RouterOS mutation in repository CI.

## Router read-only/runtime

~~~bash
make status
make audit
make verify
make e2e
~~~

Use `make backup` and `make dry-run` before any approved live change.

## CI matrix

| Workflow | Primary purpose | Live mutation? |
|---|---|---|
| `validate.yml` | repository/static/docs/safety checks | no |
| `evidence-validation.yml` | corpus and generated security evidence | no |
| `routeros-skills.yml` | vendored RouterOS skill integrity | no |
| `zos-build.yml` | tarball and OCI package build | no |
| `security-scan.yml` | Trivy filesystem and controller-image HIGH/CRITICAL vulnerability gates | no |

The optional self-hosted runner probe remains validation-only.

## Failure interpretation

A green CI run means its configured checks passed for that commit. It does not prove router connectivity, CORE route persistence, DNS, VPN, firewall/NAT, or PROD reachability.

## CHR Lab Harness (Mock)

Deterministic failure-injection tests without live RouterOS:

~~~bash
python3 tools/chr-lab-harness.py
~~~

Produces sanitized evidence manifest at `artifacts/chr-lab/manifest-<run_id>.json`.
All live RouterOS integration tests remain **BLOCKED** until isolated CHR is available.
See `docs/CHR-LAB-EVIDENCE.md` for test matrix and status.

## Backup Hardening (Mock, No Live Router)

Idempotent backup lifecycle without a live router (mocked `ssh`/`scp`):

~~~bash
bash tools/test-backup-hardening.sh
~~~

Covers 28 checks: unique identifiers, `700`/`600` permissions, `mktemp` staging + atomic `mv` publish, nonempty validation, SHA-256 + manifest, cleanup trap preserving the original error, no password in ssh argv/stdout/`bash -x` trace, happy-path manifest/perms/checksum/unique IDs, partial-download and empty-artifact fail-closed behavior. Wired into `make validate` via `tools/validate-repo.sh`.

## Restore Drill (Mock, No Live Router)

Reusable fail-closed drill for disposable CHR:

~~~bash
bash tools/test-restore-drill.sh
tools/restore-drill.sh --backup-id <id> --mock
~~~

Covers 9 checks: mock `MOCK PASS` with elapsed time and sanitized evidence, checksum/provenance/password gates, production-target refusal, live-without-authorization refusal. Live CHR restore stays `BLOCKED` until an isolated disposable target is authorized.
