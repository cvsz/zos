:log warning "OMEGA NETWORK NORMALIZE START"

:if ([:len [/interface bridge find where name="DBC-Bridge-Local"]] = 0) do={
    :error "NETWORK NORMALIZE FAIL: DBC-Bridge-Local missing"
}

# LAN ports may be added only when they are not already owned by another bridge.
:foreach p in={"ether2";"ether3";"ether4";"ether5";"ether6";"ether7";"ether8";"ether9";"ether10";"sfp-sfpplus1"} do={
    :if ([:len [/interface find where name=$p]] > 0) do={
        :if ([:len [/interface bridge port find where bridge="DBC-Bridge-Local" and interface=$p]] = 0) do={
            :if ([:len [/interface bridge port find where interface=$p]] > 0) do={
                :error ("interface " . $p . " already belongs to another bridge; refusing takeover")
            }
            /interface bridge port add bridge=DBC-Bridge-Local interface=$p comment="OMEGA-MANAGED"
        }
    }
}

# In the verified production topology ether1 is already isolated as WAN.
# Active normalization never removes an unowned bridge membership implicitly.
:if ([:len [/interface bridge port find where interface="ether1"]] > 0) do={
    :error "ether1 is attached to a bridge; refusing implicit WAN/LAN topology takeover"
}

# The LAN gateway must either already be correct or be absent.
:if ([:len [/ip address find where address="192.168.1.1/24" and interface="DBC-Bridge-Local"]] = 0) do={
    :if ([:len [/ip address find where address="192.168.1.1/24"]] > 0) do={
        :error "192.168.1.1/24 exists on another interface; refusing takeover"
    }
    /ip address add address=192.168.1.1/24 interface=DBC-Bridge-Local comment="OMEGA-MANAGED LAN gateway"
}

# WAN DHCP is required on ether1. Other DHCP clients are not deleted here.
:if ([:len [/ip dhcp-client find where interface="ether1"]] = 0) do={
    /ip dhcp-client add interface=ether1 add-default-route=yes default-route-distance=1 use-peer-dns=yes use-peer-ntp=yes disabled=no comment="OMEGA-MANAGED WAN DHCP"
} else={
    :local wanClient [/ip dhcp-client find where interface="ether1"]
    :if ([/ip dhcp-client get $wanClient disabled] = true) do={
        :error "ether1 DHCP client exists but is disabled; refusing implicit rewrite"
    }
}

/interface list
:if ([:len [find where name="WAN"]] = 0) do={ add name=WAN comment="OMEGA-MANAGED" }
:if ([:len [find where name="LAN"]] = 0) do={ add name=LAN comment="OMEGA-MANAGED" }
:if ([:len [find where name="VPN"]] = 0) do={ add name=VPN comment="OMEGA-MANAGED" }

/interface list member
:if ([:len [find where list="WAN" and interface="DBC-Bridge-Local"]] > 0) do={
    :error "DBC-Bridge-Local is unexpectedly in WAN list; refusing implicit removal"
}
:if ([:len [find where list="LAN" and interface="ether1"]] > 0) do={
    :error "ether1 is unexpectedly in LAN list; refusing implicit removal"
}
:if ([:len [find where list="WAN" and interface="ether1"]] = 0) do={ add list=WAN interface=ether1 comment="OMEGA-MANAGED" }
:if ([:len [find where list="LAN" and interface="DBC-Bridge-Local"]] = 0) do={ add list=LAN interface=DBC-Bridge-Local comment="OMEGA-MANAGED" }
:if ([:len [/interface wireguard find where name="wg-remote"]] > 0) do={
    :if ([:len [find where list="VPN" and interface="wg-remote"]] = 0) do={ add list=VPN interface=wg-remote comment="OMEGA-MANAGED" }
}

:put "NETWORK NORMALIZE PASS"
:log warning "OMEGA NETWORK NORMALIZE PASS"
