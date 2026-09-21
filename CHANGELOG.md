# Changelog

Notable repository and operational changes are recorded here. zOS has not yet declared a stable public API; version numbers below describe repository milestones.

## Unreleased

### DHCP pool normalization and phase diagnostics
- Normalize RouterOS `/ip pool get ... ranges` values with `:tostr` before comparing them with the verified legacy/desired contracts.
- Represent the single dynamic address `192.168.1.121` canonically instead of as a degenerate start/end range.
- Capture RouterOS import errors with `:onerror` per phase and include the failing phase filename plus the native RouterOS error text.
- Include `/ip pool print detail` and `/ip pool used print detail` in read-only audits so fallback pools such as `next-pool` can be reviewed before mutation.


### RouterOS Safe Mode persistent receive buffer
- Preserve one SSH receive buffer across prompt, Safe Mode confirmation, SAFE-prompt, and transaction-result stages.
- Prevent loss of `<SAFE>` when RouterOS emits it in the same SSH read as `Taking Safe Mode session... Success!`.
- Add a regression test for same-chunk Safe Mode confirmation and SAFE prompt delivery.


### RouterOS Safe Mode prompt synchronization
- Wait for the interactive RouterOS CLI prompt before sending Ctrl-X.
- Require both `[Safe Mode taken]` and the `<SAFE>` prompt before sending the production transaction.
- Detect Safe Mode hijack prompts during the handshake and decline ownership.
- Use split RouterOS PASS/FAIL sentinel strings so terminal input echo cannot be mistaken for executed results.
- Request Ctrl-D rollback on transactional failure or timeout.


### Retained vulnerability and package evidence
- Generate Trivy filesystem and controller-image vulnerability SARIF before enforcement gates.
- Generate a package-aware CycloneDX SBOM from the built controller image.
- Retain Trivy SARIF and CycloneDX evidence as GitHub Actions artifacts for 30 days.
- Validate the evidence/output contract in repository safety checks.


### Supply-chain and recovery follow-up
- Pin GitHub Actions to immutable commit SHAs and pin the controller Alpine base image by digest.
- Add Dependabot coverage for GitHub Actions and Docker updates.
- Add Trivy filesystem and controller-image HIGH/CRITICAL vulnerability gates.
- Harden Docker build context exclusions for local topology, backups, state, environment files, and key material.
- Make the golden reinstall refuse already-configured managed targets and converge the current WireGuard, firewall/NAT, service-hardening, and observability baseline.
- Provision a dedicated root-only secret directory for unattended RouterOS backup passwords.


### Production safety hardening
- Make Safe Mode apply transactional so `/quit` is reachable only after every phase, including assertion verification, succeeds.
- Bind dry-run evidence to the exact target router fingerprint, topology config hash, git commit, phase hashes, and a one-hour freshness window.
- Convert health verification into fail-closed assertions for WAN/LAN, DHCP pool, fixed reservations including EnGenius `.50-.58`, WireGuard, reachability, and DNS.
- Package releases from tracked Git content only, block release without a project-wide `LICENSE`, and reject non-main/dirty/out-of-sync release state.
- Add `.dockerignore` protection for local topology, backups, state, environment files, and key material.
- Fail closed on unowned WireGuard state, peer identity drift, foreign firewall rules, duplicate/disabled policy jumps, duplicate DHCP network records, and duplicate static DNS records.
- Separate encrypted-backup password storage from backup artifacts by default and retain post-apply RouterOS evidence exports locally.
- Require RouterOS auto-update to return on the exact version advertised before installation.
- Make `zos doctor` propagate CORE structural-check failures and wire the controller-generated RouterOS SSH key into local topology config.
- Expand secret evidence scanning to tracked documentation and example files.

### Safe Mode apply operator visibility
- Stream RouterOS Safe Mode output in real time instead of buffering the entire interactive SSH session until exit.
- Add a controller-side `flock` guard so a second `apply-safe` run cannot start while another is active.
- Surface RouterOS Safe Mode hijack prompts so stale/external ownership is visible instead of appearing as a silent hang.
- Keep repository validation ShellCheck-clean while asserting the realtime streaming and locking safeguards.


### RouterOS dynamic interface-list ownership guard
- Ignore RouterOS-generated dynamic interface-list memberships when checking explicit WAN/LAN ownership in `20-NETWORK-NORMALIZE.rsc`.
- Preserve fail-closed behavior for static conflicting memberships while avoiding false failures from Detect Internet state such as dynamic `LAN ether1`.
- Add repository validation and runbook coverage for this distinction.


### EnGenius DHCP reservation reconciliation
- Moved `EWS1200D-10T` to reserved `192.168.1.50` and the eight EWS310AP units to `192.168.1.51-.58` using their verified MAC mappings.
- Updated the LAN pool so `.50-.58`, `.100`, `.119`, `.120`, `.122`, `.123`, and `.238` are excluded from dynamic allocation while the former `.101-.108` and `.239` WiFi addresses return to the dynamic pool.
- Added controlled migration from the previous EnGenius reservations while unrelated fixed hosts remain fail-closed on address drift.
- Removed `server=lan-dhcp` updates from existing lease reconciliation to avoid RouterOS `ambiguous value of server` failures; new leases retain the explicit `lan-dhcp` binding without rewriting existing lease ownership.
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
