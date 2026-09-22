# Roadmap

This roadmap describes intended work. It must not be read as evidence that an item is deployed or production-ready.

## Now

- keep CORE SSH/network recovery deterministic and reboot-verifiable;
- keep documentation and GitHub community health complete and validated;
- maintain RouterOS production-safety gates and evidence checks;
- maintain trusted self-hosted runner isolation.

## Completed (Repository-Ready)

- **Phase 1**: Safe Mode nonce-framed state machine with 28 regression tests (PR #67 merged)
- **Phase 2**: CHR Lab Mock Harness with 16 event-driven failure-injection scenarios + evidence manifest (PRs #68-#69 merged)
- **Phase 3 (repo-safe)**: idempotent backup lifecycle (28 mocked checks), fail-closed restore drill (9 mocked checks), recovery runbooks, machine-readable evidence manifests, repo-security + read-only topology reconciliation — live CHR restore still BLOCKED

## Next

- formalize release/version policy before 1.0;
- add stronger documentation/static link validation where useful;
- maintain Dependabot, immutable Action pins, container digest pins, and vulnerability-scan policy;
- expand sanitized failure-mode evidence for CORE/GitHub incidents;
- verify and document actual PROD host addressing before enabling cross-environment automation.

## Blocked (Require CHR Infrastructure + Operator Approval)

- **Phase 2 Live**: CHR integration tests (SM-01, SM-02, DR-01..03, UP-01..02, BK-01..02, GR-01..03, OWN-01..03 — 15 tests)
- **Phase 3 Live**: backup/restore drill on disposable CHR (mock tooling complete, live execution BLOCKED)
- **Phase 4**: Production topology reconciliation (read-only offline audit complete; live read-only audit → mutation still gated)
- **Phase 5**: Security hardening (SSH ACL, WinBox, WireGuard AllowedIPs, firewall ownership)
- **Phase 6**: Observability (health checks, metrics, alerts, evidence retention)
- **Phase 7**: Documentation sync, release engineering, production acceptance report
- **Phase 8**: Controlled production rollout (explicit approval + maintenance window)

## Later

- evaluate multi-controller/HA and reserved overlay design after route-conflict review;
- expand observability and independent restore/DR exercises;
- add release provenance/signing/SBOM distribution if the package becomes externally distributed.

## Open project decisions

- choose and declare the zOS project license;
- decide long-term support/versioning guarantees;
- define additional maintainer/reviewer roles as the contributor base grows.
