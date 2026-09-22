:log warning "OMEGA FIREWALL NAT START"

# zOS owns only rules carrying ZEAZ-PoliceDBC/PoliceDBC comments. Existing
# unrelated rules in these named chains are preserved; conflicts fail closed.
:local inputJump [/ip firewall filter find where chain="input" and jump-target="ZEAZ-PoliceDBC-INPUT" and comment="ZEAZ-PoliceDBC: INPUT POLICY"]
:if ([:len $inputJump] = 0) do={
    :if ([:len [/ip firewall filter find where chain="input" and jump-target="ZEAZ-PoliceDBC-INPUT"]] > 0) do={ :error "input already jumps to ZEAZ-PoliceDBC-INPUT without zOS ownership" }
    /ip firewall filter add chain=input action=jump jump-target=ZEAZ-PoliceDBC-INPUT place-before=0 comment="ZEAZ-PoliceDBC: INPUT POLICY"
} else={
    :if ([:len $inputJump] > 1) do={ :error "owned input policy jump is duplicated" }
    :if ([/ip firewall filter get $inputJump disabled] = true) do={ :error "owned input policy jump is disabled; refusing silent policy bypass" }
}
:local forwardJump [/ip firewall filter find where chain="forward" and jump-target="ZEAZ-PoliceDBC-FORWARD" and comment="ZEAZ-PoliceDBC: FORWARD POLICY"]
:if ([:len $forwardJump] = 0) do={
    :if ([:len [/ip firewall filter find where chain="forward" and jump-target="ZEAZ-PoliceDBC-FORWARD"]] > 0) do={ :error "forward already jumps to ZEAZ-PoliceDBC-FORWARD without zOS ownership" }
    /ip firewall filter add chain=forward action=jump jump-target=ZEAZ-PoliceDBC-FORWARD place-before=0 comment="ZEAZ-PoliceDBC: FORWARD POLICY"
} else={
    :if ([/ip firewall filter print count-only where chain="forward" and jump-target="ZEAZ-PoliceDBC-FORWARD" and comment="ZEAZ-PoliceDBC: FORWARD POLICY"] > 1) do={ :error "owned forward policy jump is duplicated" }
    :if ([/ip firewall filter get $forwardJump disabled] = true) do={ :error "owned forward policy jump is disabled; refusing silent policy bypass" }
}

/ip firewall filter
:foreach ruleId in=[find where chain="ZEAZ-PoliceDBC-INPUT"] do={
    :local ruleComment [get $ruleId comment]
    :if ([:pick $ruleComment 0 10] != "PoliceDBC:") do={ :error "unowned rule found in ZEAZ-PoliceDBC-INPUT; refusing rewrite" }
}
:foreach ruleId in=[find where chain="ZEAZ-PoliceDBC-FORWARD"] do={
    :local ruleComment [get $ruleId comment]
    :if ([:pick $ruleComment 0 10] != "PoliceDBC:") do={ :error "unowned rule found in ZEAZ-PoliceDBC-FORWARD; refusing rewrite" }
}
remove [find where chain="ZEAZ-PoliceDBC-INPUT" and comment~"^PoliceDBC:"]
remove [find where chain="ZEAZ-PoliceDBC-FORWARD" and comment~"^PoliceDBC:"]

/ip firewall filter
add chain=ZEAZ-PoliceDBC-INPUT action=accept connection-state=established,related,untracked comment="PoliceDBC: INPUT Established Related"
add chain=ZEAZ-PoliceDBC-INPUT action=drop connection-state=invalid comment="PoliceDBC: INPUT Invalid Drop"
add chain=ZEAZ-PoliceDBC-INPUT action=accept protocol=icmp comment="PoliceDBC: INPUT ICMP"
add chain=ZEAZ-PoliceDBC-INPUT action=accept protocol=udp in-interface-list=WAN dst-port=51820 comment="PoliceDBC: INPUT WireGuard WAN"
add chain=ZEAZ-PoliceDBC-INPUT action=accept in-interface-list=LAN comment="PoliceDBC: INPUT LAN Management"
add chain=ZEAZ-PoliceDBC-INPUT action=accept in-interface-list=VPN comment="PoliceDBC: INPUT VPN Management"
add chain=ZEAZ-PoliceDBC-INPUT action=drop comment="PoliceDBC: INPUT DEFAULT DENY"

add chain=ZEAZ-PoliceDBC-FORWARD action=fasttrack-connection connection-state=established,related comment="PoliceDBC: FORWARD FastTrack"
add chain=ZEAZ-PoliceDBC-FORWARD action=accept connection-state=established,related,untracked comment="PoliceDBC: FORWARD Established Related"
add chain=ZEAZ-PoliceDBC-FORWARD action=drop connection-state=invalid comment="PoliceDBC: FORWARD Invalid Drop"
add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=192.168.1.0/24 in-interface-list=LAN out-interface-list=WAN comment="PoliceDBC: FORWARD LAN to WAN"
add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=10.8.0.0/24 in-interface-list=VPN out-interface-list=WAN comment="PoliceDBC: FORWARD VPN to WAN"
add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=10.8.0.0/24 dst-address=192.168.1.0/24 in-interface-list=VPN out-interface-list=LAN comment="PoliceDBC: FORWARD VPN to LAN"
add chain=ZEAZ-PoliceDBC-FORWARD action=accept src-address=192.168.1.0/24 dst-address=10.8.0.0/24 in-interface-list=LAN out-interface-list=VPN comment="PoliceDBC: FORWARD LAN to VPN"
add chain=ZEAZ-PoliceDBC-FORWARD action=drop comment="PoliceDBC: FORWARD DEFAULT DENY"

:local srcnatJump [/ip firewall nat find where chain="srcnat" and jump-target="ZEAZ-PoliceDBC-SRCNAT" and comment="ZEAZ-PoliceDBC: SRCNAT POLICY"]
:if ([:len $srcnatJump] = 0) do={
    :if ([:len [/ip firewall nat find where chain="srcnat" and jump-target="ZEAZ-PoliceDBC-SRCNAT"]] > 0) do={ :error "srcnat already jumps to ZEAZ-PoliceDBC-SRCNAT without zOS ownership" }
    /ip firewall nat add chain=srcnat action=jump jump-target=ZEAZ-PoliceDBC-SRCNAT place-before=0 comment="ZEAZ-PoliceDBC: SRCNAT POLICY"
} else={
    :if ([/ip firewall nat print count-only where chain="srcnat" and jump-target="ZEAZ-PoliceDBC-SRCNAT" and comment="ZEAZ-PoliceDBC: SRCNAT POLICY"] > 1) do={ :error "owned srcnat policy jump is duplicated" }
    :if ([/ip firewall nat get $srcnatJump disabled] = true) do={ :error "owned srcnat policy jump is disabled; refusing silent NAT bypass" }
}
/ip firewall nat
:foreach ruleId in=[find where chain="ZEAZ-PoliceDBC-SRCNAT"] do={
    :local ruleComment [get $ruleId comment]
    :if ([:pick $ruleComment 0 10] != "PoliceDBC:") do={ :error "unowned rule found in ZEAZ-PoliceDBC-SRCNAT; refusing rewrite" }
}
remove [find where chain="ZEAZ-PoliceDBC-SRCNAT" and comment~"^PoliceDBC:"]
add chain=ZEAZ-PoliceDBC-SRCNAT action=masquerade src-address=192.168.1.0/24 out-interface-list=WAN comment="PoliceDBC: NAT LAN to WAN"
add chain=ZEAZ-PoliceDBC-SRCNAT action=masquerade src-address=10.8.0.0/24 out-interface-list=WAN comment="PoliceDBC: NAT VPN to WAN"

:put "FIREWALL NAT PASS"
:log warning "OMEGA FIREWALL NAT PASS"
