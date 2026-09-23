# zOS for MikroTik

![zOS infrastructure safety control plane](assets/zos-banner-01.jpg)

[![Validate RouterOS Stack](https://github.com/cvsz/zos/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/cvsz/zos/actions/workflows/validate.yml?query=branch%3Amain)
[![Build zOS](https://github.com/cvsz/zos/actions/workflows/zos-build.yml/badge.svg?branch=main)](https://github.com/cvsz/zos/actions/workflows/zos-build.yml?query=branch%3Amain)
[![Security Scan](https://github.com/cvsz/zos/actions/workflows/security-scan.yml/badge.svg?branch=main)](https://github.com/cvsz/zos/actions/workflows/security-scan.yml?query=branch%3Amain)
[![Evidence Validation](https://github.com/cvsz/zos/actions/workflows/evidence-validation.yml/badge.svg?branch=main)](https://github.com/cvsz/zos/actions/workflows/evidence-validation.yml?query=branch%3Amain)
[![RouterOS Skills](https://github.com/cvsz/zos/actions/workflows/routeros-skills.yml/badge.svg?branch=main)](https://github.com/cvsz/zos/actions/workflows/routeros-skills.yml?query=branch%3Amain)

[![Live Apply](https://img.shields.io/badge/Live_Apply-DISABLED-critical)](docs/PRODUCTION-READINESS.md)
[![CHR Integration](https://img.shields.io/badge/CHR_Integration-BLOCKED-orange)](docs/CHR-LAB-EVIDENCE.md)
[![Production Readiness](https://img.shields.io/badge/Production_Readiness-NOT_VERIFIED-yellow)](docs/PRODUCTION-READINESS.md)

> **Status badge scope:** GitHub Actions badges show the latest workflow status on `main` only. They do not prove CHR integration, live router health, disaster recovery, or production acceptance. The operational badges are deliberately static safety-gate labels; update them only after independently verified evidence and an approved release.

zOS is the ZeaZDev management and safety control plane for MikroTik RouterOS. RouterOS remains the network operating system on the router; zOS runs from the controller side and adds deterministic planning, validation, backup, evidence, guarded apply, verification, recovery, and GitHub delivery workflows.

> Production rule: normal CI is validation/build/evidence only. **Both `apply` and `apply-safe` are currently blocked** pending a CHR-verified interactive Safe Mode implementation. `OMEGA_ALLOW_LIVE_APPLY=1` does not override the driver block. Do not attempt production mutation from CI.

## Current verified invariants

- Repository: `cvsz/zos`, default branch `main`.
- Router: MikroTik RB4011iGS+, RouterOS 7.24.2+.
- WAN: DHCP client on `ether1`; observed lease `192.168.202.91/21`, upstream gateway `192.168.200.1`. The lease is runtime evidence and must not be hard-coded.
- LAN: `DBC-Bridge-Local = 192.168.1.1/24`; `ether2`-`ether10` and `sfp-sfpplus1` remain LAN bridge ports.
- `PoliceDBC-SEA = 192.168.1.100`, MAC `48:4D:7E:D4:3A:C6`.
- `core.zeaz.dev = 192.168.1.123`, MAC `00:0C:29:75:A6:D4`.
- `prod.zeaz.dev = 192.168.1.122`, MAC `00:0C:29:B5:F4:09`; this existing repository baseline is retained.
- `ha-a.zeaz.dev = 192.168.1.119`, MAC `00:0C:29:B7:22:AF`.
- `ha-b.zeaz.dev = 192.168.1.120`, MAC `00:0C:29:72:EF:42`.
- EnGenius infrastructure is fixed at controller `.50` and EWS310AP `.51-.58`; `wifi.zeaz.dev` remains `.238`, with MAC mappings documented in `README-INFRA.md` and `ENVIRONMENTS.md`.
- The dynamic DHCP pool excludes all fixed infrastructure addresses, including `.50-.58`, `.100`, `.119`, `.120`, `.122`, `.123`, and `.238`.
- NAT is restricted to `192.168.1.0/24 -> WAN`.
- DEV/controller FQDN: `core.zeaz.dev`; PROD FQDN: `prod.zeaz.dev`.
- CORE physical interface: `ens33`; WireGuard interface: `policedbc`.
- CORE routing contract:

~~~text
default via 192.168.1.1 dev ens33
192.168.1.0/24 dev ens33
10.8.0.0/24 dev policedbc
~~~

- `192.168.1.0/24` must never be an active `AllowedIPs` route on `policedbc`.
- CORE SSH is fail-closed toward public-key authentication: password login is disabled by default by `core/install.sh`, and the installer refuses to disable passwords unless an authorized key is already present.

## Reinstall / recovery bootstrap

Use `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` only as the clean-rebuild bootstrap for the verified `ether1` DHCP WAN, `DBC-Bridge-Local` single untagged LAN, current DHCP/fixed-host inventory, WireGuard, firewall/NAT, service-hardening, and observability baseline. The bootstrap deliberately refuses non-clean pool/DHCP/WireGuard/firewall state before mutation. A clean rebuild generates a fresh router WireGuard keypair and prints its public key for CORE reconciliation; private key material is never stored in Git. It is not evidence that every active production phase is converged. After recovery connectivity is proven, run the current guarded phase workflow and verification before declaring production acceptance. Always dry-run and maintain a recovery path before live apply.

## Quick start

~~~bash
git clone https://github.com/cvsz/zos.git
cd zos
cp config/topology.env.example config/topology.env
chmod 600 config/topology.env
./tools/install-controller.sh
./zOS/bin/zos doctor
make validate
make docs
~~~

### Environment examples

- `.env.example` — operator/developer overrides and fail-closed gates;
- `config/topology.env.example` — authoritative RouterOS/DEV/PROD topology template;
- `core/.env.example` — CORE network and SSH bootstrap variables;
- `zOS/.env.example` — zOS runtime/update-policy variables.
- `cloudflare/config.env.example` — optional, secret-free Cloudflare connector/origin template.

Real `.env` files remain ignored. Keep secrets and site-specific values out of Git.

Optional Cloudflare publication and Access controls are documented in [`cloudflare/README.md`](cloudflare/README.md); they do not replace RouterOS management or recovery paths.

## Operator workflow

~~~bash
make validate
make docs
make evidence
make security-evidence
make core-check
make status
make audit
make backup
make dry-run
make verify
make e2e
~~~

**Live apply is disabled in the current release.** Do not set `OMEGA_ALLOW_LIVE_APPLY=1` expecting `make apply` to work: `tools/routeros-safe-session.py` intentionally returns a nonzero status, and direct `tools/omega-router.sh apply` is disabled. The supported operator path is read-only inspection, encrypted backup, dry-run and verification. Follow [Production Readiness](docs/PRODUCTION-READINESS.md) and [OpenCode Master Prompt](docs/OPENCODE-MASTER-PROMPT.md) to implement and validate the missing CHR-backed interactive driver in a separate reviewed PR.

Automatic RouterOS installation is separately double-gated by `OMEGA_AUTO_ROUTEROS_UPDATE=1` and `OMEGA_ALLOW_ROUTER_REBOOT=1`.

## Documentation map

Start at `docs/INDEX.md`. Key documents include `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/INSTALLATION.md`, `docs/RUNBOOK.md`, `docs/NETWORK-RECOVERY.md`, `docs/SSH-HARDENING.md`, `docs/PRODUCTION-READINESS.md`, `docs/GITHUB-OPERATIONS.md`, `docs/TESTING.md`, `docs/RELEASES.md`, `docs/DISASTER-RECOVERY.md`, and `docs/OPENCODE-MASTER-PROMPT.md`.

## Repository status is not production status

A green GitHub build proves the repository checks that ran. It does not prove live router reachability, DNS, WireGuard, firewall/NAT behavior, recovery access, or PROD connectivity. Production acceptance requires the runtime evidence defined in `docs/PRODUCTION-READINESS.md`.
