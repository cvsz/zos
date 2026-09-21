# ZeaZDev Infrastructure Reference

This file is a compact infrastructure summary. `ENVIRONMENTS.md` is the canonical environment inventory and `docs/ARCHITECTURE.md` describes trust boundaries and data flow.

## Router baseline

- Device: PoliceDBC MikroTik RB4011iGS+.
- RouterOS baseline: 7.24.2+.
- WAN: DHCP client on `ether1`; observed lease `192.168.202.91/21` is runtime evidence only.
- Upstream gateway observed from DHCP: `192.168.200.1`.
- LAN: `DBC-Bridge-Local = 192.168.1.1/24`.
- LAN ports: `ether2`-`ether10` and `sfp-sfpplus1`.
- Dynamic DHCP ranges: `192.168.1.59-99`, `101-118`, `121`, `124-237`, and `239-254`.
- Fixed infrastructure `.50-.58`, `.100`, `.119`, `.120`, `.122`, `.123`, and `.238` is excluded from dynamic allocation.
- WireGuard target: `wg-remote = 10.8.0.1/24`, UDP 51820.
- CORE WireGuard peer target: `10.8.0.2/32`.

## Fixed LAN inventory

| Host | IPv4 | MAC |
|---|---|---|
| EWS1200D-10T | `192.168.1.50` | `88:DC:96:53:0F:55` |
| RITRUECHAI-AP01 | `192.168.1.51` | `88:DC:96:55:58:E4` |
| RITRUECHAI-AP02 | `192.168.1.52` | `88:DC:96:55:58:E7` |
| BOONNAK-AP01 | `192.168.1.53` | `88:DC:96:55:58:F0` |
| BOONNAK-AP02 | `192.168.1.54` | `88:DC:96:55:58:DE` |
| SARASIN-AP02 | `192.168.1.55` | `88:DC:96:55:58:ED` |
| SARASIN-AP01 | `192.168.1.56` | `88:DC:96:55:58:EA` |
| PANKHONGCHUEN-AP01 | `192.168.1.57` | `88:DC:96:55:58:F3` |
| PANKHONGCHUEN-AP02 | `192.168.1.58` | `88:DC:96:55:58:E1` |
| PoliceDBC-SEA | `192.168.1.100` | `48:4D:7E:D4:3A:C6` |
| ha-a.zeaz.dev | `192.168.1.119` | `00:0C:29:B7:22:AF` |
| ha-b.zeaz.dev | `192.168.1.120` | `00:0C:29:72:EF:42` |
| prod.zeaz.dev | `192.168.1.122` | `00:0C:29:B5:F4:09` |
| core.zeaz.dev | `192.168.1.123` | `00:0C:29:75:A6:D4` |
| ZEAZ Wifi Repeater / `wifi.zeaz.dev` | `192.168.1.238` | `E4:90:2A:40:61:21` |

## Address authority

The current repository baseline keeps `prod.zeaz.dev=.122` and `core.zeaz.dev=.123`. Moving the EnGenius controller/AP estate to `.50-.58` removes the previous `.101` overlap and keeps infrastructure reservations outside the dynamic pool.

## CORE contract

~~~text
physical interface: ens33
WireGuard interface: policedbc
default route:      via 192.168.1.1 on ens33
physical LAN:       192.168.1.0/24 on ens33
WireGuard network:  10.8.0.0/24 on policedbc
~~~

`core.zeaz.dev = 192.168.1.123` retains the verified repository MAC binding.

## Identity model

`zeazdev` is the desired automation SSH identity in the topology contract. Existing hosts may be administered during recovery by another local account. Scripts must use the actual selected account rather than assuming the desired automation identity already exists.

## Legacy warning

The old static-WAN, `bridge-lan`, PPPoE, `192.168.10.0/24`, and alternate-WireGuard assumptions are historical and must not be applied to PoliceDBC production.
