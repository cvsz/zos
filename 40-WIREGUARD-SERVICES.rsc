:log warning "OMEGA WIREGUARD SERVICES START"

:local wgIds [/interface wireguard find where name="wg-remote"]
:if ([:len $wgIds] > 1) do={ :error "wg-remote is duplicated; refusing ambiguous rewrite" }
:if ([:len $wgIds] = 0) do={
    /interface wireguard add name=wg-remote listen-port=51820 mtu=1420 comment="PoliceDBC: VPN"
} else={
    :local wgId $wgIds
    :local wgComment [/interface wireguard get $wgId comment]
    :if ($wgComment != "PoliceDBC: VPN") do={
        :error "wg-remote exists without expected zOS ownership comment; refusing takeover"
    }
    /interface wireguard set $wgId listen-port=51820 mtu=1420
}

:local wgAddressIds [/ip address find where address="10.8.0.1/24"]
:if ([:len $wgAddressIds] > 1) do={ :error "10.8.0.1/24 is duplicated; refusing ambiguous rewrite" }
:if ([:len $wgAddressIds] = 0) do={
    /ip address add address=10.8.0.1/24 interface=wg-remote comment="PoliceDBC: VPN GATEWAY"
} else={
    :local wgAddressId $wgAddressIds
    :if ([/ip address get $wgAddressId interface] != "wg-remote") do={ :error "10.8.0.1/24 exists on another interface; refusing takeover" }
}

:if ([:len [/interface list member find where list="VPN" and interface="wg-remote"]] = 0) do={
    /interface list member add list=VPN interface=wg-remote comment="OMEGA-MANAGED"
}

:local peerIds [/interface wireguard peers find where interface="wg-remote" and allowed-address="10.8.0.2/32"]
:if ([:len $peerIds] > 1) do={ :error "CORE WireGuard peer is duplicated; refusing ambiguous rewrite" }
:if ([:len $peerIds] = 0) do={
    /interface wireguard peers add interface=wg-remote public-key="HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8=" allowed-address=10.8.0.2/32 comment="core.zeaz.dev"
} else={
    :local peerId $peerIds
    :if ([/interface wireguard peers get $peerId public-key] != "HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8=") do={
        :error "CORE WireGuard peer public key differs from verified contract; refusing takeover"
    }
}

/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh disabled=no port=22
/ip service set winbox disabled=no port=8291
:if ([:len [/ip service find where name="reverse-proxy"]] > 0) do={ /ip service set reverse-proxy disabled=yes }
/ip ssh set strong-crypto=yes
/tool bandwidth-server set enabled=no
/ip proxy set enabled=no
/ip socks set enabled=no
/ip upnp set enabled=no
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=LAN
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list=LAN
:put "WIREGUARD SERVICES PASS"
:log warning "OMEGA WIREGUARD SERVICES PASS"
