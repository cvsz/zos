:log warning "OMEGA PRECHECK START"
:put "===== OMEGA PRECHECK ====="
/system resource print
/system package print
/system identity print
:if ([:len [/interface find where name="ether1"]] = 0) do={ :error "PRECHECK FAIL: ether1 missing" }
:if ([:len [/interface bridge find where name="DBC-Bridge-Local"]] = 0) do={ :error "PRECHECK FAIL: DBC-Bridge-Local missing" }
:if ([:len [/ip address find where address="192.168.1.1/24" and interface="DBC-Bridge-Local"]] = 0) do={ :error "PRECHECK FAIL: LAN gateway 192.168.1.1/24 missing from DBC-Bridge-Local" }
:if ([:len [/ip dhcp-client find where interface="ether1" and status="bound"]] = 0) do={ :error "PRECHECK FAIL: ether1 WAN DHCP client is not bound" }
:if ([:len [/ip dhcp-server find where interface="ether1" and disabled=no]] > 0) do={
    :error "PRECHECK FAIL: enabled DHCP server exists on WAN ether1; disable/remove the legacy WAN-side DHCP service before production apply"
}
:if ([:len [/ip address find where address="192.168.0.0/24" and interface="DBC-Bridge-Local"]] > 0) do={
    :error "PRECHECK FAIL: legacy 192.168.0.0/24 address remains on DBC-Bridge-Local; inspect legacy wifi-pool/DHCP ownership before production apply"
}
:if ([:len [/ip route find where dst-address="0.0.0.0/0" and gateway="192.168.200.1"]] = 0) do={ :error "PRECHECK FAIL: expected upstream gateway 192.168.200.1 missing" }
:if ([:len [/interface bridge port find where interface="ether1"]] > 0) do={ :error "PRECHECK FAIL: ether1 must not be a LAN bridge port" }
:put "PRECHECK PASS: ether1 DHCP WAN + DBC-Bridge-Local LAN"
:log warning "OMEGA PRECHECK PASS"
