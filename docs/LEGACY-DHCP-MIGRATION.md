# Legacy DHCP Quarantine Migration

เอกสารนี้ใช้สำหรับ migration แบบ one-shot ของ legacy DHCP topology ที่ตรวจพบจริงบน RB4011iGS+ เมื่อวันที่ 2026-09-21 เท่านั้น ห้ามใช้กับ RouterOS อื่นหรือ topology ที่ state ไม่ตรงกับ precondition ใน migration script

## ขอบเขตที่ตรวจพบ

Live inspection ยืนยันว่า production LAN ใช้ `lan-dhcp` บน `DBC-Bridge-Local` และ `lan-pool` แต่ยังมี legacy fallback chain:

```text
lan-pool  -> zeaz-pool
zeaz-pool -> wifi-pool
wifi-pool -> lan-pool
```

legacy objects ที่ยังคงอยู่และต้องแยกออกจาก production คือ:

- `wifi-pool = 192.168.0.0/24`
- `zeaz-pool = 192.168.10.0/24`
- `192.168.0.0/24` บน `DBC-Bridge-Local`
- DHCP network `192.168.0.0/24`
- DHCP network `192.168.10.0/24`
- production DHCP network `192.168.1.0/24` ที่ยังแจก DNS `1.1.1.1,8.8.8.8`

Live inspection ล่าสุดไม่พบ pool usage สำหรับ `wifi-pool` หรือ `zeaz-pool`, ไม่พบ legacy ARP และไม่พบ DHCP server ที่ใช้ legacy pools แล้ว

## หลักอ้างอิง MikroTik

ใช้เอกสารทางการของ MikroTik เป็น source of truth:

- RouterOS manual index: https://manual.mikrotik.com/llms.txt
- Safe Mode / Console: https://manual.mikrotik.com/docs/management-tools/console/
- Configuration Management / Safe Mode: https://manual.mikrotik.com/docs/getting-started/configuration-management/
- DHCP: https://manual.mikrotik.com/docs/network-management/dhcp/
- IP pool used: https://manual.mikrotik.com/docs/cli-reference/ip/pool/used/
- Scripting / `:onerror` / import dry-run: https://manual.mikrotik.com/docs/developer-guides/scripting/

RouterOS DHCP ใช้ `address-pool` เพื่อแจก address และ DHCP network เป็นจุดกำหนด gateway/DNS ให้ client ตามเอกสารทางการ ส่วน Safe Mode ใช้ Ctrl-X/F4 เพื่อเข้า mode และ Ctrl-D เพื่อออกแบบ undo หาก transaction fail

## Safety contract

ไฟล์ `migrations/20260921-legacy-dhcp-quarantine.rsc` จะไม่ลบ `wifi-pool` หรือ `zeaz-pool` ออกจาก router แต่จะ quarantine โดยตัด `next-pool` ทุกเส้นออกก่อน แล้วถอนเฉพาะ legacy network/address ที่ตรวจสอบแล้ว

Migration จะ refuse ทันทีถ้าพบข้อใดข้อหนึ่ง:

- pool name/ranges/fallback chain เปลี่ยนจาก inspected state
- `wifi-pool` หรือ `zeaz-pool` มี active usage
- มี DHCP server อ้างถึง legacy pool
- มี DHCP server บน WAN `ether1`
- มี ARP หรือ DHCP lease ใน `192.168.0.0/24` หรือ `192.168.10.0/24`
- legacy address/network ไม่ unique
- production LAN gateway/DNS เปลี่ยนจาก inspected contract
- RouterOS DNS cache ไม่ได้เปิด `allow-remote-requests=yes`

เมื่อ precondition ผ่าน migration จะทำเฉพาะ:

1. ตั้ง `next-pool=none` ให้ `lan-pool`, `wifi-pool`, `zeaz-pool`
2. ถอน DHCP network `192.168.0.0/24`
3. ถอน DHCP network `192.168.10.0/24`
4. ตั้ง DHCP network `192.168.1.0/24` ให้แจก DNS `192.168.1.1`
5. ถอน address `192.168.0.0/24` จาก `DBC-Bridge-Local`
6. assert state หลัง migration ก่อน Safe Mode transaction ถูก commit

## วิธีรัน

ก่อนรันต้อง sync `main` และตรวจ working tree:

```bash
cd ~/zos
git pull --ff-only origin main
git status --short
make validate
```

Migration ใช้ explicit opt-in สองชั้น:

```bash
export OMEGA_ALLOW_LEGACY_DHCP_MIGRATION=1
export OMEGA_ALLOW_LIVE_APPLY=1
make migrate-legacy-dhcp
```

Target นี้จะรัน repository validation, encrypted RouterOS backup, RouterOS import dry-run และ Safe Mode apply ตามลำดับ ถ้า guard ใด fail จะไม่ถือว่า migration สำเร็จ

## หลัง migration

ตรวจ state แบบ read-only:

```bash
./tools/omega-router.sh legacy-dhcp-status
```

จากนั้นต้องสร้าง production dry-run ใหม่ เพราะ live topology และ Git state เปลี่ยน:

```bash
make backup
make dry-run
export OMEGA_ALLOW_LIVE_APPLY=1
make apply
make verify
```

Production apply จะเป็นผู้ migrate `lan-pool` จาก legacy ranges ไปยัง ranges ที่ reserve EnGenius `.50-.58` และ fixed infrastructure ตาม contract ปัจจุบัน

## Rollback

ก่อน mutation runner สร้างทั้ง text export และ encrypted binary backup ผ่าน `tools/omega-router.sh backup` และ mutation เกิดภายใน RouterOS Safe Mode ถ้า migration import/assertion fail session driver จะ request rollback ตาม Safe Mode contract

ห้ามลบ `wifi-pool` หรือ `zeaz-pool` หลัง migration จนกว่าจะผ่าน production apply, `make verify`, EnGenius convergence และ rollback evidence review ครบ
