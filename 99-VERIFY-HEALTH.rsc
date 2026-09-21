:log warning "OMEGA VERIFY START"
:put "===== OMEGA VERIFY ====="

:local desiredRanges "192.168.1.59-192.168.1.99,192.168.1.101-192.168.1.118,192.168.1.121-192.168.1.121,192.168.1.124-192.168.1.237,192.168.1.239-192.168.1.254"
:local poolId [/ip pool find where name="lan-pool"]
:if ([:len $poolId] != 1) do={ :error "VERIFY FAIL: lan-pool must exist exactly once" }
:if ([/ip pool get $poolId ranges] != $desiredRanges) do={ :error "VERIFY FAIL: lan-pool does not match the fixed-host exclusion contract" }

:local dhcpId [/ip dhcp-server find where name="lan-dhcp"]
:if ([:len $dhcpId] != 1) do={ :error "VERIFY FAIL: lan-dhcp must exist exactly once" }
:if ([/ip dhcp-server get $dhcpId interface] != "DBC-Bridge-Local") do={ :error "VERIFY FAIL: lan-dhcp interface mismatch" }
:if ([/ip dhcp-server get $dhcpId address-pool] != "lan-pool") do={ :error "VERIFY FAIL: lan-dhcp pool mismatch" }
:if ([/ip dhcp-server get $dhcpId disabled] = true) do={ :error "VERIFY FAIL: lan-dhcp is disabled" }

:local expectedHosts {
    "88:DC:96:53:0F:55=192.168.1.50";
    "88:DC:96:55:58:E4=192.168.1.51";
    "88:DC:96:55:58:E7=192.168.1.52";
    "88:DC:96:55:58:F0=192.168.1.53";
    "88:DC:96:55:58:DE=192.168.1.54";
    "88:DC:96:55:58:ED=192.168.1.55";
    "88:DC:96:55:58:EA=192.168.1.56";
    "88:DC:96:55:58:F3=192.168.1.57";
    "88:DC:96:55:58:E1=192.168.1.58";
    "48:4D:7E:D4:3A:C6=192.168.1.100";
    "00:0C:29:B7:22:AF=192.168.1.119";
    "00:0C:29:72:EF:42=192.168.1.120";
    "00:0C:29:B5:F4:09=192.168.1.122";
    "00:0C:29:75:A6:D4=192.168.1.123";
    "E4:90:2A:40:61:21=192.168.1.238"
}
:foreach item in=$expectedHosts do={
    :local sep [:find $item "="]
    :local mac [:pick $item 0 $sep]
    :local expectedAddress [:pick $item ($sep + 1) [:len $item]]
    :local leaseId [/ip dhcp-server lease find where mac-address=$mac]
    :if ([:len $leaseId] != 1) do={ :error ("VERIFY FAIL: expected exactly one lease for " . $mac) }
    :if ([/ip dhcp-server lease get $leaseId address] != $expectedAddress) do={ :error ("VERIFY FAIL: reservation mismatch for " . $mac) }
}

:local wgId [/interface wireguard find where name="wg-remote"]
:if ([:len $wgId] != 1) do={ :error "VERIFY FAIL: wg-remote must exist exactly once" }
:if ([/interface wireguard get $wgId listen-port] != 51820) do={ :error "VERIFY FAIL: wg-remote listen-port mismatch" }
:if ([/interface wireguard get $wgId mtu] != 1420) do={ :error "VERIFY FAIL: wg-remote MTU mismatch" }
:if ([:len [/ip address find where address="10.8.0.1/24" and interface="wg-remote"]] != 1) do={ :error "VERIFY FAIL: WireGuard gateway address missing/duplicated" }

:local peerId [/interface wireguard peers find where interface="wg-remote" and allowed-address="10.8.0.2/32"]
:if ([:len $peerId] != 1) do={ :error "VERIFY FAIL: CORE WireGuard peer missing/duplicated" }
:if ([/interface wireguard peers get $peerId public-key] != "HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8=") do={ :error "VERIFY FAIL: CORE WireGuard public key mismatch" }

:local inputJump [/ip firewall filter find where chain="input" and jump-target="ZEAZ-PoliceDBC-INPUT" and comment="ZEAZ-PoliceDBC: INPUT POLICY" and disabled=no]
:if ([:len $inputJump] != 1) do={ :error "VERIFY FAIL: input policy jump missing/duplicated/disabled" }
:local forwardJump [/ip firewall filter find where chain="forward" and jump-target="ZEAZ-PoliceDBC-FORWARD" and comment="ZEAZ-PoliceDBC: FORWARD POLICY" and disabled=no]
:if ([:len $forwardJump] != 1) do={ :error "VERIFY FAIL: forward policy jump missing/duplicated/disabled" }
:local natJump [/ip firewall nat find where chain="srcnat" and jump-target="ZEAZ-PoliceDBC-SRCNAT" and comment="ZEAZ-PoliceDBC: SRCNAT POLICY" and disabled=no]
:if ([:len $natJump] != 1) do={ :error "VERIFY FAIL: srcnat policy jump missing/duplicated/disabled" }

:if ([:len [/ip route find where dst-address="0.0.0.0/0" and active=yes]] = 0) do={ :error "VERIFY FAIL: active default route missing" }
:local upstreamReplies [/ping 192.168.200.1 count=3]
:if ($upstreamReplies = 0) do={ :error "VERIFY FAIL: upstream gateway unreachable" }
:local internetReplies [/ping 1.1.1.1 count=3]
:if ($internetReplies = 0) do={ :error "VERIFY FAIL: internet IP unreachable" }

:put [/resolve cloudflare.com]
:if ([/resolve prod.zeaz.dev] != "192.168.1.122") do={ :error "VERIFY FAIL: prod.zeaz.dev resolution mismatch" }
:if ([/resolve core.zeaz.dev] != "192.168.1.123") do={ :error "VERIFY FAIL: core.zeaz.dev resolution mismatch" }
:if ([/resolve ha-a.zeaz.dev] != "192.168.1.119") do={ :error "VERIFY FAIL: ha-a.zeaz.dev resolution mismatch" }
:if ([/resolve ha-b.zeaz.dev] != "192.168.1.120") do={ :error "VERIFY FAIL: ha-b.zeaz.dev resolution mismatch" }

:put "===== VERIFIED STATE ====="
/system resource print
/ip address print detail
/interface bridge port print where bridge="DBC-Bridge-Local"
/interface list member print detail
/ip dhcp-client print detail where interface="ether1"
/ip dhcp-server print detail where name="lan-dhcp"
/ip dhcp-server lease print detail where mac-address~"88:DC:96"
/interface wireguard print detail where name="wg-remote"
/interface wireguard peers print detail where interface="wg-remote"
/ip route print where dst-address="0.0.0.0/0"
/export terse file=omega-policedbc-after
:put "OMEGA VERIFY PASS"
:log warning "OMEGA VERIFY PASS"
