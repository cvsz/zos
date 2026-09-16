# zOS for MikroTik

![zOS infrastructure safety control plane](assets/zos-banner-01.jpg)

[![Validate RouterOS Stack](https://github.com/cvsz/zos/actions/workflows/validate.yml/badge.svg)](https://github.com/cvsz/zos/actions/workflows/validate.yml)
[![Build zOS](https://github.com/cvsz/zos/actions/workflows/zos-build.yml/badge.svg)](https://github.com/cvsz/zos/actions/workflows/zos-build.yml)
[![Evidence Validation](https://github.com/cvsz/zos/actions/workflows/evidence-validation.yml/badge.svg)](https://github.com/cvsz/zos/actions/workflows/evidence-validation.yml)
[![RouterOS Skills](https://github.com/cvsz/zos/actions/workflows/routeros-skills.yml/badge.svg)](https://github.com/cvsz/zos/actions/workflows/routeros-skills.yml)

zOS is the ZeaZDev management and safety control plane for MikroTik RouterOS. RouterOS remains the network operating system on the router; zOS runs from the controller side and adds deterministic planning, validation, backup, evidence, guarded apply, verification, recovery, and GitHub delivery workflows.

> Production rule: normal CI is validation/build/evidence only. Live RouterOS mutation remains operator-gated and recovery-aware.

## Current verified invariants

- Repository: `cvsz/zos`, default branch `main`.
- Router: MikroTik RB4011iGS+, RouterOS 7.24.2+.
- WAN: DHCP client on `ether1`; observed lease `192.168.202.91/21`, upstream gateway `192.168.200.1`. The lease is runtime evidence and must not be hard-coded.
- LAN: `bridgeLocal = 192.168.1.1/24`; `ether2`-`ether10` and `sfp-sfpplus1` remain LAN bridge ports.
- `PoliceDBC-SEA = 192.168.1.10`, MAC `48:4D:7E:D4:3A:C6`.
- `core.zeaz.dev = 192.168.1.100`, MAC `00:0C:29:75:A6:D4`.
- `ha-a.zeaz.dev = 192.168.1.119`, MAC `00:0C:29:B7:22:AF`.
- `ha-b.zeaz.dev = 192.168.1.120`, MAC `00:0C:29:72:EF:42`.
- WiFi infrastructure is fixed at `.101-.108`, `.238`, and `.239` with the MAC mappings documented in `README-INFRA.md` and `ENVIRONMENTS.md`.
- The dynamic DHCP pool excludes all fixed infrastructure addresses.
- `prod.zeaz.dev` is currently reported as `192.168.1.101`, which conflicts with verified `RITRUECHAI-AP01 = 192.168.1.101`; the PROD DHCP/DNS binding is therefore withheld until reconciled.
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

## Reinstall / recovery source of truth

Use `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` for a clean RouterOS rebuild. It encodes the verified `ether1` DHCP WAN and `bridgeLocal` LAN topology and the verified fixed host inventory. The reported PROD `.101` address is deliberately not configured because it collides with RITRUECHAI-AP01. Always dry-run and maintain a recovery path before live apply.

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

Live apply remains blocked unless the operator explicitly enables it after backup, dry-run, and a verified recovery path:

~~~bash
export OMEGA_ALLOW_LIVE_APPLY=1
make apply
~~~

Automatic RouterOS installation is separately double-gated by `OMEGA_AUTO_ROUTEROS_UPDATE=1` and `OMEGA_ALLOW_ROUTER_REBOOT=1`.

## Documentation map

Start at `docs/INDEX.md`. Key documents include `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/INSTALLATION.md`, `docs/RUNBOOK.md`, `docs/NETWORK-RECOVERY.md`, `docs/SSH-HARDENING.md`, `docs/PRODUCTION-READINESS.md`, `docs/GITHUB-OPERATIONS.md`, `docs/TESTING.md`, `docs/RELEASES.md`, and `docs/DISASTER-RECOVERY.md`.

## Repository status is not production status

A green GitHub build proves the repository checks that ran. It does not prove live router reachability, DNS, WireGuard, firewall/NAT behavior, recovery access, or PROD connectivity. Production acceptance requires the runtime evidence defined in `docs/PRODUCTION-READINESS.md`.
