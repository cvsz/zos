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

## Restore Drill บน CHR แยกเครือข่าย

ใช้ `tools/restore-drill.sh --backup-id <id> --mock` เพื่อตรวจ Manifest และ Artifact โดยไม่เชื่อมต่อ Router; ผล `MOCK PASS` ไม่ใช่หลักฐานว่า Restore สำเร็จจริง สคริปต์ตรวจฟิลด์ `bytes` ที่ Backup Pipeline สร้าง รวมถึง `backup_id`, `commit_sha`, `created_at`, `router_host`, ชื่อไฟล์ และ SHA-256 จากไฟล์จริง การ Restore บน CHR ยังเป็น `BLOCKED` จนกว่าจะมี Lab ที่แยกเครือข่ายและ Recovery Path ที่พิสูจน์แล้ว

## คู่มือกู้คืนระบบ (fail-closed, ปฏิบัติได้จริง)

หลักการทั่วไปสำหรับทุกสถานการณ์ด้านล่าง: เปิดเส้นทางการจัดการที่เป็นอิสระ (คอนโซลในสถานที่ / MAC-WinBox / SSH ลำดับที่สอง) ทิ้งไว้ก่อนปิด; ห้ามปิดเส้นทางรับรองสุดท้ายที่ใช้งานอยู่; กำหนดจุดเรียกคืนก่อนเปลี่ยนแปลง; บันทึกจุดตัดสินใจของผู้ดำเนินการ; ทำซ้ำการตรวจสอบหลังกู้คืน (การจัดการ, เส้นทาง WAN/default route, LAN/DHCP/DNS, WireGuard, firewall/NAT, บริการที่ตั้งใจ)

### 1. ข้อผิดพลาดการพิสูจน์ตัวตน SSH
- การเข้าถึงที่เป็นอิสระ: ใช้คอนโซล/MAC-WinBox หรือ SSH ลำดับที่สองที่พิสูจน์ตัวตนแล้ว; อย่าปิด
- วินิจฉัย: `make status` (read-only), ตรวจสอบ `/user print`, `/ip service print`, SSH key fingerprint ของ router เทียบกับ controller (`ROUTER_SSH_KEY`)
- จุดเรียกคืน: การเปลี่ยนแปลงที่เสี่ยงต่อการล็อกอินแบบ key-only ต้องหยุดทันที; คืน `/user ssh-keys` ก่อนจาก export
- การตัดสินใจ: หมุน/เพิ่ม keys เฉพาะกับ `core/install-ssh-key.sh --host <ip> --user <user> --private-key <key>` และพิสูจน์การเข้าสู่ระบบจากไคลเอ็นต์แยกก่อนปิด recovery
- ตรวจสอบ: การเข้าสู่ระบบด้วย key อิสระ, `PermitRootLogin no`, password auth ไม่เปลี่ยนแปลงตาม contract

### 2. การสูญเสียสิทธิ์เข้าถึง (SSH + WinBox)
- การเข้าถึงที่เป็นอิสระ: คอนโซลทางกายภาพหรือ MAC-WinBox บน LAN segment; ห้ามรีบูตแบบไม่ไตร่ตรอง
- วินิจฉัย: `/ip service print`, `/user print`, firewall `ZEAZ-PoliceDBC-INPUT` สำหรับ foreign accept/drop ที่ครอบคลุม management ports
- จุดเรียกคืน: หาก Safe Mode มีอยู่ ให้เข้าก่อนแตะ firewall/services; การขาดการเชื่อมต่อที่ผิดปกติต้อง rollback
- การตัดสินใจ: เปิดใช้งาน LAN/VPN-only management ใหม่จาก console; ลบเฉพาะ zOS-owned rule ที่ผิดพลาด (comment `^PoliceDBC:`) ห้ามลบ filter/NAT เป็นกลุ่ม
- ตรวจสอบ: SSH + WinBox จาก LAN, services จำกัดเฉพาะ interfaces ที่อนุมัติ, ตรวจสอบ audit log

### 3. เส้นทาง default route ไม่ถูกต้อง
- การเข้าถึงที่เป็นอิสระ: การจัดการทาง LAN (การเปลี่ยนเส้นทางต้องไม่ทิ้ง operator ให้หลงทาง)
- วินิจฉัย: `/ip route print detail where dst-address=0.0.0.0/0`, `/ip dhcp-client print`, `ether1` status; เปรียบเทียบกับ `00-PRECHECK.rsc` (DHCP WAN บน `ether1`)
- จุดเรียกคืน: สูญเสีย upstream ping (`192.168.200.1`, `1.1.1.1`) หรือสูญเสีย management → หยุดการเปลี่ยนแปลงเพิ่มเติม; คืนค่า route/DHCP-client ก่อน
- การตัดสินใจ: แก้ไข DHCP-client/default-route เฉพาะใน approved window พร้อม Safe Mode; ห้ามเปลี่ยน WAN โดยไม่มี recovery access
- ตรวจสอบ: default via DHCP, `make verify` upstream/internet/DNS checks ผ่าน

### 4. LAN หรือ DHCP ล่ม (`192.168.1.0/24`)
- การเข้าถึงที่เป็นอิสระ: LAN/console โดยตรง; เตรียม static-IP client พร้อม (เช่น `192.168.1.10/24` ผ่าน `DBC-Bridge-Local`)
- วินิจฉัย: `/ip address print`, `/ip pool print`, `/ip dhcp-server print/network/lease`, `lan-pool` ranges เทียบกับ contract; ตรวจสอบ `next-pool=none`
- จุดเรียกคืน: new leases ล้มเหลวหรือ fixed inventory (`.50-.58`, `.100`, `.122`, `.123`) ขัดแย้ง → หยุดการเปลี่ยนแปลง
- การตัดสินใจ: pool/network/DNS convergence เฉพาะ contract ที่ verified; quarantine legacy pools ผ่าน `make migrate-legacy-dhcp` gates ห้ามลบ pool objects กว้าง
- ตรวจสอบ: fixed reservations มีอยู่, dynamic leases สำเร็จ, `wifi.zeaz.dev/core/prod` DNS resolve, reboot persistence หากเปลี่ยน

### 5. firewall rule lockout
- การเข้าถึงที่เป็นอิสระ: คอนโซล/MAC-WinBox; รักษา Safe Mode session ที่รองรับ
- วินิจฉัย: `/ip firewall filter print` ใน `ZEAZ-PoliceDBC-INPUT/FORWARD`, jump counters, recent change diff
- จุดเรียกคืน: management drop หลัง firewall phase → ให้ Safe Mode unroll (abnormal close) แทน commit
- การตัดสินใจ: ลบ/ปิดใช้งานเฉพาะ zOS-owned rule (`comment~"^PoliceDBC:"`); ห้าม flush chains หรือลบ foreign rules โดยอัตโนมัติ
- ตรวจสอบ: management + intended service reachability, `OWN-02/OWN-03` ownership expectations คงอยู่

### 6. WireGuard สูญหาย (`wg-remote`/`policedbc`)
- การเข้าถึงที่เป็นอิสระ: LAN/SSH ไม่ต้องพึ่ง VPN; ห้ามหมุน keys โดยไม่แจ้ง
- วินิจฉัย: `/interface wireguard print/peers print`, handshake timestamps, `AllowedIPs` ต้องยกเว้น `192.168.1.0/24`, CORE `10.8.0.0/24 via policedbc`
- จุดเรียกคืน: handshake failure หลัง peer change → ย้อนกลับไปยัง trusted known key material จาก pre-change export
- การตัดสินใจ: reconcile router public key (`OMEGA WG ROUTER PUBLIC KEY=...`) บน CORE โดยชัดเจนก่อน VPN acceptance; ไม่มี private key ใน Git
- ตรวจสอบ: handshake recent, `10.8.0.0/24` routes via `policedbc`, LAN excluded จาก `AllowedIPs`

### 7. RouterOS deployment ล้มเหลว (apply-safe)
- การเข้าถึงที่เป็นอิสระ: management session ลำดับที่สองสำหรับ rollback verification
- วินิจฉัย: รวบรวม sanitized transcript, phase marker (`OMEGA_PHASE_FILE:`), nonce-bound pass/fail, health output; ยืนยัน Safe Mode released vs unrolled
- จุดเรียกคืน: script error, timeout, disconnect, stale Safe Mode, concurrent apply, failed health → ห้าม commit; ปิด session, ต้องการ rollback verification อย่างอิสระ
- การตัดสินใจ: แก้ไข phase content, รัน `make dry-run` (fresh manifest) ใหม่, แล้ว single smallest idempotent apply ใน window ใหม่
- ตรวจสอบ: `99-VERIFY-HEALTH.rsc` sentinel, management/WAN/LAN/DHCP/WireGuard/firewall checks

### 8. Backup หรือ restore ล้มเหลว
- การเข้าถึงที่เป็นอิสระ: controller shell ที่มี `backups/` + `state/backup-secrets/` สมบูรณ์; ห้ามลบสำเนาที่ verified เพียงชุดเดียว
- วินิจฉัย: backup manifest (ทั้งสอง artifacts, SHA-256, nonempty, atomic publish) หรือ restore-drill evidence (`MOCK PASS`/`FAIL`/`BLOCKED`, elapsed, checks); ตรวจสอบ partial/empty/tamper โดยไม่พิมพ์ secrets
- จุดเรียกคืน: checksum/provenance/password failure → หยุดก่อน restore ใดๆ; production target ปฏิเสธเสมอ
- การตัดสินใจ: รัน `make backup` (unique ID ใหม่), แล้ว `tools/restore-drill.sh --mock`; live restore เฉพาะบน disposable CHR พร้อม full authorization gates
- ตรวจสอบ: manifest ใหม่ validates, `sha256sum -c` ผ่าน, restore-drill evidence archived, off-host copy reconciled หากตั้งค่าไว้

### 9. CHR กู้คืนหลัง restore หยุดชะงัก
- การเข้าถึงที่เป็นอิสระ: hypervisor console + isolated CHR management บน lab VLAN เท่านั้น; ยืนยัน no route สู่ production
- วินิจฉัย: CHR state (boot, identity, version, file list), restore-drill evidence ล่าสุด, elapsed time, before/after sanitized diffs
- จุดเรียกคืน: uncertain CHR state → destroy และ re-provision disposable CHR จาก known image (URL + SHA-256 บันทึก); ห้าม reuse production credentials/keys
- การตัดสินใจ: รัน golden bootstrap บน clean target (พิสูจน์ `GR-01` refusal ก่อนหาก state ยังไม่สมบูรณ์), แล้ว restore drill อีกครั้ง; บันทึก actual elapsed recovery time
- ตรวจสอบ: RouterOS version, configuration contract, management access, networking, expected services; archive sanitized before/after evidence; teardown disposable CHR
