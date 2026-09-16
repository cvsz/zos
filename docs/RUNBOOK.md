# ZeaZDev MikroTik End-to-End Runbook

This is the primary operator sequence. Detailed recovery, SSH, GitHub, release, and lab procedures are linked from `docs/INDEX.md`.

## 1. Prepare the controller

~~~bash
git clone https://github.com/cvsz/zos.git
cd zos
cp config/topology.env.example config/topology.env
chmod 600 config/topology.env
./tools/install-controller.sh
./zOS/bin/zos doctor
~~~

Review every topology value before use. The verified production router contract is `ether1` DHCP WAN and `bridgeLocal = 192.168.1.1/24`. A DHCP-assigned WAN address is runtime evidence and must not be hard-coded.

## 2. Establish CORE network and SSH

Update the repository as its owner, not root:

~~~bash
cd /home/<repo-owner>/zos
git pull --ff-only origin main
sudo ./core/install.sh
make core-check
make core-find-conflict
~~~

The secure installer path requires an existing public key and defaults to `PasswordAuthentication no`. Keep the current recovery session open until a separate client proves key-only login. See `docs/SSH-HARDENING.md`.

For key recovery, use the tracked helper with an explicit target and local SSH key validation:

~~~bash
bash ./core/install-ssh-key.sh --host <core-ip-or-hostname> --user <core-user> --private-key <key-path>
~~~

Required routing:

~~~text
default via 192.168.1.1 dev ens33
192.168.1.0/24 dev ens33
10.8.0.0/24 dev policedbc
~~~

Active `policedbc` configuration must not route `192.168.1.0/24`. Backups may retain historical values for rollback.

`core.zeaz.dev = 192.168.1.123` is paired with verified MAC `00:0C:29:75:A6:D4`.

## 3. Validate repository state

~~~bash
make validate
make docs
make evidence
make security-evidence
./zOS/bin/zos help
~~~

Green repository checks are necessary but are not proof of live production readiness.

## 4. Inspect router state

~~~bash
make status
make audit
~~~

The active phase stack assumes the live router already matches the verified WAN/LAN split. If `ether1` is still bridged or another unowned object conflicts with the contract, normalization fails closed instead of silently taking ownership.

For a clean rebuild, use `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` through an operator-controlled console/MAC-WinBox recovery path; do not use the live phase stack as a substitute for clean-install bootstrap.

## 5. Back up

~~~bash
make backup
~~~

`make backup` creates a text export and an AES-SHA256 encrypted binary RouterOS backup, downloads both, stores the generated backup password locally with restrictive permissions, and removes the temporary controller-created files from the router after successful download. Keep the local evidence outside source control.

## 6. Dry-run intended phases

~~~bash
make dry-run
~~~

Active production phases:

~~~text
00-PRECHECK.rsc
10-BACKUP-SNAPSHOT.rsc
20-NETWORK-NORMALIZE.rsc
30-DHCP-DNS-NTP.rsc
40-WIREGUARD-SERVICES.rsc
50-FIREWALL-NAT.rsc
60-OBSERVABILITY.rsc
90-EXPORT-EVIDENCE.rsc
99-VERIFY-HEALTH.rsc
~~~

The controller uses unique temporary RouterOS filenames for dry-runs and removes them after the import attempt. A successful dry-run records a SHA-256 manifest of the exact active phase files. Any later phase change makes that manifest stale and blocks live apply until dry-run succeeds again.

Historical clean-slate/PPPoE/alternate-WireGuard paths are not part of the active production phase sequence.

## 7. Apply only in an approved change window

Fail-closed defaults are:

~~~text
OMEGA_REQUIRE_DRY_RUN=1
OMEGA_REQUIRE_SAFE_MODE=1
OMEGA_ALLOW_LIVE_APPLY=0
~~~

After a successful current dry-run, explicitly enable live apply only for the approved window:

~~~bash
export OMEGA_ALLOW_LIVE_APPLY=1
make apply
~~~

When Safe Mode is required, zOS uses one interactive RouterOS CLI session for all phase imports, requires RouterOS to confirm `[Safe Mode taken]`, and requires the explicit `OMEGA_APPLY_PASS` sentinel before treating the operation as successful. A failed phase or missing Safe Mode confirmation fails closed.

Do not bypass this workflow with ad-hoc individual imports for ordinary production changes. Do not release Safe Mode until independent verification succeeds.

## 8. Verify

~~~bash
make verify
make e2e
~~~

Independently verify management, `ether1` WAN DHCP/default route, `bridgeLocal` LAN, DHCP/DNS, the fixed host inventory, WireGuard handshake, firewall/NAT, and intended service reachability.

Current fixed/reserved LAN inventory:

~~~text
PoliceDBC-SEA       192.168.1.100  48:4D:7E:D4:3A:C6
core.zeaz.dev       192.168.1.123  00:0C:29:75:A6:D4
prod.zeaz.dev       192.168.1.122  00:0C:29:B5:F4:09
RITRUECHAI-AP01     192.168.1.101  88:DC:96:55:58:E4
RITRUECHAI-AP02     192.168.1.102  88:DC:96:55:58:E7
BOONNAK-AP01        192.168.1.103  88:DC:96:55:58:F0
BOONNAK-AP02        192.168.1.104  88:DC:96:55:58:DE
SARASIN-AP02        192.168.1.105  88:DC:96:55:58:ED
SARASIN-AP01        192.168.1.106  88:DC:96:55:58:EA
PANKHONGCHUEN-AP01  192.168.1.107  88:DC:96:55:58:F3
PANKHONGCHUEN-AP02  192.168.1.108  88:DC:96:55:58:E1
ha-a.zeaz.dev       192.168.1.119  00:0C:29:B7:22:AF
ha-b.zeaz.dev       192.168.1.120  00:0C:29:72:EF:42
wifi.zeaz.dev       192.168.1.238  E4:90:2A:40:61:21
EWS1200D-10T        192.168.1.239  88:DC:96:53:0F:55
~~~

The existing repository baseline for CORE and PROD is authoritative for this change: `core=.123`, `prod=.122`. The supplied WiFi inventory is added without reassigning those addresses.

## 9. Update automation

RouterOS update checks are read-only with respect to persistent update-channel configuration:

~~~bash
make update-check
~~~

The checker refuses a channel mismatch instead of changing `/system package update channel`. Unattended installation requires both `OMEGA_AUTO_ROUTEROS_UPDATE=1` and `OMEGA_ALLOW_ROUTER_REBOOT=1`. Update success requires the router to return and report a different running RouterOS version from the pre-update value.

## 10. GitHub and runner

CI validates/builds/packages. It does not perform ordinary live production mutation. The optional `zOS-Runner` probe is trusted validation only. See `docs/GITHUB-OPERATIONS.md` and `docs/SELF_HOSTED_RUNNER.md`.

Use `docs/ROUTEROS-LAB-TEST-PLAN.md` to exercise Safe Mode rollback, ownership conflicts, dry-run staleness, backups, and update behavior on an isolated disposable RouterOS lab before relying on those controls in production.

## 11. Acceptance

Use `CHECKLIST.md` and `docs/PRODUCTION-READINESS.md`. Record the commit/release, relevant CI runs, pre-change audit, backup identifiers, current dry-run manifest, live-change approval if any, post-change verification, rollback outcome if exercised, and operator timestamp.
