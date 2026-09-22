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

For a clean rebuild, use `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` through an operator-controlled console/MAC-WinBox recovery path; do not use the live phase stack as a substitute for clean-install bootstrap.

## 5. Back up

~~~bash
make backup
~~~

`make backup` creates a text export and an AES-SHA256 encrypted binary RouterOS backup with a unique `timestamp-pid-random` identifier. Both artifacts download into private `mktemp` staging as `.part` files, are validated nonempty, checksummed (SHA-256), then published atomically with `.sha256` sidecars and a `manifest.json` binding `backup_id/commit_sha/created_at/router_host/artifact sha256/bytes` (no passwords/secrets). The backup password travels via stdin pipe (never in ssh argv/ps), shell tracing is disabled around secrets, dirs are `700` and artifacts/manifest/password are `600`. Router temp files are removed only after the local verified copy is complete; partial/empty downloads never report success. Retention keeps the newest `OMEGA_BACKUP_RETENTION_COUNT` (default 30) sets without deleting the only verified copy; `OMEGA_BACKUP_OFFHOST_DIR` enables an optional best-effort off-host copy. Keep the local evidence outside source control. A backup file alone is not proof of recoverability until a restore drill succeeds on disposable CHR.

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

The controller uses unique temporary RouterOS filenames for dry-runs and removes them after the import attempt. A successful dry-run records the exact phase hashes together with the Git commit, topology-config hash, router host/user, router identity, board, architecture, and RouterOS version. The marker expires after one hour by default (`OMEGA_DRY_RUN_MAX_AGE_SECONDS=3600`). Any phase, target, configuration, version, commit, or freshness mismatch blocks live apply until dry-run succeeds again.

Historical clean-slate/PPPoE/alternate-WireGuard paths are not part of the active production phase sequence.

## 7. Production apply is currently blocked

The repository currently **does not provide a CHR-verified interactive RouterOS Safe Mode driver**. Both direct `tools/omega-router.sh apply` and the `apply-safe` driver are fail-closed. Setting `OMEGA_ALLOW_LIVE_APPLY=1` does not make them safe or functional. Do not bypass this gate with ad-hoc SSH imports, production CI, or an unverified alternative driver.

Before enabling live apply in a future reviewed change, require all of the following:

1. A real interactive SSH/PTY session with authenticated host keys, verified RouterOS prompt, and confirmed Safe Mode entry before any mutation.
2. Tests against an isolated CHR target for successful commit, phase failure, timeout, SSH disconnect, stale Safe Mode session, concurrent apply, and rollback.
3. Evidence that command echo cannot spoof a success marker and that failure cannot release Safe Mode as a commit.
4. Verified backup/restore and an independent local management or console recovery path.
5. Current dry-run, router fingerprint, commit SHA, operator approval, and an approved maintenance window.
6. Post-change management, WAN, LAN/DHCP/DNS, WireGuard, firewall/NAT and CORE/PROD connectivity verification.

Keep live apply disabled if any criterion is unverified. Use `docs/ROUTEROS-LAB-TEST-PLAN.md`, `docs/PRODUCTION-READINESS.md`, and `docs/OPENCODE-MASTER-PROMPT.md` to track implementation and evidence. No current CI result substitutes for CHR or production runtime evidence.

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
