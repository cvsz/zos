:log warning "OMEGA VERIFY START"
:put "===== OMEGA VERIFY ====="

/system resource print

:if ([:len [/ip address find where address="192.168.1.1/24" and interface="DBC-Bridge-Local"]] != 1) do={
    :error "VERIFY FAIL: LAN gateway is not exactly present on DBC-Bridge-Local"
}
:if ([:len [/ip dhcp-client find where interface="ether1" and status="bound"]] != 1) do={
    :error "VERIFY FAIL: ether1 DHCP WAN is not uniquely bound"
}
:if ([:len [/ip route find where dst-address="0.0.0.0/0" and gateway="192.168.200.1"]] = 0) do={
    :error "VERIFY FAIL: expected upstream default route is missing"
}

:local desiredRanges "192.168.1.59-192.168.1.99,192.168.1.101-192.168.1.118,192.168.1.121,192.168.1.124-192.168.1.237,192.168.1.239-192.168.1.254"
:local desiredRangesStr "192.168.1.59-192.168.1.99;192.168.1.101-192.168.1.118;192.168.1.121;192.168.1.124-192.168.1.237;192.168.1.239-192.168.1.254"
:local poolId [/ip pool find where name="lan-pool"]
:if ([:len $poolId] != 1) do={ :error "VERIFY FAIL: lan-pool is not unique" }
:local currentRanges [:tostr [/ip pool get $poolId ranges]]
:if ($currentRanges != $desiredRangesStr) do={ :error ("VERIFY FAIL: lan-pool ranges do not match production contract: " . $currentRanges) }
:local nextPool [/ip pool get $poolId next-pool]
:if ($nextPool != "" && $nextPool != "none") do={ :error ("VERIFY FAIL: lan-pool has unexpected next-pool=" . $nextPool) }

:local fixedHosts {
    "48:4D:7E:D4:3A:C6=192.168.1.100=PoliceDBC-SEA";
    "00:0C:29:75:A6:D4=192.168.1.123=core.zeaz.dev";
    "00:0C:29:B5:F4:09=192.168.1.122=prod.zeaz.dev";
    "00:0C:29:B7:22:AF=192.168.1.119=ha-a.zeaz.dev";
    "00:0C:29:72:EF:42=192.168.1.120=ha-b.zeaz.dev";
    "88:DC:96:53:0F:55=192.168.1.50=EWS1200D-10T";
    "88:DC:96:55:58:E4=192.168.1.51=RITRUECHAI-AP01";
    "88:DC:96:55:58:E7=192.168.1.52=RITRUECHAI-AP02";
    "88:DC:96:55:58:F0=192.168.1.53=BOONNAK-AP01";
    "88:DC:96:55:58:DE=192.168.1.54=BOONNAK-AP02";
    "88:DC:96:55:58:ED=192.168.1.55=SARASIN-AP02";
    "88:DC:96:55:58:EA=192.168.1.56=SARASIN-AP01";
    "88:DC:96:55:58:F3=192.168.1.57=PANKHONGCHUEN-AP01";
    "88:DC:96:55:58:E1=192.168.1.58=PANKHONGCHUEN-AP02";
    "E4:90:2A:40:61:21=192.168.1.238=ZEAZ Wifi Repeater"
}

:foreach item in=$fixedHosts do={
    :local mac [:pick $item 0 [:find $item "="]]
    :local rest [:pick $item ([:find $item "="] + 1) [:len $item]]
    :local address [:pick $rest 0 [:find $rest "="]]
    :local comment [:pick $rest ([:find $rest "="] + 1) [:len $rest]]
    :local leaseId [/ip dhcp-server lease find where mac-address=$mac]
    :if ([:len $leaseId] != 1) do={ :error ("VERIFY FAIL: lease is not unique for " . $comment) }
    :if ([/ip dhcp-server lease get $leaseId address] != $address) do={ :error ("VERIFY FAIL: reservation mismatch for " . $comment) }
}

:if ([:len [/interface wireguard find where name="wg-remote"]] != 1) do={ :error "VERIFY FAIL: wg-remote is not unique" }
:if ([:len [/ip address find where address="10.8.0.1/24" and interface="wg-remote"]] != 1) do={ :error "VERIFY FAIL: WireGuard gateway address missing" }

:local upstreamReplies [/ping 192.168.200.1 count=3]
:if ($upstreamReplies < 1) do={ :error "VERIFY FAIL: upstream gateway unreachable" }
:local internetReplies [/ping 1.1.1.1 count=3]
:if ($internetReplies < 1) do={ :error "VERIFY FAIL: Internet IP unreachable" }

:do { :local cloudflareIp [:resolve cloudflare.com]; :if ([:len $cloudflareIp] = 0) do={ :error "empty DNS answer" } } on-error={
    :error "VERIFY FAIL: public DNS resolution failed"
}
:do { :local coreIp [:resolve core.zeaz.dev]; :if ($coreIp != "192.168.1.123") do={ :error "wrong core DNS" } } on-error={
    :error "VERIFY FAIL: core.zeaz.dev DNS contract failed"
}
:do { :local prodIp [:resolve prod.zeaz.dev]; :if ($prodIp != "192.168.1.122") do={ :error "wrong prod DNS" } } on-error={
    :error "VERIFY FAIL: prod.zeaz.dev DNS contract failed"
}

/interface bridge port print where bridge="DBC-Bridge-Local"
/interface list member print detail
/ip dhcp-server print detail
/ip dhcp-server lease print detail where mac-address~"88:DC:96"
/interface wireguard peers print detail
/ip firewall filter print stats where comment~"PoliceDBC:"
/ip firewall nat print stats where comment~"PoliceDBC:"
/ip service print
/export terse file=omega-policedbc-after

:put "OMEGA VERIFY PASS"
:log warning "OMEGA VERIFY PASS"
