# Changelog

Notable repository and operational changes are recorded here. zOS has not yet declared a stable public API; version numbers below describe repository milestones.

## Unreleased

### EnGenius DHCP reservation reconciliation
- Moved `EWS1200D-10T` to reserved `192.168.1.50` and the eight EWS310AP units to `192.168.1.51-.58` using their verified MAC mappings.
- Updated the LAN pool so `.50-.58`, `.100`, `.119`, `.120`, `.122`, `.123`, and `.238` are excluded from dynamic allocation while the former `.101-.108` and `.239` WiFi addresses return to the dynamic pool.
- Added controlled migration from the previous EnGenius reservations while unrelated fixed hosts remain fail-closed on address drift.
- Removed textual `server=lan-dhcp` updates from existing lease reconciliation to avoid RouterOS `ambiguous value of server` failures; new leases use the exact internal DHCP server ID.
- Synchronized the topology template, golden reinstall, validation, environment inventory, runbook, migration guide, and infrastructure reference with the new address contract.
- Documented that a changed reservation is not operationally complete until RouterOS `active-address` matches the target after a controlled DHCP renew or AP reboot.

### Router automation and live apply verification
- Quoted `WIFI_REPEATER_NAME` in `config/topology.env.example` to prevent bash word-splitting errors during environment sourcing.
- Preserved caller `OMEGA_ALLOW_LIVE_APPLY` override across topology sourcing in `tools/omega-router.sh`.
- Completed pre-change backup, dry-run manifest validation, and live configuration apply on the MikroTik RB4011 router (`192.168.1.1`) with health verification passing.

### WireGuard peer configuration
- Added idempotent creation of `wg-remote` interface, address `10.8.0.1/24`, `VPN` interface list membership, and `core.zeaz.dev` peer (`10.8.0.2/32`) in `40-WIREGUARD-SERVICES.rsc`.
- Fixed `/etc/wireguard/*.conf` file discovery in `tools/core-network-repair.sh` to work with root-protected permissions.
- Verified active bidirectional WireGuard handshake and ICMP ping reachability between CORE (`10.8.0.2`) and router (`10.8.0.1`).

### 2026-09-16 verified LAN/WiFi inventory
- Corrected `PoliceDBC-SEA` to `192.168.1.10` with MAC `48:4D:7E:D4:3A:C6`.
- Corrected `core.zeaz.dev` to `192.168.1.100` with verified VMware MAC `00:0C:29:75:A6:D4`.
- Added fixed DHCP inventory for RITRUECHAI-AP01/02, BOONNAK-AP01/02, SARASIN-AP01/02, and PANKHONGCHUEN-AP01/02 at `.101-.108` with the supplied MACs.
- Added `wifi.zeaz.dev = 192.168.1.238` for `ZEAZ Wifi Repeater` and `EWS1200D-10T = 192.168.1.239`.
- Updated the dynamic DHCP pool so fixed infrastructure addresses cannot be dynamically allocated.
- Withheld the reported `prod.zeaz.dev = 192.168.1.101` binding because `.101` is already assigned to verified `RITRUECHAI-AP01`; the active RouterOS phase fails closed on this inventory conflict.
- Removed obsolete active-contract assumptions for `prod=.122` and `core=.123` from the RouterOS topology source of truth.

### Cloudflare integration boundary
- Added a secret-free Cloudflare connector/origin template and documented the optional DNS, Access, and Tunnel trust boundary.
- Added explicit repository, runtime, rollback, and GitHub review gates; no Cloudflare provisioning or live RouterOS mutation is included.

### Verified RB4011 production topology
- Replaced the stale static-WAN assumption with the verified `ether1` DHCP WAN contract; the observed `192.168.202.91/21` lease is runtime evidence only.
- Made `DBC-Bridge-Local = 192.168.1.1/24` the canonical LAN bridge and retained `ether2`-`ether10` plus `sfp-sfpplus1` as LAN ports.
- Added `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` as the clean rebuild/recovery source of truth.
- Removed obsolete numbered legacy phases for clean-slate identity, PPPoE networking, unverified segmentation, alternate WireGuard, fixed shaping, and superseded logging.

### Production safety hardening
- Added exact SHA-256 dry-run manifests and blocks live apply when phase contents have changed since the successful dry-run.
- Added one-session RouterOS Safe Mode apply with explicit Safe Mode and all-phase success sentinels.
- Added AES-SHA256 controller-managed binary backups, local backup-password protection, download verification flow, and router-side temporary-file cleanup.
- Made dry-run uploads unique and removes temporary files after validation.
- Made RouterOS update checks read-only with respect to update-channel state and requires the running RouterOS version to change before reporting an update successful.
- Changed network, DHCP/DNS, firewall, and NAT management to preserve unowned state and fail closed on ownership conflicts.
- Added an explicit SSH public-key bootstrap helper and isolated RouterOS safety lab test plan.

### Documentation and GitHub operations
- Rebuilt the project documentation map and added architecture, installation, testing, release, network-recovery, SSH-hardening, GitHub-operations, roadmap, support, governance, maintainer, and licensing guidance.
- Added GitHub community templates and CODEOWNERS guidance.
- Added documentation validation to prevent stale repository names and broken local Markdown references.
- Clarified the difference between desired automation identity and the actual operator/recovery account on an existing CORE host.
- Added root, CORE, zOS, PROD, topology, and Windows runner VM `.env.example` templates with fail-closed defaults and documented loading/secret-handling rules.
- Added the `zeaz` Windows VM / `zOS-Runner` environment contract and runner-local documentation.

### CORE recovery/hardening
- Added fail-closed OpenSSH bootstrap/recovery for CORE.
- Defaulted SSH password authentication to disabled and added authorized-key lockout prevention.
- Added secure HashiCorp APT signing-key recovery with a reviewed pinned fingerprint.
- Fixed temporary-file cleanup under `set -u`.
- Restored executable Git modes for operational shell entry points.
- Corrected persistent WireGuard conflict reporting so active `.conf` files are evaluated separately from retained backups.

## v2.1 - Real ZeaZDev environment naming
- Canonical DEV host: `core.zeaz.dev`.
- Canonical PROD host: `prod.zeaz.dev`.
- Desired automation SSH identity: `zeazdev`.
- Removed legacy DBC naming from current automation guidance.
- Preserved the PoliceDBC RouterOS production baseline and safe-change workflow.

## v2.0 - PoliceDBC production-safe refactor
- Replaced clean-slate assumptions with the verified PoliceDBC topology.
- Added hard prechecks for WAN, LAN, default route, and WireGuard.
- Added backup, dry-run, Safe Mode, and explicit live-change gates.
- Deprecated the old PPPoE/192.168.10.0 production assumptions.

## v1.0
- Initial clean-slate PPPoE-oriented design.
