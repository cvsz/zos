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


## แนวทางกู้คืนระบบบริหารจัดการ (Fail-closed)

ทุกกรณีต้องรักษาช่องทางบริหารจัดการอิสระ เช่น console, MAC-WinBox หรือ SSH session สำรองไว้เสมอ ห้ามปิดวิธียืนยันตัวตนสุดท้ายที่ยังใช้งานได้ กำหนด rollback trigger ก่อนแก้ระบบ และตรวจสอบ management, WAN, LAN, DHCP, DNS, WireGuard, firewall/NAT และบริการที่เกี่ยวข้องหลังการกู้คืน การใช้งานกับ Production ต้องมี operator approval และ recovery path ที่ยืนยันแล้ว

### 1. SSH authentication failure

- **Independent access:** ใช้ console, MAC-WinBox หรือ SSH session ที่เชื่อมต่ออยู่แล้ว และอย่าปิด session สำรอง
- **Diagnosis:** ตรวจ `/user print`, `/ip service print`, SSH key fingerprints และ `ROUTER_SSH_KEY` โดยระวังการเปิดเผยข้อมูลลับ
- **Rollback trigger:** หยุดทันทีเมื่อการเปลี่ยน key อาจทำให้ key-only access ใช้งานไม่ได้ และคืนค่า SSH key configuration เดิมจาก export ที่ตรวจสอบแล้ว
- **Operator decision:** เพิ่มหรือ rotate key เฉพาะเมื่อมีช่องทาง recovery และทดสอบการเข้าสู่ระบบจาก client แยกก่อนปิด session เก่า
- **Verification:** ยืนยัน public-key login และ management ACL ตาม policy ที่ใช้งานจริง

### 2. Management access lockout (SSH + WinBox)

- **Independent access:** ใช้ physical console หรือ MAC-WinBox ใน LAN segment; ห้าม reboot โดยไม่ตรวจสอบ
- **Diagnosis:** ตรวจ `/ip service print`, `/user print` และกฎใน `ZEAZ-PoliceDBC-INPUT` โดยใช้ช่องทาง recovery
- **Rollback trigger:** หากอยู่ใน Safe Mode และ management หาย ให้ปล่อย transaction rollback แทนการ commit
- **Operator decision:** เปิด management เฉพาะ LAN/VPN ที่อนุมัติ และแก้เฉพาะกฎที่เป็นสาเหตุ ห้ามลบ firewall/NAT แบบกว้าง
- **Verification:** ทดสอบ SSH, WinBox, ACL และบันทึก audit evidence

### 3. Incorrect default route

- **Independent access:** ต้องมี LAN-side management ซึ่งไม่พึ่ง default route ที่กำลังแก้
- **Diagnosis:** ตรวจ `/ip route print detail`, `/ip dhcp-client print` และสถานะ `ether1`; เทียบกับ baseline ที่ยืนยันแล้ว
- **Rollback trigger:** หากสูญเสีย upstream reachability หรือ management access ให้หยุดและคืนค่า routing/DHCP-client เดิม
- **Operator decision:** แก้ WAN/default route เฉพาะ approved maintenance window พร้อม Safe Mode และ recovery
- **Verification:** ทดสอบ default route, upstream connectivity และ DNS โดยใช้ target ที่อนุมัติ

### 4. LAN or DHCP outage (`192.168.1.0/24`)

- **Independent access:** ใช้ direct LAN/console และเตรียม static-IP client ที่ไม่ชนกับ address ที่ใช้งาน
- **Diagnosis:** ตรวจ `/ip address print`, `/ip pool print`, `/ip dhcp-server print`, network และ leases เทียบกับ inventory ล่าสุด
- **Rollback trigger:** เมื่อ lease ใหม่ล้มเหลวหรือพบการชนกับ fixed reservations ให้หยุดการเปลี่ยนแปลง
- **Operator decision:** ปรับเฉพาะ pool/network/DNS ที่เป็นเจ้าของและผ่าน verification ห้ามลบ pool ของระบบอื่น
- **Verification:** ตรวจ fixed reservations, dynamic leases, local DNS และ reboot persistence หากแก้ persistent configuration

### 5. Firewall rule lockout

- **Independent access:** ใช้ console/MAC-WinBox และรักษา Safe Mode session เมื่อรองรับ
- **Diagnosis:** ตรวจ filter chains, jump counters และ diff ของกฎที่เปลี่ยนล่าสุด
- **Rollback trigger:** หาก management ถูก block หลังเปลี่ยน firewall ให้ rollback Safe Mode และไม่ commit
- **Operator decision:** เปลี่ยนเฉพาะกฎที่เป็นเจ้าของและพิสูจน์ว่าเป็นสาเหตุ ห้าม flush chains หรือแก้ foreign rules อัตโนมัติ
- **Verification:** ตรวจ management reachability, intended services และ ownership contract

### 6. WireGuard loss (`wg-remote` / `policedbc`)

- **Independent access:** ใช้ LAN/SSH ที่ไม่พึ่ง WireGuard; ห้าม rotate key โดยไม่อนุมัติ
- **Diagnosis:** ตรวจ WireGuard interfaces/peers, handshake และ routes; `AllowedIPs` ต้องไม่ครอบ physical LAN `192.168.1.0/24`
- **Rollback trigger:** หาก handshake หรือ routing เสียหลังเปลี่ยน peer ให้คืนค่าจาก key material ที่ตรวจสอบแล้ว
- **Operator decision:** ทำ key handoff ระหว่าง RouterOS และ CORE อย่างชัดเจนก่อนยืนยัน VPN
- **Verification:** ตรวจ handshake, overlay routing และการแยก physical LAN

### 7. Failed RouterOS deployment (apply-safe)

- **Independent access:** ใช้ management session แยกเพื่อตรวจสอบ rollback
- **Diagnosis:** เก็บ sanitized transcript, phase markers, nonce-bound signals และ health-check output
- **Rollback trigger:** script error, timeout, disconnect, session conflict หรือ health failure ต้องไม่ commit
- **Operator decision:** แก้ phase ที่ล้มเหลว ทดสอบ dry-run ใหม่และขอ maintenance approval ก่อนเปลี่ยน production
- **Verification:** ตรวจ rollback จริงผ่าน independent management; mock PASS ไม่ใช่ CHR evidence

### 8. Failed backup or restore

- **Independent access:** รักษา controller shell และ backup/password stores โดยไม่เปิดเผย secrets
- **Diagnosis:** ตรวจ manifest, artifact SHA-256, provenance, nonempty checks และ sanitized restore-drill evidence
- **Rollback trigger:** checksum, provenance, password หรือ isolation gate ล้มเหลว ต้องหยุดก่อน restore
- **Operator decision:** สร้าง backup ID ใหม่ตามความเหมาะสม และทดสอบ restore บน disposable CHR ที่อนุมัติเท่านั้น
- **Verification:** ตรวจ manifest/checksums และเก็บ restore evidence; การมี backup file ไม่ใช่ proof of recoverability

### 9. CHR recovery after interrupted restore

- **Independent access:** ใช้ hypervisor console และ isolated CHR management network ที่ไม่มี route ไป production
- **Diagnosis:** ตรวจ CHR boot/version, artifact provenance, ก่อน/หลัง restore และ sanitized logs
- **Rollback trigger:** หาก CHR state ไม่แน่นอน ให้ทำลาย disposable instance แล้ว provision ใหม่จาก verified image; ห้ามนำ production credentials ไปใช้
- **Operator decision:** ทำ restore drill ใหม่บน CHR ที่แยกจริงโดยบันทึก elapsed recovery time
- **Verification:** ตรวจ RouterOS version, configuration contract, management, networking และ expected services แล้ว archive evidence ก่อน teardown
