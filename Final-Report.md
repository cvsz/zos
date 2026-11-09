# AUSI Repository Audit — zOS

**Repository:** `cvsz/zos`  
**Audit date:** 2026-11-09  
**Audited base commit:** `b045af7ddf3b296960eea3f177e9f6609744d86f`  
**Branch:** `main` (read-only inspection)  
**Scope:** GitHub repository metadata, root instructions, selected project documentation, open PRs/issues, branch metadata, and recent GitHub Actions runs.

> This report is an evidence-bounded repository/API audit. It is not a local checkout test run, independent security review, penetration test, CHR lab session, RouterOS production change, or production acceptance.

## Executive summary

The repository is an infrastructure-management and safety control plane for MikroTik RouterOS. Its canonical operating contract in `AGENTS.md` is appropriately fail-closed: protect management/recovery access, separate repository CI from live evidence, back up and dry-run before mutation, and do not perform live RouterOS changes from ordinary CI.

The latest inspected `main` commit is `b045af7ddf3b296960eea3f177e9f6609744d86f`. GitHub reports `main` as protected, but the exposed protection metadata has required status-check enforcement set to `off`. The commit includes a PGP signature, but GitHub reports it as **unverified** with reason `no_user`.

Repository metadata confirms an MIT license and a root `LICENSE` file, contrary to the stale content in `docs/LICENSING.md`. The repository homepage remains malformed as `http:://zos.zeaz.dev`. Documentation and metadata therefore require reconciliation.

Current workflow evidence is mixed: on the inspected `main` SHA, the build and RouterOS validation workflows succeeded while the Trivy security scan failed at the controller-image scan step. The failure must be investigated from its full run evidence; it must not be bypassed or suppressed.

Live RouterOS apply remains intentionally disabled pending independently verified CHR Safe Mode/rollback evidence. Open issue #39 requires additional CHR, backup/restore, PROD SSH, golden rebuild, and EnGenius convergence proof. CI cannot close those requirements.

## Repository and instruction discovery

- Default branch: `main`.
- Repository visibility: public.
- Repository permissions for the connected identity: admin, maintain, push, pull, triage.
- Governing instruction file: `AGENTS.md`.
- `zeaz.md` is not present at the repository root.
- `README.md`, `CONTRIBUTING.md`, and `SECURITY.md` were present and inspected.
- Root `LICENSE` is present and contains MIT License terms.
- `Final-Report.md` did not exist at the inspected base commit.

The root `AGENTS.md` requires Thai explanatory communication, English code/configuration, read-only-first inspection, and clear separation of repository evidence from runtime/production evidence.

## Architecture and operational safety observations

The project documentation describes zOS as a controller-side RouterOS management and safety control plane. It provides deterministic planning, validation, backup, evidence, guarded apply, verification, recovery, and GitHub delivery.

Important documented safety constraints:

- live `apply` and `apply-safe` remain blocked until an interactive Safe Mode driver is independently validated in CHR;
- `OMEGA_ALLOW_LIVE_APPLY=1` is not an override for the driver block;
- normal CI must not become a live RouterOS apply channel;
- production changes require recovery access, pre-change evidence, backup, dry-run, explicit operator opt-in, and independent post-change checks;
- credentials, private keys, backups, and populated local topology files must not enter Git.

These are safety constraints, not deficiencies to remove for the sake of declaring feature completeness.

## GitHub state observed

### Branch

GitHub reported `main` at:

`b045af7ddf3b296960eea3f177e9f6609744d86f`

GitHub branch metadata reported `protected: true`, with protection enabled. The returned required-status-check metadata showed enforcement level `off` and no required contexts/checks.

### Commit signature

The GitHub commit object contained a PGP signature, but its verification object reported:

- `verified: false`
- `reason: no_user`

This is not verified-signature evidence. Do not treat the presence of an embedded signature as equivalent to GitHub verification.

### Open pull requests

- PR #84 — `actions/upload-artifact` pinned SHA update from v7.0.1 to v7.0.2. Patch changes three workflow references. No review submissions or review threads were returned. Its metadata reported `mergeable: false` at inspection time.
- PR #86 — `docker/login-action` pinned SHA update from v4.6.0 to v4.8.0. Patch changes one workflow reference. No review submissions or review threads were returned. Its metadata reported `mergeable: true`.

Do not merge either PR solely because it is a Dependabot update. Validate the exact head SHA, all required workflows, security evidence, and repository merge policy first.

### Open issues

- Issue #38 — governance, license, branch protection, and repository settings. Its original evidence is partly stale: the repository now contains an MIT license and reports main protected. Outstanding checks include required status-check enforcement, malformed homepage metadata, and reconciliation of wiki/delete-branch policy with the documented settings.
- Issue #39 — production readiness evidence. Requires isolated CHR rollback testing, encrypted backup restore/text-export recovery, golden reinstall convergence, PROD SSH/e2e recovery, EnGenius reservation convergence, device counts, and retained post-change evidence. This remains a runtime/operations gate.

## Workflow evidence observed

Recent GitHub Actions runs for the inspected `main` SHA included:

- `validate-routeros-stack`: success on `b045af7`;
- `build-zos`: success on `b045af7`;
- `security-scan`: failure on `b045af7`, job `trivy`, step `Scan controller image`;
- Dependabot `docker` update run: failure in the Dependabot job.

A PR #86 run showed `build-zos` and `validate-routeros-stack` succeeding, while `security-scan` failed at `Scan controller image`.

The workflow is configured to fail on HIGH and CRITICAL findings for filesystem and controller-image scans, ignoring unfixed findings. The failing step's existence is evidence of a failed gate; the finding details and remediation must be obtained from the retained SARIF/Trivy output before deciding whether the result is an actionable vulnerability, policy issue, or scan/configuration failure.

The latest run list also included a scheduled `Auto Fix Open PRs` run that completed successfully. The workflow is currently read-only validation/reporting and explicitly does not sign or push fixes.

## Documentation inconsistency identified

At the inspected commit, `docs/LICENSING.md` claimed no project-wide license existed. This conflicts with both the root MIT `LICENSE` file and GitHub repository metadata reporting `mit`.

This discrepancy is corrected in the implementation branch accompanying this report. The document now describes the MIT project license while preserving the separate third-party notice boundary.

The repository homepage is still `http:://zos.zeaz.dev`; this report records it as an outstanding metadata task rather than silently guessing the intended canonical URL.

## Security scan findings — inspected Trivy evidence

The retained Trivy SARIF for run 42330612687 identified the following HIGH findings in the controller image built from the audited `main` commit:

| Package | Installed | Fixed version from scan | CVE | Finding |
|---|---:|---:|---|---|
| musl / musl-utils | 1.2.5-r12 | 1.2.5-r13 | CVE-2026-107891 | integer-overflow issue in regular-expression compilation |
| zlib | 1.3.2-r0 | 1.3.2-r1 | CVE-2026-85091 | heap-buffer-overflow issue in non-blocking gzip write handling |

The evidence artifact contained two SARIF results for the musl CVE (the `musl` and `musl-utils` packages) and one for zlib. The failed controller-image scan reported three HIGH results total and zero CRITICAL results.

The image used `alpine:3.22.6` pinned to an immutable digest. Alpine's official 2026-10-21 release announcement for 3.22.7 explicitly listed both CVEs among the security fixes, and the 2026-11-05 release archive lists 3.22.8 as the latest 3.22 point release. The implementation branch therefore updates the controller base image to the 3.22.8 tag. **The branch's pinned digest must be validated by CI before merge; no clean-scan result is claimed here.**

Sources:
- Alpine 3.22.7 security release notes: https://www.alpinelinux.org/posts/alpine-3.21.9-3.22.7-3.23.7-3.24.3-released/
- Alpine 3.22 release archive: https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/

## Security assessment boundaries

The reviewed metadata and workflow configuration establish that security scanning is intended and that the Trivy workflow has failed. They do not establish a complete vulnerability inventory.

Not performed in this audit:

- local SAST or dependency scan;
- full Trivy SARIF analysis;
- dynamic application or RouterOS penetration testing;
- secret-scanning alert enumeration;
- CHR/live RouterOS testing;
- host-level access or credential validation.

No claim of penetration-test success or complete security clearance is made.

## Actions taken in the accompanying branch

- corrected `docs/LICENSING.md` to reflect the existing MIT license and preserve third-party licensing boundaries;
- added this evidence-bounded report as `Final-Report.md`.

These changes do not alter RouterOS behavior, deployment configuration, security gates, branch protection, secrets, or live infrastructure.

## Remaining blockers and recommended next work

1. Inspect the complete Trivy SARIF and failing controller-image scan output; fix actual HIGH/CRITICAL findings at their source and rerun the full workflow.
2. Resolve or rebase PR #84 and #86 only after exact-head CI/security validation.
3. Configure main-branch rules to require pull requests and exact successful validation/build/security contexts, plus conversation resolution; verify the resulting policy through GitHub after mutation.
4. Correct repository homepage to the explicitly approved canonical HTTPS URL.
5. Decide wiki and merged-branch deletion policy, then align repository settings with `docs/GITHUB-SETTINGS.md`.
6. Reconcile issue #38 with verified current settings.
7. Complete issue #39 only with actual isolated CHR and authorized runtime evidence. Do not simulate or infer these results from mocks or CI.
8. Investigate why GitHub does not associate the current commit's signature with a verified user and establish a signing path that GitHub verifies before making signed-commit claims.
9. Obtain an actual independent review from `policedbc` through that identity's authenticated session. The current connector session is `cvsz`, so it cannot truthfully submit the independent approval.
10. Run `make validate`, `make docs`, `make evidence`, `make security-evidence`, and `./zOS/bin/zos help` in a trusted local checkout and attach exact command output to the PR.

## Verification status

| Area | Status | Evidence |
|---|---|---|
| Root instructions inspected | PASS | `AGENTS.md` fetched |
| Project README/security/contribution docs inspected | PASS | GitHub file contents |
| License file present | PASS | root MIT `LICENSE`, GitHub metadata |
| Licensing documentation synchronized | IMPLEMENTED IN BRANCH | accompanying branch change |
| Main protected | PARTIAL | branch metadata says protected; required checks enforcement is off |
| Main required checks | BLOCKED | enforcement level `off`, no contexts returned |
| Main signature verified | FAIL | GitHub `verified=false`, `no_user` |
| Build workflow on audited SHA | PASS | run 42330612582 |
| RouterOS validation workflow on audited SHA | PASS | run 42330612701 |
| Security scan on audited SHA | FAIL | run 42330612687, Trivy controller-image scan step |
| Open PRs reviewed at metadata/patch level | PARTIAL | #84 and #86 inspected; no full CI/artifact verification |
| CHR Safe Mode / rollback | BLOCKED | no live CHR evidence inspected |
| Backup restore / disaster recovery | BLOCKED | no restore exercise performed |
| PROD SSH / e2e | BLOCKED | not tested |
| EnGenius active reservation convergence | BLOCKED | live equipment evidence not inspected |
| Independent policedbc review | BLOCKED | current authenticated identity is cvsz |
| Post-merge validation | NOT RUN | no merge performed |

## Evidence references

- Main commit: https://github.com/cvsz/zos/commit/b045af7ddf3b296960eea3f177e9f6609744d86f
- Main build run: https://github.com/cvsz/zos/actions/runs/42330612582
- Main RouterOS validation run: https://github.com/cvsz/zos/actions/runs/42330612701
- Main security scan run: https://github.com/cvsz/zos/actions/runs/42330612687
- PR #84: https://github.com/cvsz/zos/pull/84
- PR #86: https://github.com/cvsz/zos/pull/86
- Governance issue #38: https://github.com/cvsz/zos/issues/38
- Runtime evidence issue #39: https://github.com/cvsz/zos/issues/39

---

**Assessment:** The repository has meaningful safety controls and successful build/validation evidence, but it is **not production-accepted**. The security workflow is failing, branch required-check enforcement is not evidenced as active, commit verification is false, and live CHR/restore/PROD evidence remains outstanding.
