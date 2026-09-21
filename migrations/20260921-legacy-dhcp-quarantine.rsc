:log warning "OMEGA LEGACY DHCP QUARANTINE START"
:put "===== OMEGA LEGACY DHCP QUARANTINE ====="

:do {
:local lanPool 0
:local wifiPool 1
:local zeazPool 2

:if ([/ip pool print count-only where name="lan-pool"] != 1) do={ :error "MIGRATION REFUSED: lan-pool is not unique" }
:if ([/ip pool print count-only where name="wifi-pool"] != 1) do={ :error "MIGRATION REFUSED: wifi-pool is not unique" }
:if ([/ip pool print count-only where name="zeaz-pool"] != 1) do={ :error "MIGRATION REFUSED: zeaz-pool is not unique" }
:if ([/ip pool get $lanPool name] != "lan-pool") do={ :error "MIGRATION REFUSED: lan-pool is not at index 0" }
:if ([/ip pool get $wifiPool name] != "wifi-pool") do={ :error "MIGRATION REFUSED: wifi-pool is not at index 1" }
:if ([/ip pool get $zeazPool name] != "zeaz-pool") do={ :error "MIGRATION REFUSED: zeaz-pool is not at index 2" }

:if ([:tostr [/ip pool get $lanPool ranges]] != "192.168.1.50-192.168.1.99;192.168.1.109-192.168.1.118;192.168.1.121-192.168.1.237;192.168.1.240-192.168.1.254") do={ :error "MIGRATION REFUSED: lan-pool ranges changed from inspected legacy state" }
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

:local legacyAddress 4
:if ([/ip address get $legacyAddress address] != "192.168.0.0/24") do={ :error "MIGRATION REFUSED: address[4] is not 192.168.0.0/24" }
:if ([/ip address print count-only where address="192.168.0.0/24" and interface="DBC-Bridge-Local"] != 1) do={ :error "MIGRATION REFUSED: expected one legacy 192.168.0.0/24 bridge address" }

:local net0 0
:local net1 1
:local net10 2
:if ([/ip dhcp-server network get $net0 address] != "192.168.0.0/24") do={ :error "MIGRATION REFUSED: net0 is not 192.168.0.0/24" }
:if ([/ip dhcp-server network get $net1 address] != "192.168.1.0/24") do={ :error "MIGRATION REFUSED: net1 is not 192.168.1.0/24" }
:if ([/ip dhcp-server network get $net10 address] != "192.168.10.0/24") do={ :error "MIGRATION REFUSED: net10 is not 192.168.10.0/24" }
:if ([/ip dhcp-server network get $net0 gateway] != "192.168.1.1") do={ :error "MIGRATION REFUSED: legacy 192.168.0.0/24 gateway changed" }
:if ([/ip dhcp-server network get $net10 gateway] != "192.168.1.1") do={ :error "MIGRATION REFUSED: legacy 192.168.10.0/24 gateway changed" }
:if ([/ip dhcp-server network get $net1 gateway] != "192.168.1.1") do={ :error "MIGRATION REFUSED: production LAN gateway changed" }
:local lanDns [/ip dhcp-server network get $net1 dns-server]
:if ($lanDns != "1.1.1.1,8.8.8.8" && $lanDns != "192.168.1.1") do={ :error ("MIGRATION REFUSED: production LAN DNS changed to " . $lanDns) }
:if ([/ip dns get allow-remote-requests] != true) do={ :error "MIGRATION REFUSED: router DNS cache is not enabled for LAN clients" }

/ip dhcp-server network set $net1 dns-server=192.168.1.1

:if ([/ip pool get $lanPool next-pool] != "none") do={ /ip pool set $lanPool next-pool=none }
:if ([/ip pool get $wifiPool next-pool] != "none") do={ /ip pool set $wifiPool next-pool=none }
:if ([/ip pool get $zeazPool next-pool] != "none") do={ /ip pool set $zeazPool next-pool=none }

/ip dhcp-server network remove $net10
/ip dhcp-server network remove $net0
/ip address remove $legacyAddress

:if ([/ip address print count-only where address="192.168.0.0/24" and interface="DBC-Bridge-Local"] > 0) do={ :error "VERIFY FAIL: legacy bridge address remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.0.0/24"] > 0) do={ :error "VERIFY FAIL: legacy 192.168.0.0/24 DHCP network remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.10.0/24"] > 0) do={ :error "VERIFY FAIL: legacy 192.168.10.0/24 DHCP network remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.1.0/24"] != 1) do={ :error "VERIFY FAIL: production LAN DHCP network is not unique after migration" }
:if ([/ip dhcp-server network print count-only where address="192.168.1.0/24" and dns-server="192.168.1.1"] != 1) do={ :error "VERIFY FAIL: production LAN DNS was not migrated to RouterOS" }

:put "LEGACY DHCP QUARANTINE PASS"
:log warning "OMEGA LEGACY DHCP QUARANTINE PASS"
}
