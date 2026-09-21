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

Review every topology value before use. The verified production router contract is `ether1` DHCP WAN and `DBC-Bridge-Local = 192.168.1.1/24`. A DHCP-assigned WAN address is runtime evidence and must not be hard-coded.

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

The active phase stack assumes the live router already matches the verified WAN/LAN split. If `ether1` is still bridged or another unowned object conflicts with the contract, normalization fails closed instead of silently taking ownership. RouterOS-generated dynamic interface-list memberships (for example Detect Internet classifying `ether1` as LAN) are observational state and are not treated as explicit ownership conflicts; only static list memberships block normalization.

For a clean rebuild, use `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` through an operator-controlled console/MAC-WinBox recovery path. The golden script now refuses targets that already contain the managed DHCP/WireGuard/firewall state; reset/clean the recovery target first. Do not use it as a live-normalization script.

## 5. Back up

~~~bash
make backup
~~~

`make backup` creates a text export and an AES-SHA256 encrypted binary RouterOS backup and downloads both to `backups/`. The generated decryption password is stored separately with mode 0600 under the protected controller state secret directory (or `OMEGA_BACKUP_SECRET_DIR` when explicitly configured), not beside the backup artifact. Temporary router-side backup files are removed after successful download. Keep both artifacts and decryption secrets outside source control and back them up through separate trusted storage paths.

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

The controller uses unique temporary RouterOS filenames for dry-runs and removes them after the import attempt. A successful dry-run records the exact phase SHA-256 manifest plus the reviewed git commit, topology-file hash, target router identity/board/architecture/RouterOS version, and timestamp. Live apply rejects evidence older than `OMEGA_DRY_RUN_MAX_AGE_SECONDS` (default 3600 seconds), a different target/runtime, a changed topology file, a different commit, or changed phase content.

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

Production apply always requires both a current dry-run and RouterOS Safe Mode; the previous bypass branches are intentionally disabled. zOS uses one interactive RouterOS CLI session, waits for `[Safe Mode taken]`, sends exactly one phase at a time, and waits for `OMEGA_PHASE_PASS` before sending the next phase. A phase failure, timeout, Safe Mode hijack/release, or missing sentinel stops the sequence and exits with Ctrl-D so RouterOS rolls back the current Safe Mode transaction. Only after `99-VERIFY-HEALTH.rsc` passes inside Safe Mode does zOS emit `OMEGA_APPLY_PASS` and commit the verified transaction.

Do not bypass this workflow with ad-hoc individual imports for ordinary production changes. Keep a recovery-capable management path open for the entire transaction. MikroTik Safe Mode history is finite, so production phases must remain bounded and reviewable rather than becoming bulk migration engines.

## 8. Verify

~~~bash
make verify
make e2e
~~~

Independently verify management, `ether1` WAN DHCP/default route, `DBC-Bridge-Local` LAN, DHCP/DNS, the fixed host inventory, WireGuard handshake, firewall/NAT, and intended service reachability.

Current fixed/reserved LAN inventory:

~~~text
PoliceDBC-SEA       192.168.1.100  48:4D:7E:D4:3A:C6
core.zeaz.dev       192.168.1.123  00:0C:29:75:A6:D4
prod.zeaz.dev       192.168.1.122  00:0C:29:B5:F4:09
EWS1200D-10T        192.168.1.50   88:DC:96:53:0F:55
RITRUECHAI-AP01     192.168.1.51   88:DC:96:55:58:E4
RITRUECHAI-AP02     192.168.1.52   88:DC:96:55:58:E7
BOONNAK-AP01        192.168.1.53   88:DC:96:55:58:F0
BOONNAK-AP02        192.168.1.54   88:DC:96:55:58:DE
SARASIN-AP02        192.168.1.55   88:DC:96:55:58:ED
SARASIN-AP01        192.168.1.56   88:DC:96:55:58:EA
PANKHONGCHUEN-AP01  192.168.1.57   88:DC:96:55:58:F3
PANKHONGCHUEN-AP02  192.168.1.58   88:DC:96:55:58:E1
ha-a.zeaz.dev       192.168.1.119  00:0C:29:B7:22:AF
ha-b.zeaz.dev       192.168.1.120  00:0C:29:72:EF:42
wifi.zeaz.dev       192.168.1.238  E4:90:2A:40:61:21
~~~

The repository baseline for CORE and PROD remains `core=.123`, `prod=.122`. EnGenius controller/AP reservations use `.50-.58`; if RouterOS shows the new reservation in `address` but an older value in `active-address`, renew or reboot only that AP during a controlled window before declaring migration complete.

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
