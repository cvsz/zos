:log warning "OMEGA DHCP DNS NTP START"

# zOS owns only the verified LAN DHCP/DNS contract below. Conflicting live
# objects are preserved and cause this phase to fail rather than being rewritten.
# Fixed infrastructure is excluded from the dynamic pool to prevent duplicate IPs.
# Existing unowned DHCP servers and upstream DNS resolver state are preserved.

:local desiredRanges "192.168.1.50-192.168.1.99,192.168.1.109-192.168.1.118,192.168.1.121-192.168.1.237,192.168.1.240-192.168.1.254"
:if ([:len [/ip pool find where name="lan-pool"]] = 0) do={
    /ip pool add name=lan-pool ranges=$desiredRanges comment="OMEGA-MANAGED"
} else={
    :local poolId [/ip pool find where name="lan-pool"]
    :if ([/ip pool get $poolId ranges] != $desiredRanges) do={
        :error "lan-pool exists with ranges outside the verified contract; refusing takeover"
    }
}

# Do not delete unrelated DHCP servers. zOS creates/manages only lan-dhcp.
:if ([:len [/ip dhcp-server find where name="lan-dhcp"]] = 0) do={
    /ip dhcp-server add name=lan-dhcp interface=DBC-Bridge-Local address-pool=lan-pool lease-time=12h authoritative=yes disabled=no comment="OMEGA-MANAGED LAN DHCP"
} else={
    :local dhcpId [/ip dhcp-server find where name="lan-dhcp"]
    :if ([/ip dhcp-server get $dhcpId interface] != "DBC-Bridge-Local") do={ :error "lan-dhcp exists on another interface; refusing takeover" }
    :if ([/ip dhcp-server get $dhcpId address-pool] != "lan-pool") do={ :error "lan-dhcp uses another pool; refusing takeover" }
    :if ([/ip dhcp-server get $dhcpId disabled] = true) do={ :error "lan-dhcp exists but is disabled; refusing implicit enable" }
}

:if ([:len [/ip dhcp-server network find where address="192.168.1.0/24"]] = 0) do={
    /ip dhcp-server network add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=192.168.1.1 comment="OMEGA-MANAGED"
} else={
    :local netId [/ip dhcp-server network find where address="192.168.1.0/24"]
    :if ([/ip dhcp-server network get $netId gateway] != "192.168.1.1") do={ :error "LAN DHCP gateway differs from contract; refusing takeover" }
    :if ([/ip dhcp-server network get $netId dns-server] != "192.168.1.1") do={ :error "LAN DHCP DNS differs from contract; refusing takeover" }
}

# Every fixed lease below is an observed MAC/IP pair supplied as verified inventory.
:local leaseId
:local fixedHosts {
    "48:4D:7E:D4:3A:C6=192.168.1.100=PoliceDBC-SEA";
    "00:0C:29:75:A6:D4=192.168.1.123=core.zeaz.dev";
    "00:0C:29:B5:F4:09=192.168.1.122=prod.zeaz.dev";
    "00:0C:29:B7:22:AF=192.168.1.119=ha-a.zeaz.dev";
    "00:0C:29:72:EF:42=192.168.1.120=ha-b.zeaz.dev";
    "88:DC:96:55:58:E4=192.168.1.101=RITRUECHAI-AP01";
    "88:DC:96:55:58:E7=192.168.1.102=RITRUECHAI-AP02";
    "88:DC:96:55:58:F0=192.168.1.103=BOONNAK-AP01";
    "88:DC:96:55:58:DE=192.168.1.104=BOONNAK-AP02";
    "88:DC:96:55:58:ED=192.168.1.105=SARASIN-AP02";
    "88:DC:96:55:58:EA=192.168.1.106=SARASIN-AP01";
    "88:DC:96:55:58:F3=192.168.1.107=PANKHONGCHUEN-AP01";
    "88:DC:96:55:58:E1=192.168.1.108=PANKHONGCHUEN-AP02";
    "E4:90:2A:40:61:21=192.168.1.238=ZEAZ Wifi Repeater";
    "88:DC:96:53:0F:55=192.168.1.239=EWS1200D-10T"
}

:foreach item in=$fixedHosts do={
    :local mac [:pick $item 0 [:find $item "="]]
    :local rest [:pick $item ([:find $item "="] + 1) [:len $item]]
    :local address [:pick $rest 0 [:find $rest "="]]
    :local comment [:pick $rest ([:find $rest "="] + 1) [:len $rest]]

    :set leaseId [/ip dhcp-server lease find where mac-address=$mac]
    :if ([:len $leaseId] = 0) do={
        :if ([:len [/ip dhcp-server lease find where address=$address]] > 0) do={
            :error ("" . $address . " is occupied by another DHCP lease; refusing to take over for " . $comment)
        }
        /ip dhcp-server lease add server=lan-dhcp address=$address mac-address=$mac comment=$comment
    } else={
        :if ([/ip dhcp-server lease get $leaseId address] != $address) do={
            :error ("MAC " . $mac . " has a different lease; refusing rewrite for " . $comment)
        }
        /ip dhcp-server lease make-static $leaseId
        /ip dhcp-server lease set $leaseId server=lan-dhcp comment=$comment
    }
}

# Preserve the existing global upstream DNS resolver configuration. Only enable
# local recursive requests when the existing policy already permits local DNS.
:local dnsBefore [/ip dns get allow-remote-requests]
:if ($dnsBefore = true) do={
    /ip dns set allow-remote-requests=yes
} else={
    :log info "OMEGA: preserving upstream DNS allow-remote-requests=no"
}

:local dnsId
:set dnsId [/ip dns static find where name="core.zeaz.dev"]
:if ([:len $dnsId] = 0) do={ /ip dns static add name=core.zeaz.dev address=192.168.1.123 ttl=1d comment="OMEGA-MANAGED zeaz core" } else={ :if ([/ip dns static get $dnsId address] != "192.168.1.123") do={ :error "core.zeaz.dev DNS conflicts with verified address" } }
:set dnsId [/ip dns static find where name="prod.zeaz.dev"]
:if ([:len $dnsId] = 0) do={ /ip dns static add name=prod.zeaz.dev address=192.168.1.122 ttl=1d comment="OMEGA-MANAGED zeaz prod" } else={ :if ([/ip dns static get $dnsId address] != "192.168.1.122") do={ :error "prod.zeaz.dev DNS conflicts with verified address" } }
:set dnsId [/ip dns static find where name="ha-a.zeaz.dev"]
:if ([:len $dnsId] = 0) do={ /ip dns static add name=ha-a.zeaz.dev address=192.168.1.119 ttl=1d comment="OMEGA-MANAGED zeaz ha-a" } else={ :if ([/ip dns static get $dnsId address] != "192.168.1.119") do={ :error "ha-a.zeaz.dev DNS conflicts with verified address" } }
:set dnsId [/ip dns static find where name="ha-b.zeaz.dev"]
:if ([:len $dnsId] = 0) do={ /ip dns static add name=ha-b.zeaz.dev address=192.168.1.120 ttl=1d comment="OMEGA-MANAGED zeaz ha-b" } else={ :if ([/ip dns static get $dnsId address] != "192.168.1.120") do={ :error "ha-b.zeaz.dev DNS conflicts with verified address" } }
:set dnsId [/ip dns static find where name="wifi.zeaz.dev"]
:if ([:len $dnsId] = 0) do={ /ip dns static add name=wifi.zeaz.dev address=192.168.1.238 ttl=1d comment="OMEGA-MANAGED ZeaZ WiFi repeater" } else={ :if ([/ip dns static get $dnsId address] != "192.168.1.238") do={ :error "wifi.zeaz.dev DNS conflicts with verified address" } }

/system clock set time-zone-name=Asia/Bangkok
/system ntp client set enabled=yes
:put "DHCP DNS NTP PASS"
:log warning "OMEGA DHCP DNS NTP PASS"
