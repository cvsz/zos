# OMEGA RB4011 GOLDEN REINSTALL CONFIG
# RouterOS 7.24.x / MikroTik RB4011iGS+
# Verified topology: ether1 DHCP WAN, DBC-Bridge-Local LAN 192.168.1.1/24.
# Use only for clean rebuild/recovery; this script does not reset the router itself.

:log warning "OMEGA GOLDEN REINSTALL START"
/system identity set name="OMEGA-RB4011"

:if ([:len [/interface bridge find where name="DBC-Bridge-Local"]] = 0) do={ /interface bridge add name=DBC-Bridge-Local protocol-mode=rstp comment="OMEGA LAN" }
:foreach p in=[/interface bridge port find where interface="ether1"] do={ /interface bridge port remove $p }
:foreach ifn in={"ether2";"ether3";"ether4";"ether5";"ether6";"ether7";"ether8";"ether9";"ether10";"sfp-sfpplus1"} do={
    :if ([:len [/interface find where name=$ifn]] > 0 && [:len [/interface bridge port find where interface=$ifn]] = 0) do={ /interface bridge port add bridge=DBC-Bridge-Local interface=$ifn }
}

:if ([:len [/interface list find where name="WAN"]] = 0) do={ /interface list add name=WAN }
:if ([:len [/interface list find where name="LAN"]] = 0) do={ /interface list add name=LAN }
:if ([:len [/interface list member find where list="WAN" and interface="ether1"]] = 0) do={ /interface list member add list=WAN interface=ether1 }
:if ([:len [/interface list member find where list="LAN" and interface="DBC-Bridge-Local"]] = 0) do={ /interface list member add list=LAN interface=DBC-Bridge-Local }

:if ([:len [/ip address find where address="192.168.1.1/24" and interface="DBC-Bridge-Local"]] = 0) do={ /ip address add address=192.168.1.1/24 interface=DBC-Bridge-Local comment="OMEGA LAN gateway" }
:if ([:len [/ip dhcp-client find where interface="ether1"]] = 0) do={ /ip dhcp-client add interface=ether1 add-default-route=yes default-route-distance=1 use-peer-dns=yes use-peer-ntp=yes disabled=no comment="OMEGA WAN DHCP" }

# Clean-rebuild source of truth for local names. Upstream resolver settings are
# inherited from the WAN DHCP client and are not replaced by hard-coded servers.
/ip dns set allow-remote-requests=yes
/ip dns static
add name=core.zeaz.dev address=192.168.1.123 ttl=1d comment="OMEGA core"
add name=prod.zeaz.dev address=192.168.1.122 ttl=1d comment="OMEGA prod"
add name=ha-a.zeaz.dev address=192.168.1.119 ttl=1d comment="OMEGA ha-a"
add name=ha-b.zeaz.dev address=192.168.1.120 ttl=1d comment="OMEGA ha-b"
add name=wifi.zeaz.dev address=192.168.1.238 ttl=1d comment="OMEGA ZeaZ WiFi repeater"

/ip pool add name=lan-pool ranges=192.168.1.59-192.168.1.99,192.168.1.101-192.168.1.118,192.168.1.121-192.168.1.121,192.168.1.124-192.168.1.237,192.168.1.239-192.168.1.254
/ip dhcp-server network add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=192.168.1.1 comment="OMEGA LAN"
/ip dhcp-server add name=lan-dhcp interface=DBC-Bridge-Local address-pool=lan-pool lease-time=12h authoritative=yes disabled=no
/ip dhcp-server lease
add server=lan-dhcp address=192.168.1.100 mac-address=48:4D:7E:D4:3A:C6 comment="PoliceDBC-SEA"
add server=lan-dhcp address=192.168.1.123 mac-address=00:0C:29:75:A6:D4 comment="core.zeaz.dev"
add server=lan-dhcp address=192.168.1.122 mac-address=00:0C:29:B5:F4:09 comment="prod.zeaz.dev"
add server=lan-dhcp address=192.168.1.50 mac-address=88:DC:96:53:0F:55 comment="EWS1200D-10T"
add server=lan-dhcp address=192.168.1.51 mac-address=88:DC:96:55:58:E4 comment="RITRUECHAI-AP01"
add server=lan-dhcp address=192.168.1.52 mac-address=88:DC:96:55:58:E7 comment="RITRUECHAI-AP02"
add server=lan-dhcp address=192.168.1.53 mac-address=88:DC:96:55:58:F0 comment="BOONNAK-AP01"
add server=lan-dhcp address=192.168.1.54 mac-address=88:DC:96:55:58:DE comment="BOONNAK-AP02"
add server=lan-dhcp address=192.168.1.55 mac-address=88:DC:96:55:58:ED comment="SARASIN-AP02"
add server=lan-dhcp address=192.168.1.56 mac-address=88:DC:96:55:58:EA comment="SARASIN-AP01"
add server=lan-dhcp address=192.168.1.57 mac-address=88:DC:96:55:58:F3 comment="PANKHONGCHUEN-AP01"
add server=lan-dhcp address=192.168.1.58 mac-address=88:DC:96:55:58:E1 comment="PANKHONGCHUEN-AP02"
add server=lan-dhcp address=192.168.1.119 mac-address=00:0C:29:B7:22:AF comment="ha-a.zeaz.dev"
add server=lan-dhcp address=192.168.1.120 mac-address=00:0C:29:72:EF:42 comment="ha-b.zeaz.dev"
add server=lan-dhcp address=192.168.1.238 mac-address=E4:90:2A:40:61:21 comment="ZEAZ Wifi Repeater"

/ip firewall nat add chain=srcnat action=masquerade src-address=192.168.1.0/24 out-interface-list=WAN comment="OMEGA LAN to WAN"
/ip firewall filter
add chain=input action=accept connection-state=established,related,untracked comment="OMEGA-FW input established"
add chain=input action=drop connection-state=invalid comment="OMEGA-FW input invalid"
add chain=input action=accept protocol=icmp comment="OMEGA-FW input ICMP"
add chain=input action=accept in-interface-list=LAN src-address=192.168.1.0/24 comment="OMEGA-FW LAN manage router"
add chain=input action=accept protocol=udp dst-port=67,68 in-interface=ether1 comment="OMEGA-FW WAN DHCP client"
add chain=input action=drop in-interface-list=WAN comment="OMEGA-FW drop WAN to router"
add chain=forward action=accept connection-state=established,related,untracked comment="OMEGA-FW forward established"
add chain=forward action=drop connection-state=invalid comment="OMEGA-FW forward invalid"
add chain=forward action=accept in-interface-list=LAN out-interface-list=WAN src-address=192.168.1.0/24 comment="OMEGA-FW LAN to WAN"
add chain=forward action=accept in-interface-list=LAN out-interface-list=LAN src-address=192.168.1.0/24 dst-address=192.168.1.0/24 comment="OMEGA-FW LAN east-west"
add chain=forward action=drop in-interface-list=WAN connection-state=new connection-nat-state=!dstnat comment="OMEGA-FW drop unsolicited WAN"

/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh disabled=no address=192.168.1.0/24
/ip service set winbox disabled=no address=192.168.1.0/24
/ip neighbor discovery-settings set discover-interface-list=LAN
/tool mac-server set allowed-interface-list=LAN
/tool mac-server mac-winbox set allowed-interface-list=LAN

:delay 3s
:put "===== OMEGA VERIFY ====="
/interface bridge port print where bridge="DBC-Bridge-Local"
/interface list member print detail
/ip address print detail
/ip dhcp-client print detail
/ip dhcp-server lease print detail
/ip route print detail
/ip firewall nat print detail
:do { /ping 192.168.200.1 count=3 } on-error={ :log warning "OMEGA: upstream gateway ping failed" }
:do { /ping 1.1.1.1 count=3 } on-error={ :log warning "OMEGA: Internet ping failed" }
/export file=OMEGA-RB4011-AFTER-REINSTALL
:log warning "OMEGA GOLDEN REINSTALL COMPLETE"
:put "OMEGA GOLDEN REINSTALL COMPLETE"
