:log warning "OMEGA LEGACY DHCP QUARANTINE START"
:put "===== OMEGA LEGACY DHCP QUARANTINE ====="

:local legacyLanRanges "192.168.1.50-192.168.1.99,192.168.1.109-192.168.1.118,192.168.1.121-192.168.1.237,192.168.1.240-192.168.1.254"

:if ([/ip pool print count-only where name="lan-pool"] != 1) do={ :error "MIGRATION REFUSED: lan-pool is not unique" }
:if ([/ip pool print count-only where name="wifi-pool"] != 1) do={ :error "MIGRATION REFUSED: wifi-pool is not unique" }
:if ([/ip pool print count-only where name="zeaz-pool"] != 1) do={ :error "MIGRATION REFUSED: zeaz-pool is not unique" }
:local lanPool [/ip pool find where name="lan-pool"]
:local wifiPool [/ip pool find where name="wifi-pool"]
:local zeazPool [/ip pool find where name="zeaz-pool"]

:if ([/ip pool get $lanPool ranges] != $legacyLanRanges) do={ :error "MIGRATION REFUSED: lan-pool ranges changed from inspected legacy state" }
:if ([/ip pool get $lanPool next-pool] != "zeaz-pool") do={ :error "MIGRATION REFUSED: lan-pool no longer points to zeaz-pool" }
:if ([/ip pool get $wifiPool ranges] != "192.168.0.0/24") do={ :error "MIGRATION REFUSED: wifi-pool ranges changed from inspected legacy state" }
:if ([/ip pool get $wifiPool next-pool] != "lan-pool") do={ :error "MIGRATION REFUSED: wifi-pool no longer points to lan-pool" }
:if ([/ip pool get $zeazPool ranges] != "192.168.10.0/24") do={ :error "MIGRATION REFUSED: zeaz-pool ranges changed from inspected legacy state" }
:if ([/ip pool get $zeazPool next-pool] != "wifi-pool") do={ :error "MIGRATION REFUSED: zeaz-pool no longer points to wifi-pool" }

:if ([/ip pool used print count-only where pool="wifi-pool"] > 0) do={ :error "MIGRATION REFUSED: wifi-pool has active usage" }
:if ([/ip pool used print count-only where pool="zeaz-pool"] > 0) do={ :error "MIGRATION REFUSED: zeaz-pool has active usage" }
:if ([/ip dhcp-server print count-only where address-pool="wifi-pool"] > 0) do={ :error "MIGRATION REFUSED: DHCP server still references wifi-pool" }
:if ([/ip dhcp-server print count-only where address-pool="zeaz-pool"] > 0) do={ :error "MIGRATION REFUSED: DHCP server still references zeaz-pool" }
:if ([/ip dhcp-server print count-only where interface="ether1"] > 0) do={ :error "MIGRATION REFUSED: DHCP server still exists on WAN ether1" }
:if ([/ip arp print count-only where address~"^192\\.168\\.0\\."] > 0) do={ :error "MIGRATION REFUSED: legacy 192.168.0.x ARP state is still present" }
:if ([/ip arp print count-only where address~"^192\\.168\\.10\\."] > 0) do={ :error "MIGRATION REFUSED: legacy 192.168.10.x ARP state is still present" }
:if ([/ip dhcp-server lease print count-only where address~"^192\\.168\\.0\\."] > 0) do={ :error "MIGRATION REFUSED: legacy 192.168.0.x DHCP lease is still present" }
:if ([/ip dhcp-server lease print count-only where address~"^192\\.168\\.10\\."] > 0) do={ :error "MIGRATION REFUSED: legacy 192.168.10.x DHCP lease is still present" }

:if ([/ip address print count-only where address="192.168.0.0/24" and interface="DBC-Bridge-Local"] != 1) do={ :error "MIGRATION REFUSED: expected one legacy 192.168.0.0/24 bridge address" }
:local legacyAddress [/ip address find where address="192.168.0.0/24" and interface="DBC-Bridge-Local"]

:if ([/ip dhcp-server network print count-only where address="192.168.0.0/24"] != 1) do={ :error "MIGRATION REFUSED: expected one 192.168.0.0/24 DHCP network" }
:if ([/ip dhcp-server network print count-only where address="192.168.1.0/24"] != 1) do={ :error "MIGRATION REFUSED: expected one 192.168.1.0/24 DHCP network" }
:if ([/ip dhcp-server network print count-only where address="192.168.10.0/24"] != 1) do={ :error "MIGRATION REFUSED: expected one 192.168.10.0/24 DHCP network" }
:local net0 [/ip dhcp-server network find where address="192.168.0.0/24"]
:local net1 [/ip dhcp-server network find where address="192.168.1.0/24"]
:local net10 [/ip dhcp-server network find where address="192.168.10.0/24"]

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

:local lanNextAfter [/ip pool get $lanPool next-pool]
:local wifiNextAfter [/ip pool get $wifiPool next-pool]
:local zeazNextAfter [/ip pool get $zeazPool next-pool]
:if ($lanNextAfter != "" && $lanNextAfter != "none") do={ :error "VERIFY FAIL: lan-pool fallback remains" }
:if ($wifiNextAfter != "" && $wifiNextAfter != "none") do={ :error "VERIFY FAIL: wifi-pool fallback remains" }
:if ($zeazNextAfter != "" && $zeazNextAfter != "none") do={ :error "VERIFY FAIL: zeaz-pool fallback remains" }
:if ([/ip address print count-only where address="192.168.0.0/24" and interface="DBC-Bridge-Local"] > 0) do={ :error "VERIFY FAIL: legacy bridge address remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.0.0/24"] > 0) do={ :error "VERIFY FAIL: legacy 192.168.0.0/24 DHCP network remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.10.0/24"] > 0) do={ :error "VERIFY FAIL: legacy 192.168.10.0/24 DHCP network remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.1.0/24"] != 1) do={ :error "VERIFY FAIL: production LAN DHCP network is not unique after migration" }
:local verifyNet1 [/ip dhcp-server network find where address="192.168.1.0/24"]
:if ([/ip dhcp-server network get $verifyNet1 dns-server] != "192.168.1.1") do={ :error "VERIFY FAIL: production LAN DNS was not migrated to RouterOS" }

:put "LEGACY DHCP QUARANTINE PASS"
:log warning "OMEGA LEGACY DHCP QUARANTINE PASS"
