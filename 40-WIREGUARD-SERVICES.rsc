:log warning "OMEGA WIREGUARD SERVICES START"
:local wgId [/interface wireguard find where name="wg-remote"]
:if ([:len $wgId] = 0) do={
    /interface wireguard add name=wg-remote listen-port=51820 mtu=1420 comment="PoliceDBC: VPN"
    :set wgId [/interface wireguard find where name="wg-remote"]
} else={
    :if ([:len $wgId] != 1) do={ :error "wg-remote exists more than once; refusing ambiguous takeover" }
    :if ([/interface wireguard get $wgId listen-port] != 51820) do={ :error "wg-remote listen-port differs from verified contract; refusing takeover" }
    :if ([/interface wireguard get $wgId mtu] != 1420) do={ :error "wg-remote MTU differs from verified contract; refusing takeover" }
}
:if ([:len [/ip address find where address="10.8.0.1/24" and interface!="wg-remote"]] > 0) do={
    :error "10.8.0.1/24 exists on another interface; refusing takeover"
}
:if ([:len [/ip address find where address="10.8.0.1/24" and interface="wg-remote"]] = 0) do={
    /ip address add address=10.8.0.1/24 interface=wg-remote comment="PoliceDBC: VPN GATEWAY"
}
:if ([:len [/interface list member find where list="VPN" and interface="wg-remote"]] = 0) do={
    /interface list member add list=VPN interface=wg-remote comment="OMEGA-MANAGED"
}
:local peerId [/interface wireguard peers find where interface="wg-remote" and allowed-address="10.8.0.2/32"]
:if ([:len $peerId] = 0) do={
    :if ([:len [/interface wireguard peers find where public-key="HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8="]] > 0) do={
        :error "CORE WireGuard public key already exists with a different peer contract"
    }
    /interface wireguard peers add interface=wg-remote public-key="HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8=" allowed-address=10.8.0.2/32 comment="core.zeaz.dev"
} else={
    :if ([:len $peerId] != 1) do={ :error "CORE WireGuard peer is duplicated" }
    :if ([/interface wireguard peers get $peerId public-key] != "HPe+0n/v9HL+0DtcvhNg+GnHwdkgDZertP5NHdZNwW8=") do={
        :error "CORE WireGuard peer public key differs from verified contract"
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
