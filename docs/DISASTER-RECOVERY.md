# Disaster Recovery

## ลำดับความสำคัญ

1. กู้คืนช่องทางบริหารจัดการที่เชื่อถือได้ผ่าน local/MAC/console/recovery;
2. กู้คืนการบริหาร RouterOS ผ่าน LAN (`192.168.1.1/24`);
3. กู้คืน WAN/upstream routing;
4. กู้คืน DHCP/DNS;
5. กู้คืน WireGuard ด้วย key material ที่เชื่อถือได้และทราบที่มา;
6. กู้คืน CORE route/SSH invariants;
7. ตรวจสอบ firewall/NAT และ application reachability;
8. เก็บหลักฐานหลังการกู้คืน.

## RouterOS Safe Mode

ใช้ Safe Mode สำหรับการเปลี่ยนแปลงที่มีความเสี่ยงในกรณีที่ RouterOS รองรับ การหลุดของ Safe Mode session แบบผิดปกติสามารถทำให้การเปลี่ยนแปลงถูก rollback ได้ แต่ Safe Mode ไม่ใช่สิ่งทดแทน export และ backup.

## Backups

Text export เป็นข้อมูลสำหรับกู้คืนที่ตรวจสอบได้ ส่วนไฟล์ binary `.backup` เป็นข้อมูลอ่อนไหวและผูกกับ device/configuration จึงต้องเก็บให้ปลอดภัยและอยู่นอก Git โดยค่าเริ่มต้น backup password ที่สร้างขึ้นจะถูกเก็บแยกไว้ใต้ `state/backup-secrets/` (เปลี่ยนได้ด้วย `OMEGA_BACKUP_PASSWORD_DIR`) ต้องปกป้องทั้งสองตำแหน่งและห้ามเผยแพร่.

ทุก controller backup ที่สำเร็จจะ publish `omega-policedbc-<timestamp-pid-random>.rsc/.backup` with `.sha256` sidecars and a `<id>.manifest.json` binding `backup_id/commit_sha/created_at/router_host/artifact checksums` (no secrets). Downloads stage as private `.part` files, require both artifacts nonempty, then publish atomically; partial/empty results never report success and never publish a manifest. Router temp files are cleaned best-effort only after the local verified copy exists, without masking the original error. Retention (`OMEGA_BACKUP_RETENTION_COUNT`, default 30) never deletes the only verified copy; `OMEGA_BACKUP_OFFHOST_DIR` holds an optional off-host copy. การมีไฟล์ backup อยู่เฉย ๆ ไม่ใช่ restore evidence — exercise `tools/restore-drill.sh` on disposable CHR before declaring recoverability.

## Restore drill (เฉพาะ disposable CHR)

~~~bash
tools/restore-drill.sh --backup-id <omega-policedbc-...> --mock
~~~

Drill นี้ตรวจสอบ manifest integrity, SHA-256 ของทั้งสอง artifact, provenance และการมีอยู่ของ password ก่อน restore ทุกครั้ง ปฏิเสธ production target ผ่าน blocklist แม้จะมี authorization และกำหนดให้มี `--allow-live-restore` plus `OMEGA_ALLOW_LIVE_RESTORE=1`, `OMEGA_CHR_ISOLATED=1`, `OMEGA_CHR_AUTHORIZED_BY=<operator>` and a proven SSH management path for live use. Mock mode จะบันทึก `MOCK PASS` พร้อม elapsed time และ sanitized evidence ใต้ `artifacts/restore-drill/`; การรันกับ CHR จริงโดยไม่มี target ที่แยกและยืนยันแล้วต้องคงสถานะ `BLOCKED` และห้าม mutation ห้าม restore production จาก backup หากไม่มี independent recovery path และ explicit approval.

## การกู้คืน CORE route

สถานะที่ต้องได้:

~~~text
default via 192.168.1.1 dev ens33
192.168.1.0/24 dev ens33
10.8.0.0/24 dev policedbc
~~~

ใช้ `docs/NETWORK-RECOVERY.md` โดย persistent `policedbc` `AllowedIPs` ต้องไม่รวม physical LAN.

## การกู้คืน CORE SSH

ใช้ `core/install.sh` / `docs/SSH-HARDENING.md` ห้ามปิด authentication path สุดท้ายที่ยังใช้งานได้ และต้องพิสูจน์ public-key access จาก client อื่นก่อนปิด recovery session.

## Package/APT trust failure

หากตรวจสอบ signature ของ third-party repository ไม่ได้ ให้คง signature enforcement ไว้และซ่อม trust จาก authoritative key material ที่ผ่าน review แล้ว ห้ามกู้ service ด้วยการเปิด insecure APT trust แบบ global.

## การกู้คืน GitHub runner

Runner path/task:

~~~text
D:\zOS-Runner
Scheduled Task: zOS-GitHub-Runner
~~~

ให้ restart scheduled listener ตัวเดิมก่อนพิจารณา re-registration ต้องรักษา runner credentials และห้าม commit.

## การตรวจสอบหลังการกู้คืน

หลัง recovery ให้รัน repository validation ซ้ำในส่วนที่มี code change แล้วจึงตรวจ CORE/router จริง หาก incident เกี่ยวข้องกับ persistent network หรือ SSH configuration ต้องมี reboot test.

## Disaster-recovery exercise

DR plan จะยังไม่ถือว่ามีหลักฐานครบจนกว่าจะ exercise restore/rollback ใน environment ที่เหมาะสมและบันทึกผลไว้ การที่ CI ผ่านไม่ใช่ restore evidence.


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

## Management recovery runbooks (practical, fail-closed)

General rules for every scenario below: keep an independent management path (local console/MAC-WinBox/second SSH) open; never disable the last working authentication path; define rollback triggers before mutating; record operator decision points; repeat post-recovery verification (management, WAN/default route, LAN/DHCP/DNS, WireGuard, firewall/NAT, intended services).

### 1. SSH authentication failure
- Independent access: use console/MAC-WinBox or a second SSH session that is already authenticated; do not close it.
- Diagnose: `make status` (read-only), check `/user print`, `/ip service print`, SSH key fingerprints on router vs controller (`ROUTER_SSH_KEY`).
- Rollback triggers: any change that risks key-only lockout stops immediately; restore prior `/user ssh-keys` from export.
- Decision: rotate/add keys only with `core/install-ssh-key.sh --host <ip> --user <user> --private-key <key>` and prove login from a separate client before closing recovery.
- Verify: independent key login, `PermitRootLogin no`, password auth unchanged per contract.

### 2. Management access lockout (SSH + WinBox)
- Independent access: physical console or MAC-WinBox on the LAN segment; never reboot blindly.
- Diagnose: `/ip service print`, `/user print`, firewall `ZEAZ-PoliceDBC-INPUT` for foreign accept/drop covering management ports.
- Rollback triggers: if Safe Mode is available, enter it before touching firewall/services; abnormal disconnect must roll back.
- Decision: re-enable LAN/VPN-only management from console; remove only the offending zOS-owned rule (comment `^PoliceDBC:`), never bulk-delete filter/NAT.
- Verify: SSH + WinBox from LAN, services limited to approved interfaces, audit log reviewed.

### 3. Incorrect default route
- Independent access: LAN-side management (route change must not orphan the operator).
- Diagnose: `/ip route print detail where dst-address=0.0.0.0/0`, `/ip dhcp-client print`, `ether1` status; compare with `00-PRECHECK.rsc` expectations (DHCP WAN on `ether1`).
- Rollback triggers: loss of upstream ping (`192.168.200.1`, `1.1.1.1`) or loss of management stops further changes; re-apply prior route/DHCP-client state.
- Decision: fix DHCP-client/default-route only in an approved window with Safe Mode; never change WAN without recovery access.
- Verify: default via DHCP, `make verify` upstream/internet/DNS checks pass.

### 4. LAN or DHCP outage (`192.168.1.0/24`)
- Independent access: direct LAN/console; keep static-IP client ready (e.g., `192.168.1.10/24` via `DBC-Bridge-Local`).
- Diagnose: `/ip address print`, `/ip pool print`, `/ip dhcp-server print/network/lease`, `lan-pool` ranges vs contract; check `next-pool=none`.
- Rollback triggers: new leases failing or fixed inventory (`.50-.58`, `.100`, `.122`, `.123`) conflicting stops the change.
- Decision: converge pool/network/DNS only to the verified contract; quarantine legacy pools via `make migrate-legacy-dhcp` gates, never delete pool objects broadly.
- Verify: fixed reservations present, dynamic leases succeed, `wifi.zeaz.dev/core/prod` DNS resolve, reboot persistence if changed.

### 5. Firewall rule lockout
- Independent access: console/MAC-WinBox; keep a Safe Mode session where supported.
- Diagnose: `/ip firewall filter print` in `ZEAZ-PoliceDBC-INPUT/FORWARD`, jump counters, recent change diff.
- Rollback triggers: management drop after a firewall phase → let Safe Mode unroll (abnormal close) instead of committing.
- Decision: remove/disable only the specific zOS-owned rule (`comment~"^PoliceDBC:"`); never flush chains or remove foreign rules automatically.
- Verify: management + intended service reachability, `OWN-02/OWN-03` ownership expectations hold.

### 6. WireGuard loss (`wg-remote`/`policedbc`)
- Independent access: LAN/SSH without VPN dependency; do not rotate keys silently.
- Diagnose: `/interface wireguard print/peers print`, handshake timestamps, `AllowedIPs` must exclude `192.168.1.0/24`, CORE `10.8.0.0/24 via policedbc`.
- Rollback triggers: handshake failure after peer change → revert to trusted known key material from pre-change export.
- Decision: reconcile router public key (`OMEGA WG ROUTER PUBLIC KEY=...`) on CORE explicitly before VPN acceptance; no private key in Git.
- Verify: handshake recent, `10.8.0.0/24` routes via `policedbc`, LAN excluded from `AllowedIPs`.

### 7. Failed RouterOS deployment (apply-safe)
- Independent access: second management session for rollback verification.
- Diagnose: collect sanitized transcript, phase marker (`OMEGA_PHASE_FILE:`), nonce-bound pass/fail, health output; confirm Safe Mode released vs unrolled.
- Rollback triggers: script error, timeout, disconnect, stale Safe Mode, concurrent apply, failed health → do not commit; close session, require independent rollback verification.
- Decision: fix phase content, re-run `make dry-run` (fresh manifest), then single smallest idempotent apply in a new window.
- Verify: `99-VERIFY-HEALTH.rsc` sentinel, management/WAN/LAN/DHCP/WireGuard/firewall checks.

### 8. Failed backup or restore
- Independent access: controller shell with `backups/` + `state/backup-secrets/` intact; never delete the only verified copy.
- Diagnose: backup manifest (both artifacts, SHA-256, nonempty, atomic publish) or restore-drill evidence (`MOCK PASS`/`FAIL`/`BLOCKED`, elapsed, checks); inspect for partial/empty/tamper without printing secrets.
- Rollback triggers: checksum/provenance/password failure stops before any restore; production target always refused.
- Decision: re-run `make backup` (new unique ID), then `tools/restore-drill.sh --mock`; live restore only on disposable CHR with full authorization gates.
- Verify: new manifest validates, `sha256sum -c` passes, restore-drill evidence archived, off-host copy reconciled if configured.

### 9. CHR recovery after an interrupted restore
- Independent access: hypervisor console + isolated CHR management on lab VLAN only; confirm no route to production.
- Diagnose: CHR state (boot, identity, version, file list), last restore-drill evidence, elapsed time, before/after sanitized diffs.
- Rollback triggers: uncertain CHR state → destroy and re-provision disposable CHR from known image (URL + SHA-256 recorded); never reuse production credentials/keys.
- Decision: re-run golden bootstrap on a clean target (prove `GR-01` refusal first if state remains), then restore drill again; record actual elapsed recovery time.
- Verify: RouterOS version, configuration contract, management access, networking, expected services; archive sanitized before/after evidence; teardown disposable CHR.
