# Production Readiness

Production readiness is an evidence state, not a label inferred from CI.

## Cloudflare-ready (optional)

- connector host is approved and its outbound-only tunnel is healthy;
- each public hostname maps to an explicitly approved private origin;
- Access policy is tested before an administrative application is published;
- RouterOS management services remain LAN/VPN-only and local recovery is proven;
- DNS, tunnel, Access, origin, and rollback evidence is recorded separately from RouterOS evidence.

Cloudflare configuration alone is not production acceptance and must not be used to infer RouterOS health.

## Repository-ready

A commit/PR is repository-ready when:

- `make validate` passes;
- `make docs` passes;
- relevant evidence/security checks pass;
- required GitHub Actions checks are green;
- live mutation paths remain fail-closed;
- no sensitive material is committed;
- documentation, rollback implications, and changelog are synchronized.

## CORE-ready

CORE is runtime-ready when:

- physical carrier and runtime IPv4 are valid;
- default/physical LAN route through `ens33`;
- `10.8.0.0/24` routes through `policedbc`;
- active WireGuard config excludes `192.168.1.0/24` from `AllowedIPs`;
- sshd validates and listens;
- public-key login is independently proven;
- password authentication is disabled for production;
- root SSH login is disabled;
- APT trust remains signature-verified;
- any network/SSH recovery survives reboot.

## Current live-apply blocker

As of the reviewed repository state on 2026-09-22, PRs #61-#66 are merged and their required validation/build/security workflows passed. These results establish only the scope exercised by repository CI. The direct `apply` command is disabled and `tools/routeros-safe-session.py` returns a fail-closed error; `apply-safe` cannot deploy. This is intentional until the interactive driver has independent CHR evidence. Never treat `OMEGA_ALLOW_LIVE_APPLY=1` as an override.

## CHR-verified

- isolated CHR version, topology, test runner and evidence are recorded;
- SSH host key, PTY/prompt and Safe Mode entry are independently verified;
- successful apply commits only after independent health checks;
- script error, timeout, disconnect, session conflict, concurrent apply and failed health checks demonstrably roll back;
- command echo and stale success markers cannot spoof acceptance;
- backup restore and local recovery have been exercised.

**Current Status**: **MOCK HARNESS COMPLETE, LIVE CHR BLOCKED**
- `tools/chr-lab-harness.py`: 15 deterministic failure-injection scenarios (SSH, Safe Mode, timeout, disconnect, signal, concurrent, spoof, fragmentation, truncation, rollback, commit gate)
- `docs/CHR-LAB-EVIDENCE.md`: evidence manifest template, test matrix with status
- All live RouterOS integration tests (SM-01, SM-02, DR-01..03, UP-01..02, BK-01..02, GR-01..03, OWN-01..03) marked **BLOCKED** — no isolated CHR available
- Never fabricate CHR results; mark integration tests BLOCKED per AGENTS.md

## Router change-ready

- current state audited;
- recovery-capable management path proven;
- export and backup captured;
- intended phases dry-run cleanly;
- the CHR-verified interactive Safe Mode driver and independent recovery path are available;
- explicit live-apply gate enabled only for the approved window.

## Production accepted

After an approved live change, independently verify management, WAN/default route, LAN/DHCP/DNS, WireGuard, firewall/NAT, intended service behavior, and DEV/PROD reachability where applicable.

Record:

1. commit/release SHA;
2. CI run identifiers;
3. pre-change audit timestamp;
4. backup/export identifiers;
5. dry-run result;
6. approved change window/operator;
7. post-change verification result;
8. reboot/rollback/restore result when relevant;
9. remaining known risks.

## Explicit non-evidence

The following are not sufficient on their own: HTTP 200 from a RouterOS execute endpoint, successful repository build, an SSH TCP port being reachable, a pre-reboot route table, or a backup file existing without a restore/rollback exercise.
