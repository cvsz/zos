:log warning "OMEGA VERIFY START"
:put "===== OMEGA VERIFY ====="
/system resource print
/ip address print detail
/interface bridge port print where bridge="DBC-Bridge-Local"
/interface list member print detail
/ip dhcp-client print detail where interface="ether1"
/ip dhcp-server print detail
/ip dhcp-server lease print detail where mac-address="48:4D:7E:D4:3A:C6"
/ip dhcp-server lease print detail where mac-address="00:0C:29:B7:22:AF"
/ip dhcp-server lease print detail where mac-address="00:0C:29:72:EF:42"
/ip dhcp-server lease print detail where mac-address="00:0C:29:B5:F4:09"
/ip dns static print detail where name="prod.zeaz.dev"
/ip dns static print detail where name="core.zeaz.dev"
/ip dns static print detail where name="ha-a.zeaz.dev"
/ip dns static print detail where name="ha-b.zeaz.dev"
/interface wireguard print detail
/interface wireguard peers print detail
/ip service print
/ip route print where dst-address="0.0.0.0/0"
:put "PING UPSTREAM"
/ping 192.168.200.1 count=3
:put "PING INTERNET"
/ping 1.1.1.1 count=3
:put "DNS"
:put [/resolve cloudflare.com]
:put [/resolve prod.zeaz.dev]
:put [/resolve core.zeaz.dev]
:put [/resolve ha-a.zeaz.dev]
:put [/resolve ha-b.zeaz.dev]
/export terse file=omega-policedbc-after
:put "VERIFY COMPLETE - inspect fixed-host reachability and WireGuard handshake before exiting Safe Mode"
:log warning "OMEGA VERIFY COMPLETE"
