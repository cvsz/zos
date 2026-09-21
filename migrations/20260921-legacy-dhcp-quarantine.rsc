:log warning "OMEGA LEGACY DHCP QUARANTINE START"
:put "===== OMEGA LEGACY DHCP QUARANTINE ====="

:local legacyLanRanges "192.168.1.50-192.168.1.99,192.168.1.109-192.168.1.118,192.168.1.121-192.168.1.237,192.168.1.240-192.168.1.254"

:local lanPool [/ip pool find where name="lan-pool"]
:local wifiPool [/ip pool find where name="wifi-pool"]
:local zeazPool [/ip pool find where name="zeaz-pool"]
:if ([:len $lanPool] != 1) do={ :error "MIGRATION REFUSED: lan-pool is not unique" }
:if ([:len $wifiPool] != 1) do={ :error "MIGRATION REFUSED: wifi-pool is not unique" }
:if ([:len $zeazPool] != 1) do={ :error "MIGRATION REFUSED: zeaz-pool is not unique" }

:if ([/ip pool get $lanPool ranges] != $legacyLanRanges) do={ :error "MIGRATION REFUSED: lan-pool ranges changed from inspected legacy state" }
:if ([/ip pool get $lanPool next-pool] != "zeaz-pool") do={ :error "MIGRATION REFUSED: lan-pool no longer points to zeaz-pool" }
:if ([/ip pool get $wifiPool ranges] != "192.168.0.0/24") do={ :error "MIGRATION REFUSED: wifi-pool ranges changed from inspected legacy state" }
:if ([/ip pool get $wifiPool next-pool] != "lan-pool") do={ :error "MIGRATION REFUSED: wifi-pool no longer points to lan-pool" }
:if ([/ip pool get $zeazPool ranges] != "192.168.10.0/24") do={ :error "MIGRATION REFUSED: zeaz-pool ranges changed from inspected legacy state" }
:if ([/ip pool get $zeazPool next-pool] != "wifi-pool") do={ :error "MIGRATION REFUSED: zeaz-pool no longer points to wifi-pool" }

:if ([:len [/ip pool used find where pool="wifi-pool"]] > 0) do={ :error "MIGRATION REFUSED: wifi-pool has active usage" }
:if ([:len [/ip pool used find where pool="zeaz-pool"]] > 0) do={ :error "MIGRATION REFUSED: zeaz-pool has active usage" }
:if ([:len [/ip dhcp-server find where address-pool="wifi-pool"]] > 0) do={ :error "MIGRATION REFUSED: DHCP server still references wifi-pool" }
:if ([:len [/ip dhcp-server find where address-pool="zeaz-pool"]] > 0) do={ :error "MIGRATION REFUSED: DHCP server still references zeaz-pool" }
:if ([:len [/ip dhcp-server find where interface="ether1"]] > 0) do={ :error "MIGRATION REFUSED: DHCP server still exists on WAN ether1" }
:if ([:len [/ip arp find where address~"^192\\.168\\.(0|10)\\."]] > 0) do={ :error "MIGRATION REFUSED: legacy 192.168.0/10 client ARP state is still present" }

:local legacyAddress [/ip address find where address="192.168.0.0/24" and interface="DBC-Bridge-Local"]
:if ([:len $legacyAddress] != 1) do={ :error "MIGRATION REFUSED: expected one legacy 192.168.0.0/24 bridge address" }

:local net0 [/ip dhcp-server network find where address="192.168.0.0/24"]
:local net1 [/ip dhcp-server network find where address="192.168.1.0/24"]
:local net10 [/ip dhcp-server network find where address="192.168.10.0/24"]
:if ([:len $net0] != 1) do={ :error "MIGRATION REFUSED: expected one 192.168.0.0/24 DHCP network" }
:if ([:len $net1] != 1) do={ :error "MIGRATION REFUSED: expected one 192.168.1.0/24 DHCP network" }
:if ([:len $net10] != 1) do={ :error "MIGRATION REFUSED: expected one 192.168.10.0/24 DHCP network" }

:if ([/ip dhcp-server network get $net0 gateway] != "192.168.1.1") do={ :error "MIGRATION REFUSED: legacy 192.168.0.0/24 gateway changed" }
:if ([/ip dhcp-server network get $net10 gateway] != "192.168.1.1") do={ :error "MIGRATION REFUSED: legacy 192.168.10.0/24 gateway changed" }
:if ([/ip dhcp-server network get $net1 gateway] != "192.168.1.1") do={ :error "MIGRATION REFUSED: production LAN gateway changed" }
:local lanDns [/ip dhcp-server network get $net1 dns-server]
:if ($lanDns != "1.1.1.1,8.8.8.8" && $lanDns != "192.168.1.1") do={ :error ("MIGRATION REFUSED: production LAN DNS changed to " . $lanDns) }
:if ([/ip dns get allow-remote-requests] != true) do={ :error "MIGRATION REFUSED: router DNS cache is not enabled for LAN clients" }

# แยก legacy pools ออกจาก production โดยไม่ลบ object เพื่อเก็บหลักฐานและ rollback path
# พร้อมตัด fallback edge ทุกเส้นออกจาก production
:if ([/ip pool get $lanPool next-pool] != "none") do={ /ip pool set $lanPool next-pool=none }
:if ([/ip pool get $wifiPool next-pool] != "none") do={ /ip pool set $wifiPool next-pool=none }
:if ([/ip pool get $zeazPool next-pool] != "none") do={ /ip pool set $zeazPool next-pool=none }

# ถอนเฉพาะ DHCP network legacy สองรายการที่ตรวจสอบแล้ว
 /ip dhcp-server network remove $net0
 /ip dhcp-server network remove $net10

# ให้ production clients ใช้ RouterOS DNS cache ได้ เพราะตรวจ allow-remote-requests ไว้ด้านบนแล้ว
 /ip dhcp-server network set $net1 dns-server=192.168.1.1

# ถอนเฉพาะ legacy bridge address ที่ตรวจแล้ว โดยไม่แตะ 192.168.1.1/24
 /ip address remove $legacyAddress

:if ([/ip pool get $lanPool next-pool] != "none") do={ :error "VERIFY FAIL: lan-pool fallback remains" }
:if ([/ip pool get $wifiPool next-pool] != "none") do={ :error "VERIFY FAIL: wifi-pool fallback remains" }
:if ([/ip pool get $zeazPool next-pool] != "none") do={ :error "VERIFY FAIL: zeaz-pool fallback remains" }
:if ([:len [/ip address find where address="192.168.0.0/24" and interface="DBC-Bridge-Local"]] > 0) do={ :error "VERIFY FAIL: legacy bridge address remains" }
:if ([:len [/ip dhcp-server network find where address="192.168.0.0/24"]] > 0) do={ :error "VERIFY FAIL: legacy 192.168.0.0/24 DHCP network remains" }
:if ([:len [/ip dhcp-server network find where address="192.168.10.0/24"]] > 0) do={ :error "VERIFY FAIL: legacy 192.168.10.0/24 DHCP network remains" }
:if ([/ip dhcp-server network get $net1 dns-server] != "192.168.1.1") do={ :error "VERIFY FAIL: production LAN DNS was not migrated to RouterOS" }

:put "LEGACY DHCP QUARANTINE PASS"
:log warning "OMEGA LEGACY DHCP QUARANTINE PASS"
