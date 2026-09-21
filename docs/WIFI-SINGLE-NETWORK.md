# Single-Network Wi-Fi

เอกสารนี้กำหนด Wi-Fi production profile แบบ **1 SSID / 1 subnet / 1 DHCP domain** สำหรับ EWS1200D-10T + EWS310AP จำนวน 8 ตัว โดยไม่สร้าง Wi-Fi VLAN เพิ่มบน MikroTik

## เป้าหมาย

Topology ที่ต้องการ:

```text
Internet
  |
MikroTik RB4011
192.168.1.1
  |
DBC-Bridge-Local / 192.168.1.0/24
  |
  +-- EWS1200D-10T   192.168.1.50
  +-- EWS310AP       192.168.1.51
  +-- EWS310AP       192.168.1.52
  +-- EWS310AP       192.168.1.53
  +-- EWS310AP       192.168.1.54
  +-- EWS310AP       192.168.1.55
  +-- EWS310AP       192.168.1.56
  +-- EWS310AP       192.168.1.57
  +-- EWS310AP       192.168.1.58
  |
  +-- Wi-Fi clients จาก lan-pool production
```

MikroTik เป็น DHCP/DNS/gateway ตัวเดียว ส่วน EWS1200D เป็น wireless controller และ EWS310AP ทั้ง 8 ตัวใช้ SSID/security profile เดียวกัน

## ข้อกำหนดฝั่ง RouterOS

Wi-Fi profile นี้ **ไม่ต้องสร้าง VLAN interface หรือเปิด bridge VLAN filtering** เพิ่ม

RouterOS ต้องคง:

- LAN bridge: `DBC-Bridge-Local`
- LAN gateway: `192.168.1.1/24`
- DHCP server: `lan-dhcp`
- controller: `192.168.1.50`
- APs: `192.168.1.51-192.168.1.58`
- Wi-Fi clients: ใช้ production `lan-pool` เดียวกับ LAN

ก่อนเปิดใช้งาน Wi-Fi production ต้องให้ legacy DHCP quarantine และ production DHCP convergence ผ่านก่อน

## EWS1200D Controller Profile

สร้าง WLAN profile เดียวและ apply ไปยัง AP group ที่มี EWS310AP ทั้ง 8 ตัว

ค่าที่แนะนำ:

| Setting | Value |
|---|---|
| SSID | ตั้งชื่อจริงใน controller; ค่าใน Git เป็น `CHANGE_ME` เท่านั้น |
| 2.4 GHz | Enabled |
| 5 GHz | Enabled |
| Security | WPA2-PSK / AES |
| VLAN | Disabled / Untagged |
| Band Steering | Enabled |
| Fast Roaming | Enabled |
| Client Isolation | Disabled |
| Guest Network | Disabled |
| Captive Portal | Disabled |
| Auto Channel | Enabled initially |
| Auto Tx Power | Enabled initially |
| 2.4 GHz width | 20 MHz |
| 5 GHz width | 40 MHz initially |

**ห้าม commit Wi-Fi PSK ลง repository** ให้ตั้ง password เฉพาะใน EWS1200D controller

## Roaming

EWS310AP รองรับ Band Steering และ Fast Roaming 802.11k/802.11r เมื่อบริหารผ่าน Neutron/EWS controller

เพื่อให้ Band Steering ทำงานถูกต้อง 2.4 GHz และ 5 GHz ต้องใช้ SSID และ security settings เดียวกัน

แนะนำเปิด Fast Roaming หลังยืนยัน client compatibility แล้ว และตรวจ:

- client สามารถ roam ระหว่าง AP ได้
- DHCP address ไม่เปลี่ยน subnet
- default gateway ยังคง `192.168.1.1`
- DNS ยังคงมาจาก production LAN contract
- ไม่มี rogue DHCP

## RF Baseline

สำหรับ 2.4 GHz ใช้ channel width 20 MHz และหลีกเลี่ยง AP ที่อยู่ใกล้กันใช้ channel เดียวกัน

ตัวอย่าง baseline:

```text
RITRUECHAI-AP01     channel 1
RITRUECHAI-AP02     channel 6
BOONNAK-AP01        channel 11
BOONNAK-AP02        channel 1
SARASIN-AP01        channel 6
SARASIN-AP02        channel 11
PANKHONGCHUEN-AP01  channel 1
PANKHONGCHUEN-AP02  channel 6
```

ถ้าใช้ Auto Channel ให้เก็บ controller evidence หลังระบบ stabilize แล้วจึงพิจารณา pin channel แบบ manual ตาม RF environment จริง

## Read-only Status

หลัง sync repository สามารถดู RouterOS-side Wi-Fi state ได้ด้วย:

```bash
make wifi-status
```

คำสั่งนี้เป็น read-only และแสดง:

- LAN gateway
- DHCP server/network
- production `lan-pool`
- EWS controller/AP leases
- EnGenius ARP
- legacy `192.168.0.0/24` / `192.168.10.0/24` indicators

มันไม่สามารถยืนยัน SSID, PSK, Band Steering หรือ Fast Roaming จาก EWS1200D ได้ เพราะ repository ยังไม่มี authenticated EWS controller API integration

## Acceptance

ถือว่า single-network Wi-Fi พร้อมใช้งานเมื่อมี evidence ครบ:

```text
Router LAN                 192.168.1.1/24
DHCP server                lan-dhcp
Controller                 192.168.1.50
AP reservations            192.168.1.51-58
Managed AP                 8
Active AP                  8
Offline AP                 0
SSID count for production  1
Wi-Fi VLAN                 none / untagged
Band Steering              enabled
Fast Roaming               enabled
Client Isolation           disabled
Guest/Captive Portal       disabled
Rogue DHCP                 0
```

## Vendor references

- EnGenius EWS1200D-10T: https://www.engeniustech.com/apac/products/network-switches/ews1200d-10t/
- EnGenius EWS310AP: https://www.engeniustech.com/apac/products/wireless/indoor-access-points/ews310ap/
- EWS310AP manual: https://www.engeniustech.com/wp-content/uploads/2016/11/EWS310_320_Manual.pdf
- MikroTik RouterOS manual index: https://manual.mikrotik.com/llms.txt
