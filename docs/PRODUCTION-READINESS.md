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

## Router change-ready

- current state audited;
- recovery-capable management path proven;
- export and backup captured;
- intended phases dry-run cleanly against the exact target runtime;
- dry-run evidence is fresh and bound to git/topology/router identity and RouterOS version;
- Safe Mode/recovery is available and the apply helper performs per-phase PASS/FAIL handshakes;
- assertive health verification passes before Safe Mode commit;
- explicit live-apply gate is enabled only for the approved window.

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


## Release/security acceptance

A public release is blocked until a project-wide LICENSE is selected. Release artifacts must be generated from tracked git content only, from a clean synchronized `main`. Container/repository vulnerability scanning is performed separately from the lightweight repository secret-evidence generator; both are evidence inputs, not substitutes for live security testing.

GitHub administrative controls such as branch/ruleset protection remain account-side state. Verify them in GitHub before calling governance complete; repository documentation cannot enforce a disabled account-side ruleset by itself.
