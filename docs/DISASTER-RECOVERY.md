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
