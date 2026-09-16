# Production Migration

This document records the migration from the historical clean-slate design to the current PoliceDBC production baseline.

## Current naming

- DEV/controller: `core.zeaz.dev`;
- PROD: `prod.zeaz.dev`;
- desired automation identity: `zeazdev` (do not assume it already exists on an existing host).

## Current router baseline

- WAN: DHCP client on `ether1`;
- observed WAN lease: `192.168.202.91/21` (runtime evidence only, never hard-code it);
- upstream gateway observed from DHCP: `192.168.200.1`;
- LAN: `DBC-Bridge-Local = 192.168.1.1/24`;
- LAN ports: `ether2`-`ether10` and `sfp-sfpplus1`;
- NAT: `192.168.1.0/24 -> WAN`;
- WireGuard target: `wg-remote = 10.8.0.1/24`;
- CORE peer target: `10.8.0.2/32`.

## Fixed LAN inventory

~~~text
PoliceDBC-SEA       192.168.1.100  48:4D:7E:D4:3A:C6
core.zeaz.dev       192.168.1.123  00:0C:29:75:A6:D4
prod.zeaz.dev       192.168.1.122  00:0C:29:B5:F4:09
RITRUECHAI-AP01     192.168.1.101  88:DC:96:55:58:E4
RITRUECHAI-AP02     192.168.1.102  88:DC:96:55:58:E7
BOONNAK-AP01        192.168.1.103  88:DC:96:55:58:F0
BOONNAK-AP02        192.168.1.104  88:DC:96:55:58:DE
SARASIN-AP02        192.168.1.105  88:DC:96:55:58:ED
SARASIN-AP01        192.168.1.106  88:DC:96:55:58:EA
PANKHONGCHUEN-AP01  192.168.1.107  88:DC:96:55:58:F3
PANKHONGCHUEN-AP02  192.168.1.108  88:DC:96:55:58:E1
ha-a.zeaz.dev       192.168.1.119  00:0C:29:B7:22:AF
ha-b.zeaz.dev       192.168.1.120  00:0C:29:72:EF:42
wifi.zeaz.dev       192.168.1.238  E4:90:2A:40:61:21
EWS1200D-10T        192.168.1.239  88:DC:96:53:0F:55
~~~

## Address authority

The existing repository baseline remains authoritative for the two VM addresses: `core=.123` and `prod=.122`. The newly supplied inventory adds the verified WiFi infrastructure and confirms `PoliceDBC-SEA=.100`; it does not reassign CORE or PROD.

## Ownership and preservation

The active DHCP phase manages only its named `lan-dhcp` object and verified fixed leases. It must not delete or disable unrelated DHCP servers. Existing upstream DNS resolver configuration is preserved; zOS adds only the local records required by the verified contract.

## Deprecated assumptions

The old static-WAN `192.168.205.251/21`, `bridge-lan`, PPPoE, `192.168.10.0/24`, old CORE `.128`, and alternate WireGuard clean-slate assumptions must not be applied to the current production router.

## Active phase sequence

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

For a clean RouterOS rebuild, use `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` through an operator-controlled recovery path.

Every migration step remains subject to backup, dry-run, recovery/Safe Mode, explicit live-apply approval, and post-change verification.

`PROD_WG_IP` remains unknown and must not be populated until independently observed. Migration documentation must not turn design targets into claims of deployed state.
