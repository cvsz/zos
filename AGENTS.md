# Agent System Rules

## Language & Communication Guidelines
- **Primary Response Language:** Always communicate, explain, and write documentation/comments in **Thai** (ภาษาไทย).
- **Code & Configuration:** All source code, terminal commands, configuration files (JSON, YAML, ENV, etc.), variable names, and code syntax MUST remain in **English**.
- **Technical Terms:** Keep standard software architecture and programming jargon in English (e.g., *refactor*, *middleware*, *dependency injection*) to maintain accuracy.

## Response Behavior
1. **Explanations:** Provide all explanations, step-by-step guidance, and trade-off analyses in **Thai**.
2. **Code Blocks:** Write clean, executable code entirely in **English**. Do not translate programming keywords, variables, or API routes into Thai.
3. **Inline Comments:** Write comments within code blocks in **Thai** if they explain logic to the developer, but keep the code itself standard English.

---

# zOS Agent Operating Contract

`AGENTS.md` is the canonical policy for Codex and every other automated agent operating in `cvsz/zos`. Adapter files such as `CODEX.md`, `CLAUDE.md`, `GEMINI.md`, `OPENCODE.md`, `ZED.md`, and `DMUX.md` may add tool-specific notes but may not weaken this contract.

## Precedence

1. Protect management and recovery access.
2. Preserve verified live state unless an approved change explicitly replaces it.
3. Prefer read-only inspection, deterministic validation, backup, and dry-run before mutation.
4. Keep repository evidence distinct from live production evidence.
5. Never invent unknown topology, credentials, addresses, or successful runtime outcomes.

## Canonical environment

| Surface | Contract | Notes |
|---|---|---|
| Repository | `cvsz/zos` | default branch `main` |
| DEV/controller | `core.zeaz.dev` | automation target; existing operator account may differ |
| PROD | `prod.zeaz.dev` | addresses not yet verified must remain unset |
| Router | PoliceDBC RB4011iGS+ | RouterOS 7.24.2+ baseline |
| CORE LAN | `ens33` / `192.168.1.0/24` | default gateway `192.168.1.1` |
| CORE WG | `policedbc` / `10.8.0.2/32` | routed WG network `10.8.0.0/24` |

The desired automation SSH identity is `zeazdev`; do not assume it already exists on an existing host. Recovery/bootstrap scripts derive the actual target user from `SUDO_USER`/`USER` unless `SSH_USER` is explicitly set.

## CORE network invariant

~~~text
default via 192.168.1.1 dev ens33
192.168.1.0/24 dev ens33
10.8.0.0/24 dev policedbc
~~~

The physical LAN must not appear in active WireGuard `AllowedIPs`. Backup files may retain historical values for rollback; active-config checks must distinguish backups from live `.conf` files.

## Mandatory production change sequence

1. inspect current repository and runtime state;
2. prove a recovery-capable management path;
3. audit and capture pre-change evidence;
4. create/export backup evidence;
5. run repository/documentation/evidence validation;
6. dry-run intended RouterOS phases where supported;
7. enter Safe Mode or use another verified rollback path for risky work;
8. require explicit operator opt-in;
9. apply the smallest idempotent change;
10. independently verify management, WAN/default route, LAN/DHCP/DNS, WireGuard, firewall/NAT, and intended service behavior;
11. retain post-change evidence and rollback notes.

## Prohibited actions

- no factory reset of production;
- no bulk deletion of firewall/NAT/IP/interface/routing state;
- no silent WireGuard key rotation;
- no default-route/WAN change without recovery access;
- no simultaneous loss of SSH and WinBox management;
- no physical LAN CIDR in CORE WireGuard `AllowedIPs`;
- no secrets, private keys, runner credentials, binary backups, or sensitive exports in Git;
- no live RouterOS apply from ordinary CI;
- no disabling APT/GitHub/security validation just to make a pipeline pass;
- no invented PROD addresses or runtime-success claims;
- no broad `safe.directory` workaround for root operating in a user-owned checkout.

## SSH and package-security contract

- `core/install.sh` defaults `SSH_ALLOW_PASSWORD=no`.
- key-only mode requires a non-empty authorized-keys file before sshd is changed.
- `PermitRootLogin no` remains required.
- temporary password bootstrap must be explicit and removed after key login is proven.
- HashiCorp APT recovery may use only the reviewed official endpoint and pinned fingerprint in source.
- APT signature verification must never be bypassed.

## Repository completion checks

~~~bash
make validate
make docs
make evidence
make security-evidence
./zOS/bin/zos help
~~~

Runtime checks are additional, not substitutes:

~~~bash
make core-check
make core-find-conflict
make status
make audit
make verify
make e2e
~~~

## Documentation contract

Project-owned Markdown must remain synchronized with behavior. `docs/INDEX.md` defines the documentation map and ownership model. Vendored skill documentation under `skills/routeros-*` is upstream-derived and should be changed only for deliberate sync/safety adaptation with provenance retained.

Any behavior-changing PR must update its relevant documentation, tests/evidence, changelog entry, and recovery implications in the same change.
