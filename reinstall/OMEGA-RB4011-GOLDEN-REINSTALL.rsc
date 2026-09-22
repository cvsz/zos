# OMEGA RB4011 GOLDEN REINSTALL CONFIG
# Clean rebuild / disaster-recovery bootstrap only; this script never factory-resets the router.
# Production contract: current cvsz/zos main, single untagged LAN 192.168.1.0/24.
# RouterOS behavior used by the recovery workflow has been verified live on 7.25beta4.
# Run only through a recovery-capable console/MAC-WinBox path, then run the guarded
# production phase stack and 99-VERIFY-HEALTH before declaring production acceptance.

:log warning "OMEGA GOLDEN REINSTALL START"
:put "===== OMEGA GOLDEN PRECHECK ====="

# Clean-rebuild guard: refuse managed/legacy state that could make this bootstrap
# ambiguous or leave a partially-owned production policy behind.
:if ([/ip pool print count-only] > 0) do={ :error "GOLDEN REINSTALL REFUSED: IP pools already exist; reset/clean the target first" }
:if ([/ip dhcp-server print count-only] > 0) do={ :error "GOLDEN REINSTALL REFUSED: DHCP servers already exist; reset/clean the target first" }
:if ([/ip dhcp-server network print count-only] > 0) do={ :error "GOLDEN REINSTALL REFUSED: DHCP networks already exist; reset/clean the target first" }
:if ([/ip dhcp-server lease print count-only] > 0) do={ :error "GOLDEN REINSTALL REFUSED: DHCP leases already exist; reset/clean the target first" }
:if ([/ip address print count-only where address="192.168.0.0/24"] > 0) do={ :error "GOLDEN REINSTALL REFUSED: legacy 192.168.0.0/24 address exists" }
:if ([/interface wireguard print count-only] > 0) do={ :error "GOLDEN REINSTALL REFUSED: WireGuard interfaces already exist; reset/clean the target first" }
:if ([/ip address print count-only where address="10.8.0.1/24"] > 0) do={ :error "GOLDEN REINSTALL REFUSED: WireGuard gateway address already exists" }
:if ([/ip firewall filter print count-only where chain="ZEAZ-PoliceDBC-INPUT"] > 0) do={ :error "GOLDEN REINSTALL REFUSED: managed input firewall chain already exists" }
:if ([/ip firewall filter print count-only where chain="ZEAZ-PoliceDBC-FORWARD"] > 0) do={ :error "GOLDEN REINSTALL REFUSED: managed forward firewall chain already exists" }
:if ([/ip firewall nat print count-only where chain="ZEAZ-PoliceDBC-SRCNAT"] > 0) do={ :error "GOLDEN REINSTALL REFUSED: managed srcnat chain already exists" }
:if ([/ip firewall filter print count-only] > 0) do={ :error "GOLDEN REINSTALL REFUSED: existing firewall filter rules remain; use a clean target" }
:if ([/ip firewall nat print count-only] > 0) do={ :error "GOLDEN REINSTALL REFUSED: existing firewall NAT rules remain; use a clean target" }
:if ([/interface print count-only where name="ether1"] != 1) do={ :error "GOLDEN REINSTALL REFUSED: ether1 is missing or ambiguous" }
:if ([/interface print count-only where name="ether2"] != 1) do={ :error "GOLDEN REINSTALL REFUSED: ether2 is missing or ambiguous" }

# Reject conflicting copies of the production LAN gateway. A correct existing
# recovery address on DBC-Bridge-Local may be retained.
:if ([/ip address print count-only where address="192.168.1.1/24" and interface!="DBC-Bridge-Local"] > 0) do={
    :error "GOLDEN REINSTALL REFUSED: 192.168.1.1/24 exists on another interface"
}

# Managed DNS names must not pre-exist on a clean target because this bootstrap
# creates the authoritative local records below.
:foreach dnsName in={"core.zeaz.dev";"prod.zeaz.dev";"ha-a.zeaz.dev";"ha-b.zeaz.dev";"wifi.zeaz.dev"} do={
    :if ([/ip dns static print count-only where name=$dnsName] > 0) do={
        :error ("GOLDEN REINSTALL REFUSED: managed DNS record already exists: " . $dnsName)
    }
}

:put "GOLDEN PRECHECK PASS"

# Identity and single-LAN bridge contract.
/system identity set name="OMEGA-RB4011"

:if ([/interface bridge print count-only where name="DBC-Bridge-Local"] > 1) do={
    :error "GOLDEN REINSTALL REFUSED: DBC-Bridge-Local is duplicated"
}
:if ([/interface bridge print count-only where name="DBC-Bridge-Local"] = 0) do={
    /interface bridge add name=DBC-Bridge-Local protocol-mode=rstp vlan-filtering=no comment="OMEGA LAN"
} else={
    /interface bridge set [find where name="DBC-Bridge-Local"] protocol-mode=rstp vlan-filtering=no comment="OMEGA LAN"
}

# ether1 is always WAN. Remove any stale bridge membership as part of clean rebuild.
:foreach p in=[/interface bridge port find where interface="ether1"] do={ /interface bridge port remove $p }

# Every physical LAN port must belong only to DBC-Bridge-Local.
:foreach ifn in={"ether2";"ether3";"ether4";"ether5";"ether6";"ether7";"ether8";"ether9";"ether10";"sfp-sfpplus1"} do={
    :if ([/interface print count-only where name=$ifn] > 0) do={
        :if ([/interface bridge port print count-only where interface=$ifn] > 0 && [/interface bridge port print count-only where bridge="DBC-Bridge-Local" and interface=$ifn] = 0) do={
            :error ("GOLDEN REINSTALL REFUSED: " . $ifn . " belongs to another bridge")
        }
        :if ([/interface bridge port print count-only where bridge="DBC-Bridge-Local" and interface=$ifn] = 0) do={
            /interface bridge port add bridge=DBC-Bridge-Local interface=$ifn comment="OMEGA-MANAGED"
        }
    }
}

# Interface-list contract. Dynamic Detect Internet memberships are observational;
# the static memberships below define zOS ownership.
:if ([/interface list print count-only where name="WAN"] = 0) do={ /interface list add name=WAN comment="OMEGA-MANAGED" }
:if ([/interface list print count-only where name="LAN"] = 0) do={ /interface list add name=LAN comment="OMEGA-MANAGED" }
:if ([/interface list print count-only where name="VPN"] = 0) do={ /interface list add name=VPN comment="OMEGA-MANAGED" }
:if ([/interface list member print count-only where list="WAN" and interface="DBC-Bridge-Local" and dynamic=no] > 0) do={ :error "GOLDEN REINSTALL REFUSED: DBC-Bridge-Local is statically in WAN list" }
:if ([/interface list member print count-only where list="LAN" and interface="ether1" and dynamic=no] > 0) do={ :error "GOLDEN REINSTALL REFUSED: ether1 is statically in LAN list" }
:if ([/interface list member print count-only where list="WAN" and interface="ether1" and dynamic=no] = 0) do={ /interface list member add list=WAN interface=ether1 comment="OMEGA-MANAGED" }
:if ([/interface list member print count-only where list="LAN" and interface="DBC-Bridge-Local" and dynamic=no] = 0) do={ /interface list member add list=LAN interface=DBC-Bridge-Local comment="OMEGA-MANAGED" }

# LAN gateway and DHCP WAN.
:if ([/ip address print count-only where address="192.168.1.1/24" and interface="DBC-Bridge-Local"] = 0) do={
    /ip address add address=192.168.1.1/24 interface=DBC-Bridge-Local comment="OMEGA LAN gateway"
}
:if ([/ip dhcp-client print count-only where interface="ether1"] > 1) do={ :error "GOLDEN REINSTALL REFUSED: multiple DHCP clients exist on ether1" }
:if ([/ip dhcp-client print count-only where interface="ether1"] = 0) do={
    /ip dhcp-client add interface=ether1 add-default-route=yes default-route-distance=1 use-peer-dns=yes use-peer-ntp=yes disabled=no comment="OMEGA WAN DHCP"
} else={
    /ip dhcp-client set [find where interface="ether1"] add-default-route=yes default-route-distance=1 use-peer-dns=yes use-peer-ntp=yes disabled=no comment="OMEGA WAN DHCP"
}

# DNS/NTP baseline. Upstream resolvers remain sourced from WAN DHCP.
 /ip dns set allow-remote-requests=yes
 /ip dns static add name=core.zeaz.dev address=192.168.1.123 ttl=1d comment="OMEGA-MANAGED local DNS"
 /ip dns static add name=prod.zeaz.dev address=192.168.1.122 ttl=1d comment="OMEGA-MANAGED local DNS"
 /ip dns static add name=ha-a.zeaz.dev address=192.168.1.119 ttl=1d comment="OMEGA-MANAGED local DNS"
 /ip dns static add name=ha-b.zeaz.dev address=192.168.1.120 ttl=1d comment="OMEGA-MANAGED local DNS"
 /ip dns static add name=wifi.zeaz.dev address=192.168.1.238 ttl=1d comment="OMEGA-MANAGED local DNS"
 /system clock set time-zone-name=Asia/Bangkok
 /system ntp client set enabled=yes

# Production DHCP contract: fixed infrastructure is excluded from the dynamic pool.
 /ip pool add name=lan-pool ranges=192.168.1.59-192.168.1.99,192.168.1.101-192.168.1.118,192.168.1.121,192.168.1.124-192.168.1.237,192.168.1.239-192.168.1.254 comment="OMEGA-MANAGED"
 /ip dhcp-server network add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=192.168.1.1 comment="OMEGA-MANAGED"
 /ip dhcp-server add name=lan-dhcp interface=DBC-Bridge-Local address-pool=lan-pool lease-time=12h authoritative=yes disabled=no comment="OMEGA-MANAGED LAN DHCP"

 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.100 mac-address=48:4D:7E:D4:3A:C6 comment="PoliceDBC-SEA"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.123 mac-address=00:0C:29:75:A6:D4 comment="core.zeaz.dev"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.122 mac-address=00:0C:29:B5:F4:09 comment="prod.zeaz.dev"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.119 mac-address=00:0C:29:B7:22:AF comment="ha-a.zeaz.dev"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.120 mac-address=00:0C:29:72:EF:42 comment="ha-b.zeaz.dev"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.50 mac-address=88:DC:96:53:0F:55 comment="EWS1200D-10T"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.51 mac-address=88:DC:96:55:58:E4 comment="RITRUECHAI-AP01"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.52 mac-address=88:DC:96:55:58:E7 comment="RITRUECHAI-AP02"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.53 mac-address=88:DC:96:55:58:F0 comment="BOONNAK-AP01"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.54 mac-address=88:DC:96:55:58:DE comment="BOONNAK-AP02"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.55 mac-address=88:DC:96:55:58:ED comment="SARASIN-AP02"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.56 mac-address=88:DC:96:55:58:EA comment="SARASIN-AP01"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.57 mac-address=88:DC:96:55:58:F3 comment="PANKHONGCHUEN-AP01"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.58 mac-address=88:DC:96:55:58:E1 comment="PANKHONGCHUEN-AP02"
 /ip dhcp-server lease add server=lan-dhcp address=192.168.1.238 mac-address=E4:90:2A:40:61:21 comment="ZEAZ Wifi Repeater"

# WireGuard rebuild. No secret key material is stored in Git; RouterOS generates
# a new interface key on a clean rebuild. The public key is printed below so CORE
# can be reconciled through the recovery procedure before VPN acceptance.
 /interface wireguard add name=wg-remote listen-port=51820 mtu=1420 comment="PoliceDBC: VPN"
 /ip address add address=10.8.0.1/24 interface=wg-remote comment="PoliceDBC: VPN GATEWAY"
 /interface list member add list=VPN interface=wg-remote comment="OMEGA-MANAGED"
 /interface wireguard peers add interface=wg-remote public-key="HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8=" allowed-address=10.8.0.2/32 comment="core.zeaz.dev"
:put ("OMEGA WG ROUTER PUBLIC KEY=" . [/interface wireguard get 0 public-key])

# Managed firewall policy. Clean-target firewall/NAT emptiness was proven in
# preflight so unrelated rules cannot silently widen policy after chain return.
 /ip firewall filter add chain=input action=jump jump-target=ZEAZ-PoliceDBC-INPUT place-before=0 comment="ZEAZ-PoliceDBC: INPUT POLICY"
 /ip firewall filter add chain=forward action=jump jump-target=ZEAZ-PoliceDBC-FORWARD place-before=0 comment="ZEAZ-PoliceDBC: FORWARD POLICY"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-INPUT action=accept connection-state=established,related,untracked comment="PoliceDBC: INPUT Established Related"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-INPUT action=drop connection-state=invalid comment="PoliceDBC: INPUT Invalid Drop"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-INPUT action=accept protocol=icmp comment="PoliceDBC: INPUT ICMP"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-INPUT action=accept protocol=udp in-interface-list=WAN dst-port=51820 comment="PoliceDBC: INPUT WireGuard WAN"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-INPUT action=accept in-interface-list=LAN comment="PoliceDBC: INPUT LAN Management"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-INPUT action=accept in-interface-list=VPN comment="PoliceDBC: INPUT VPN Management"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-INPUT action=drop comment="PoliceDBC: INPUT DEFAULT DENY"

 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=fasttrack-connection connection-state=established,related comment="PoliceDBC: FORWARD FastTrack"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=accept connection-state=established,related,untracked comment="PoliceDBC: FORWARD Established Related"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=drop connection-state=invalid comment="PoliceDBC: FORWARD Invalid Drop"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=192.168.1.0/24 in-interface-list=LAN out-interface-list=WAN comment="PoliceDBC: FORWARD LAN to WAN"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=10.8.0.0/24 in-interface-list=VPN out-interface-list=WAN comment="PoliceDBC: FORWARD VPN to WAN"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=10.8.0.0/24 dst-address=192.168.1.0/24 in-interface-list=VPN out-interface-list=LAN comment="PoliceDBC: FORWARD VPN to LAN"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=192.168.1.0/24 dst-address=10.8.0.0/24 in-interface-list=LAN out-interface-list=VPN comment="PoliceDBC: FORWARD LAN to VPN"
 /ip firewall filter add chain=ZEAZ-PoliceDBC-FORWARD action=drop comment="PoliceDBC: FORWARD DEFAULT DENY"

 /ip firewall nat add chain=srcnat action=jump jump-target=ZEAZ-PoliceDBC-SRCNAT place-before=0 comment="ZEAZ-PoliceDBC: SRCNAT POLICY"
 /ip firewall nat add chain=ZEAZ-PoliceDBC-SRCNAT action=masquerade src-address=192.168.1.0/24 out-interface-list=WAN comment="PoliceDBC: NAT LAN to WAN"
 /ip firewall nat add chain=ZEAZ-PoliceDBC-SRCNAT action=masquerade src-address=10.8.0.0/24 out-interface-list=WAN comment="PoliceDBC: NAT VPN to WAN"

# Service hardening mirrors the current production phase contract.
 /ip service set telnet disabled=yes
 /ip service set ftp disabled=yes
 /ip service set www disabled=yes
 /ip service set www-ssl disabled=yes
 /ip service set api disabled=yes
 /ip service set api-ssl disabled=yes
 /ip service set ssh disabled=no port=22
 /ip service set winbox disabled=no port=8291
:if ([/ip service print count-only where name="reverse-proxy"] > 0) do={ /ip service set reverse-proxy disabled=yes }
 /ip ssh set strong-crypto=yes
 /tool bandwidth-server set enabled=no
 /ip proxy set enabled=no
 /ip socks set enabled=no
 /ip upnp set enabled=no
 /ip neighbor discovery-settings set discover-interface-list=LAN
 /tool mac-server set allowed-interface-list=none
 /tool mac-server mac-winbox set allowed-interface-list=LAN
 /tool mac-server ping set enabled=no

# Local observability baseline. Remote syslog is intentionally not invented.
:if ([/system logging print count-only where topics="firewall" and action="memory"] = 0) do={ /system logging add topics=firewall action=memory comment="OMEGA-MANAGED" }
:if ([/system logging print count-only where topics="wireguard" and action="memory"] = 0) do={ /system logging add topics=wireguard action=memory comment="OMEGA-MANAGED" }
:if ([/system logging print count-only where topics="critical" and action="memory"] = 0) do={ /system logging add topics=critical action=memory comment="OMEGA-MANAGED" }

:delay 5s
:put "===== OMEGA GOLDEN VERIFY ====="

# Network and legacy-state assertions.
:if ([/interface bridge print count-only where name="DBC-Bridge-Local" and vlan-filtering=no] != 1) do={ :error "GOLDEN VERIFY FAIL: single-LAN bridge contract failed" }
:if ([/interface bridge port print count-only where interface="ether1"] > 0) do={ :error "GOLDEN VERIFY FAIL: ether1 is still bridged" }
:if ([/ip address print count-only where address="192.168.1.1/24" and interface="DBC-Bridge-Local"] != 1) do={ :error "GOLDEN VERIFY FAIL: LAN gateway contract failed" }
:if ([/ip dhcp-client print count-only where interface="ether1" and status="bound"] != 1) do={ :error "GOLDEN VERIFY FAIL: ether1 DHCP WAN is not uniquely bound" }
:if ([/ip dhcp-server print count-only where interface="ether1" and disabled=no] > 0) do={ :error "GOLDEN VERIFY FAIL: DHCP server exists on WAN ether1" }
:if ([/ip address print count-only where address="192.168.0.0/24"] > 0) do={ :error "GOLDEN VERIFY FAIL: legacy 192.168.0.0/24 address remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.0.0/24"] > 0) do={ :error "GOLDEN VERIFY FAIL: legacy 192.168.0.0/24 DHCP network remains" }
:if ([/ip dhcp-server network print count-only where address="192.168.10.0/24"] > 0) do={ :error "GOLDEN VERIFY FAIL: legacy 192.168.10.0/24 DHCP network remains" }

# DHCP/DNS/NTP assertions.
:local desiredRangesStr "192.168.1.59-192.168.1.99;192.168.1.101-192.168.1.118;192.168.1.121;192.168.1.124-192.168.1.237;192.168.1.239-192.168.1.254"
:if ([/ip pool print count-only where name="lan-pool"] != 1) do={ :error "GOLDEN VERIFY FAIL: lan-pool is not unique" }
:if ([:tostr [/ip pool get 0 ranges]] != $desiredRangesStr) do={ :error ("GOLDEN VERIFY FAIL: lan-pool ranges mismatch: " . [:tostr [/ip pool get 0 ranges]]) }
:local goldenNextPool [:tostr [/ip pool get 0 next-pool]]
:if ($goldenNextPool != "" && $goldenNextPool != "none") do={ :error ("GOLDEN VERIFY FAIL: lan-pool next-pool=" . $goldenNextPool) }
:if ([/ip dhcp-server print count-only where name="lan-dhcp" and interface="DBC-Bridge-Local" and address-pool="lan-pool" and disabled=no] != 1) do={ :error "GOLDEN VERIFY FAIL: lan-dhcp contract failed" }
:if ([/ip dhcp-server network print count-only where address="192.168.1.0/24" and gateway="192.168.1.1" and dns-server="192.168.1.1"] != 1) do={ :error "GOLDEN VERIFY FAIL: LAN DHCP network contract failed" }
:if ([/ip dns get allow-remote-requests] != true) do={ :error "GOLDEN VERIFY FAIL: RouterOS DNS cache is disabled" }
:if ([/system ntp client get enabled] != true) do={ :error "GOLDEN VERIFY FAIL: NTP client is disabled" }
:if ([/system clock get time-zone-name] != "Asia/Bangkok") do={ :error "GOLDEN VERIFY FAIL: timezone is not Asia/Bangkok" }

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
    :if ([/ip dhcp-server lease print count-only where mac-address=$mac and address=$address and dynamic=no] != 1) do={
        :error ("GOLDEN VERIFY FAIL: fixed DHCP reservation mismatch for " . $comment)
    }
}

:local dnsRecords {
    "core.zeaz.dev=192.168.1.123";
    "prod.zeaz.dev=192.168.1.122";
    "ha-a.zeaz.dev=192.168.1.119";
    "ha-b.zeaz.dev=192.168.1.120";
    "wifi.zeaz.dev=192.168.1.238"
}
:foreach item in=$dnsRecords do={
    :local name [:pick $item 0 [:find $item "="]]
    :local address [:pick $item ([:find $item "="] + 1) [:len $item]]
    :if ([/ip dns static print count-only where name=$name and address=$address] != 1) do={
        :error ("GOLDEN VERIFY FAIL: static DNS mismatch for " . $name)
    }
}

# WireGuard and policy assertions.
:if ([/interface wireguard print count-only where name="wg-remote" and listen-port=51820 and mtu=1420] != 1) do={ :error "GOLDEN VERIFY FAIL: wg-remote contract failed" }
:if ([/ip address print count-only where address="10.8.0.1/24" and interface="wg-remote"] != 1) do={ :error "GOLDEN VERIFY FAIL: WireGuard gateway address missing" }
:if ([/interface list member print count-only where list="VPN" and interface="wg-remote"] != 1) do={ :error "GOLDEN VERIFY FAIL: wg-remote VPN-list membership missing" }
:if ([/interface wireguard peers print count-only where interface="wg-remote" and public-key="HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8=" and allowed-address="10.8.0.2/32"] != 1) do={ :error "GOLDEN VERIFY FAIL: CORE WireGuard peer contract failed" }

:if ([/ip firewall filter print count-only where chain="input" and jump-target="ZEAZ-PoliceDBC-INPUT" and comment="ZEAZ-PoliceDBC: INPUT POLICY" and disabled=no] != 1) do={ :error "GOLDEN VERIFY FAIL: input policy jump missing" }
:if ([/ip firewall filter print count-only where chain="forward" and jump-target="ZEAZ-PoliceDBC-FORWARD" and comment="ZEAZ-PoliceDBC: FORWARD POLICY" and disabled=no] != 1) do={ :error "GOLDEN VERIFY FAIL: forward policy jump missing" }
:if ([/ip firewall filter print count-only where chain="ZEAZ-PoliceDBC-INPUT" and comment="PoliceDBC: INPUT DEFAULT DENY" and disabled=no] != 1) do={ :error "GOLDEN VERIFY FAIL: input default deny missing" }
:if ([/ip firewall filter print count-only where chain="ZEAZ-PoliceDBC-FORWARD" and comment="PoliceDBC: FORWARD DEFAULT DENY" and disabled=no] != 1) do={ :error "GOLDEN VERIFY FAIL: forward default deny missing" }
:if ([/ip firewall nat print count-only where chain="srcnat" and jump-target="ZEAZ-PoliceDBC-SRCNAT" and comment="ZEAZ-PoliceDBC: SRCNAT POLICY" and disabled=no] != 1) do={ :error "GOLDEN VERIFY FAIL: srcnat policy jump missing" }
:if ([/ip firewall nat print count-only where chain="ZEAZ-PoliceDBC-SRCNAT" and src-address="192.168.1.0/24" and out-interface-list="WAN" and comment="PoliceDBC: NAT LAN to WAN" and disabled=no] != 1) do={ :error "GOLDEN VERIFY FAIL: LAN NAT contract missing" }

# Management/service assertions.
:if ([/ip service print count-only where name="telnet" and disabled=no] > 0) do={ :error "GOLDEN VERIFY FAIL: telnet is enabled" }
:if ([/ip service print count-only where name="ftp" and disabled=no] > 0) do={ :error "GOLDEN VERIFY FAIL: ftp is enabled" }
:if ([/ip service print count-only where name="www" and disabled=no] > 0) do={ :error "GOLDEN VERIFY FAIL: www is enabled" }
:if ([/ip service print count-only where name="www-ssl" and disabled=no] > 0) do={ :error "GOLDEN VERIFY FAIL: www-ssl is enabled" }
:if ([/ip service print count-only where name="api" and disabled=no] > 0) do={ :error "GOLDEN VERIFY FAIL: api is enabled" }
:if ([/ip service print count-only where name="api-ssl" and disabled=no] > 0) do={ :error "GOLDEN VERIFY FAIL: api-ssl is enabled" }
:if ([/ip service print count-only where name="ssh" and disabled=no and port=22] != 1) do={ :error "GOLDEN VERIFY FAIL: SSH management service contract failed" }
:if ([/ip service print count-only where name="winbox" and disabled=no and port=8291] != 1) do={ :error "GOLDEN VERIFY FAIL: WinBox management service contract failed" }

# WAN/DNS runtime acceptance. The upstream gateway is the verified current
# PoliceDBC contract; the WAN lease itself remains dynamic and is not hard-coded.
:if ([/ip route print count-only where dst-address="0.0.0.0/0" and gateway="192.168.200.1"] = 0) do={ :error "GOLDEN VERIFY FAIL: expected upstream default route missing" }
:local upstreamReplies [/ping 192.168.200.1 count=3]
:if ($upstreamReplies < 1) do={ :error "GOLDEN VERIFY FAIL: upstream gateway unreachable" }
:local internetReplies [/ping 1.1.1.1 count=3]
:if ($internetReplies < 1) do={ :error "GOLDEN VERIFY FAIL: Internet unreachable" }
:do { :local cloudflareIp [:resolve cloudflare.com]; :if ([:len $cloudflareIp] = 0) do={ :error "empty DNS answer" } } on-error={
    :error "GOLDEN VERIFY FAIL: public DNS resolution failed"
}
:do { :local coreIp [:resolve core.zeaz.dev]; :if ($coreIp != "192.168.1.123") do={ :error "wrong core DNS" } } on-error={
    :error "GOLDEN VERIFY FAIL: core.zeaz.dev DNS contract failed"
}
:do { :local prodIp [:resolve prod.zeaz.dev]; :if ($prodIp != "192.168.1.122") do={ :error "wrong prod DNS" } } on-error={
    :error "GOLDEN VERIFY FAIL: prod.zeaz.dev DNS contract failed"
}

# Recovery evidence.
/system resource print
/interface bridge port print where bridge="DBC-Bridge-Local"
/interface list member print detail
/ip address print detail
/ip dhcp-client print detail
/ip dhcp-server print detail
/ip dhcp-server network print detail
/ip dhcp-server lease print detail
/interface wireguard print detail
/interface wireguard peers print detail
/ip firewall filter print stats where comment~"PoliceDBC:"
/ip firewall nat print stats where comment~"PoliceDBC:"
/ip service print
/export terse file=OMEGA-RB4011-AFTER-REINSTALL

:put "OMEGA GOLDEN REINSTALL VERIFY PASS"
:log warning "OMEGA GOLDEN REINSTALL COMPLETE"
:put "OMEGA GOLDEN REINSTALL COMPLETE"
