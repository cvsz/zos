# Disaster Recovery

## Priority order

1. regain a trusted local/MAC/console/recovery management path;
2. restore RouterOS LAN management (`192.168.1.1/24`);
3. restore WAN/upstream routing;
4. restore DHCP/DNS;
5. restore WireGuard with trusted known key material;
6. restore CORE route/SSH invariants;
7. verify firewall/NAT and application reachability;
8. capture post-recovery evidence.

## RouterOS Safe Mode

Use Safe Mode for risky changes where supported. An abnormal loss of the Safe Mode session can roll back those changes, but Safe Mode is not a substitute for an export and backup.

## Backups

Text exports are reviewable recovery inputs. Binary `.backup` files are sensitive and device/configuration-specific; keep them protected and out of Git. Generated backup passwords are stored separately under `state/backup-secrets/` by default (override with `OMEGA_BACKUP_PASSWORD_DIR`); protect both locations and never publish either.

Each successful controller backup publishes `omega-policedbc-<timestamp-pid-random>.rsc/.backup` with `.sha256` sidecars and a `<id>.manifest.json` binding `backup_id/commit_sha/created_at/router_host/artifact checksums` (no secrets). Downloads stage as private `.part` files, require both artifacts nonempty, then publish atomically; partial/empty results never report success and never publish a manifest. Router temp files are cleaned best-effort only after the local verified copy exists, without masking the original error. Retention (`OMEGA_BACKUP_RETENTION_COUNT`, default 30) never deletes the only verified copy; `OMEGA_BACKUP_OFFHOST_DIR` holds an optional off-host copy. A backup file existing is not restore evidence — exercise `tools/restore-drill.sh` on disposable CHR before declaring recoverability.

## Restore drill (disposable CHR only)

~~~bash
tools/restore-drill.sh --backup-id <omega-policedbc-...> --mock
~~~

The drill verifies manifest integrity, both SHA-256 checksums, provenance and password availability before any restore, refuses production targets via blocklist even with authorization, and requires `--allow-live-restore` plus `OMEGA_ALLOW_LIVE_RESTORE=1`, `OMEGA_CHR_ISOLATED=1`, `OMEGA_CHR_AUTHORIZED_BY=<operator>` and a proven SSH management path for live use. Mock mode records `MOCK PASS` with elapsed time and sanitized evidence under `artifacts/restore-drill/`; live CHR execution without a verified isolated target stays `BLOCKED` with no mutation. Never restore production from a backup without an independent recovery path and explicit approval.

## CORE route recovery

Required state:

~~~text
default via 192.168.1.1 dev ens33
192.168.1.0/24 dev ens33
10.8.0.0/24 dev policedbc
~~~

Use `docs/NETWORK-RECOVERY.md`. Persistent `policedbc` `AllowedIPs` must not include the physical LAN.

## CORE SSH recovery

Use `core/install.sh` / `docs/SSH-HARDENING.md`. Do not disable the last working authentication path. Prove public-key access from a separate client before closing the recovery session.

## Package/APT trust failure

If a third-party repository signature cannot be verified, preserve signature enforcement and repair trust from reviewed authoritative key material. Never restore service by enabling insecure APT trust globally.

## GitHub runner recovery

Runner path/task:

~~~text
D:\zOS-Runner
Scheduled Task: zOS-GitHub-Runner
~~~

Restart the single scheduled listener before considering re-registration. Preserve runner credentials and never commit them.

## Recovery verification

After recovery, repeat repository validation where code changed, then live CORE/router checks. Reboot tests are required when the incident involved persistent network or SSH configuration.

## Disaster-recovery exercise

A DR plan is not fully evidenced until restore/rollback has been exercised in an appropriate environment and the result recorded. CI passing is not restore evidence.


## Golden RB4011 clean rebuild

`reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` is the current clean-rebuild bootstrap for the PoliceDBC RB4011 production contract.

Use it only from a recovery-capable console/MAC-WinBox path. It now fails before the first mutation when IP pools, DHCP server/network/lease state, WireGuard interfaces, or firewall/NAT rules are still present. This is intentional: the artifact is not a live-normalization script and must not silently merge with an unknown configuration.

The current golden contract rebuilds:

- `DBC-Bridge-Local = 192.168.1.1/24` with one untagged LAN and no bridge VLAN filtering;
- DHCP WAN on `ether1`;
- production `lan-pool`, `lan-dhcp`, fixed infrastructure and EnGenius `.50-.58` reservations;
- RouterOS DNS cache, managed local DNS, `Asia/Bangkok` timezone, and NTP client;
- `wg-remote = 10.8.0.1/24`, the verified CORE peer, VPN interface-list membership;
- current PoliceDBC firewall/NAT policy, service hardening, and local observability;
- fail-closed post-rebuild assertions before the success sentinel.

No WireGuard private key is committed. A clean rebuild generates a new router WireGuard keypair and prints `OMEGA WG ROUTER PUBLIC KEY=...`; reconcile that public key on CORE before VPN acceptance.

After the golden bootstrap succeeds, run the current guarded phase stack and `99-VERIFY-HEALTH.rsc`. A successful golden import alone is not production acceptance.
