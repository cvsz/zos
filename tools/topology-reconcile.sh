#!/usr/bin/env bash
# Read-only topology reconciliation. Offline by default; live collection is
# disabled unless an approved operator window explicitly opts in.
#
# Usage:
#   tools/topology-reconcile.sh
#       Offline repository-contract checks (backward compatible).
#       Exit 0 when contracts agree, 1 with disagreement list otherwise.
#   tools/topology-reconcile.sh --snapshot <file> [--report <file>]
#       Compare a sanitized runtime snapshot against the repository contract
#       and emit a structured JSON drift report (severity, expected, observed,
#       evidence). Exit 0 (no drift) or 2 (drift found).
#   tools/topology-reconcile.sh --live --target <user@host>
#       Live read-only audit. Requires OMEGA_ALLOW_LIVE_AUDIT=1,
#       OMEGA_AUDIT_AUTHORIZED_BY=<operator> and a known target identity.
#       Without them the tool exits 3 without touching the network.
#
# Snapshot format (sanitized KEY=VALUE lines, no secrets):
#   wan.mode, wan.interface, route.default, lan.bridge, lan.members (comma),
#   bridge.vlan-filtering, dhcp.pool.<name>, dhcp.network, dhcp.dns,
#   lease.<MAC>=<ip>, arp.<MAC>=<ip>, wireguard.peer.<name>.allowed (comma),
#   firewall.owned.chains (comma), firewall.foreign=<0|1>,
#   service.ssh.interfaces (comma), core.route.default, core.route.lan,
#   core.route.wg
set -Euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Production contract (read-only, mirrors topology.env.example + RSC) ---
WAN_MODE="dhcp"
WAN_IF="ether1"
LAN_BRIDGE="DBC-Bridge-Local"
LAN_CIDR="192.168.1.0/24"
LAN_GW="192.168.1.1"
POOL_CONTRACT="192.168.1.59-192.168.1.99,192.168.1.101-192.168.1.118,192.168.1.121,192.168.1.124-192.168.1.237,192.168.1.239-192.168.1.254"
DHCP_NETWORK="192.168.1.0/24"
DHCP_DNS="192.168.1.1"
CORE_DEFAULT="default via 192.168.1.1 dev ens33"
CORE_LAN="192.168.1.0/24 dev ens33"
CORE_WG="10.8.0.0/24 dev policedbc"

# MAC (colon, upper) -> expected IP, from 30-DHCP-DNS-NTP.rsc fixed inventory.
EXPECTED_LEASES=(
  "48:4D:7E:D4:3A:C6=192.168.1.100"
  "00:0C:29:75:A6:D4=192.168.1.123"
  "00:0C:29:B5:F4:09=192.168.1.122"
  "88:DC:96:53:0F:55=192.168.1.50"
  "88:DC:96:55:58:E4=192.168.1.51"
  "88:DC:96:55:58:E7=192.168.1.52"
  "88:DC:96:55:58:F0=192.168.1.53"
  "88:DC:96:55:58:DE=192.168.1.54"
  "88:DC:96:55:58:ED=192.168.1.55"
  "88:DC:96:55:58:EA=192.168.1.56"
  "88:DC:96:55:58:F3=192.168.1.57"
  "88:DC:96:55:58:E1=192.168.1.58"
)

offline_contract_checks() {
  local fail=0
  disagree() { echo "DISAGREE: $1"; fail=1; }
  grep -q '^ROUTER_WAN_MODE=dhcp$' "$ROOT/config/topology.env.example" || disagree "topology.example missing ROUTER_WAN_MODE=dhcp"
  grep -q '^ROUTER_WAN_INTERFACE=ether1$' "$ROOT/config/topology.env.example" || disagree "topology.example missing ether1 WAN"
  grep -q '^ROUTER_LAN_BRIDGE=DBC-Bridge-Local$' "$ROOT/config/topology.env.example" || disagree "topology.example missing DBC-Bridge-Local"
  grep -q '^ROUTER_LAN_CIDR=192\\.168\\.1\\.0/24$' "$ROOT/config/topology.env.example" || disagree "topology.example LAN CIDR drift"
  grep -q '^ROUTER_LAN_IP=192\\.168\\.1\\.1$' "$ROOT/config/topology.env.example" || disagree "topology.example LAN gateway drift"
  grep -q '^DEV_LAN_IP=192\.168\.1\.123$' "$ROOT/config/topology.env.example" || disagree "CORE .123 missing"
  grep -q '^PROD_LAN_IP=192\.168\.1\.122$' "$ROOT/config/topology.env.example" || disagree "PROD .122 missing"
  grep -q '192\.168\.1\.1/24' "$ROOT/00-PRECHECK.rsc" || disagree "00-PRECHECK missing 192.168.1.1/24"
  grep -Fq 'lan-pool' "$ROOT/30-DHCP-DNS-NTP.rsc" || disagree "30-DHCP missing lan-pool"
  grep -Fq 'ZEAZ-PoliceDBC-INPUT' "$ROOT/50-FIREWALL-NAT.rsc" || disagree "50-FIREWALL missing owned chain"
  grep -Fq 'OMEGA VERIFY PASS' "$ROOT/99-VERIFY-HEALTH.rsc" || disagree "99-VERIFY missing OMEGA VERIFY PASS"
  grep -Fq 'lan-pool ranges do not match production contract' "$ROOT/99-VERIFY-HEALTH.rsc" || disagree "99-VERIFY missing pool contract assertion"
  if (( fail == 0 )); then
    echo "Topology reconciliation PASS (offline, read-only, no production access)"
  else
    echo "Topology reconciliation found disagreements (no mutation performed)" >&2
  fi
  return "$fail"
}

norm_mac() { tr 'a-z-' 'A-Z:' <<<"$1"; }

ip2int() {
  local a b c d
  IFS=. read -r a b c d <<<"$1"
  echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# range_overlap "a-b" "c-d" -> 0/1 via stdout
range_overlap() {
  local s1 e1 s2 e2
  s1="$(ip2int "${1%%-*}")"; e1="$(ip2int "${1##*-}")"
  s2="$(ip2int "${2%%-*}")"; e2="$(ip2int "${2##*-}")"
  if (( s1 <= e2 && s2 <= e1 )); then echo 1; else echo 0; fi
}

snapshot_audit() {
  local snap="$1" report="${2:-}"
  [[ -f "$snap" ]] || { echo "ERROR: snapshot file not found: $snap" >&2; return 3; }
  declare -A S=()
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" == \#* ]] && continue
    S["$k"]="$v"
  done < "$snap"

  local drifts_tsv=""
  drift() { drifts_tsv+="$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$5"$'\n'; }

  # 1. WAN DHCP/interface
  [[ "${S[wan.mode]:-}" == "$WAN_MODE" ]] || drift "WAN-DHCP" "high" "wan.mode=$WAN_MODE" "wan.mode=${S[wan.mode]:-<missing>}" "snapshot wan.mode"
  [[ "${S[wan.interface]:-}" == "$WAN_IF" ]] || drift "WAN-INTERFACE" "high" "wan.interface=$WAN_IF" "wan.interface=${S[wan.interface]:-<missing>}" "snapshot wan.interface"
  # 2. default route present and not via LAN bridge
  if [[ -z "${S[route.default]:-}" ]]; then
    drift "DEFAULT-ROUTE" "high" "default route via DHCP/$WAN_IF" "<missing>" "snapshot route.default"
  elif [[ "${S[route.default]}" == *"DBC-Bridge-Local"* ]]; then
    drift "DEFAULT-ROUTE" "high" "default route not via LAN bridge" "${S[route.default]}" "snapshot route.default"
  fi
  # 3. bridge membership: ether1 must not be bridged; LAN identity contract
  [[ "${S[lan.bridge]:-}" == "$LAN_BRIDGE" ]] || drift "LAN-BRIDGE" "high" "lan.bridge=$LAN_BRIDGE" "lan.bridge=${S[lan.bridge]:-<missing>}" "snapshot lan.bridge"
  [[ "${S[lan.cidr]:-}" == "$LAN_CIDR" ]] || drift "LAN-CIDR" "high" "lan.cidr=$LAN_CIDR" "lan.cidr=${S[lan.cidr]:-<missing>}" "snapshot lan.cidr"
  [[ "${S[lan.gateway]:-}" == "$LAN_GW" ]] || drift "LAN-GATEWAY" "high" "lan.gateway=$LAN_GW" "lan.gateway=${S[lan.gateway]:-<missing>}" "snapshot lan.gateway"
  if [[ ",${S[lan.members]:-}," == *",ether1,"* ]]; then
    drift "BRIDGE-MEMBERSHIP" "high" "ether1 not bridged" "lan.members=${S[lan.members]}" "snapshot lan.members"
  fi
  [[ "${S[bridge.vlan-filtering]:-no}" == "no" ]] || drift "BRIDGE-VLAN" "medium" "bridge.vlan-filtering=no" "bridge.vlan-filtering=${S[bridge.vlan-filtering]}" "snapshot"
  # 4. DHCP pool contract + overlap between snapshot pools
  if [[ -n "${S[dhcp.pool.lan-pool]:-}" && "${S[dhcp.pool.lan-pool]}" != "$POOL_CONTRACT" ]]; then
    drift "DHCP-POOL" "high" "lan-pool=$POOL_CONTRACT" "lan-pool=${S[dhcp.pool.lan-pool]}" "snapshot dhcp.pool.lan-pool"
  fi
  _pool_names=()
  for k in "${!S[@]}"; do [[ "$k" == dhcp.pool.* ]] && _pool_names+=("${k#dhcp.pool.}"); done
  for (( i=0; i<${#_pool_names[@]}; i++ )); do
    for (( j=i+1; j<${#_pool_names[@]}; j++ )); do
      IFS=',' read -ra _ra <<<"${S[dhcp.pool.${_pool_names[$i]}]}"
      IFS=',' read -ra _rb <<<"${S[dhcp.pool.${_pool_names[$j]}]}"
      for _x in "${_ra[@]}"; do for _y in "${_rb[@]}"; do
        [[ "$_x" == *"-"* && "$_y" == *"-"* ]] || continue
        if [[ "$(range_overlap "$_x" "$_y")" == "1" ]]; then
          drift "POOL-OVERLAP" "high" "disjoint pools" "${_pool_names[$i]}($_x) overlaps ${_pool_names[$j]}($_y)" "snapshot dhcp.pool.*"
        fi
      done; done
    done
  done
  [[ "${S[dhcp.network]:-}" == "$DHCP_NETWORK" ]] || drift "DHCP-NETWORK" "high" "dhcp.network=$DHCP_NETWORK" "dhcp.network=${S[dhcp.network]:-<missing>}" "snapshot"
  [[ "${S[dhcp.dns]:-}" == "$DHCP_DNS" ]] || drift "DHCP-DNS" "medium" "dhcp.dns=$DHCP_DNS" "dhcp.dns=${S[dhcp.dns]:-<missing>}" "snapshot"
  # 5. duplicate leases + EnGenius/fixed reservations + ARP match
  declare -A _ip_owner=()
  for k in "${!S[@]}"; do
    [[ "$k" == lease.* ]] || continue
    _mac="$(norm_mac "${k#lease.}")"; _ip="${S[$k]}"
    if [[ -n "${_ip_owner[$_ip]:-}" ]]; then
      drift "LEASE-DUPLICATE" "high" "unique IP per lease" "$_ip claimed by ${_ip_owner[$_ip]} and $_mac" "snapshot lease.*"
    else
      _ip_owner["$_ip"]="$_mac"
    fi
  done
  for _pair in "${EXPECTED_LEASES[@]}"; do
    _mac="${_pair%%=*}"; _exp="${_pair##*=}"
    _lookup="lease.$_mac"; _alt="lease.$(tr ':' '-' <<<"$_mac")"
    _obs="${S[$_lookup]:-${S[$_alt]:-}}"
    # snapshot MACs may use dashes/lowercase; normalize by scanning keys
    if [[ -z "$_obs" ]]; then
      for k in "${!S[@]}"; do
        [[ "$k" == lease.* ]] || continue
        if [[ "$(norm_mac "${k#lease.}")" == "$_mac" ]]; then _obs="${S[$k]}"; break; fi
      done
    fi
    [[ "$_obs" == "$_exp" ]] || drift "RESERVATION" "medium" "$_mac=$_exp" "$_mac=${_obs:-<missing>}" "snapshot lease.* vs fixed inventory"
    _arp=""; for k in "${!S[@]}"; do
      [[ "$k" == arp.* ]] || continue
      if [[ "$(norm_mac "${k#arp.}")" == "$_mac" ]]; then _arp="${S[$k]}"; break; fi
    done
    if [[ -n "$_arp" && -n "$_obs" && "$_arp" != "$_obs" ]]; then
      drift "ARP-MISMATCH" "medium" "arp($_mac)=$_obs" "arp($_mac)=$_arp" "snapshot arp.* vs lease"
    fi
  done
  # 6. WireGuard AllowedIPs must exclude physical LAN
  for k in "${!S[@]}"; do
    [[ "$k" == wireguard.peer.*.allowed ]] || continue
    if [[ ",${S[$k]}," == *"192.168.1.0/24"* ]]; then
      drift "WG-LAN-OVERLAP" "high" "AllowedIPs excludes 192.168.1.0/24" "$k=${S[$k]}" "snapshot $k"
    fi
  done
  # 7. firewall ownership + management exposure
  if [[ ",${S[firewall.owned.chains]:-}," != *"ZEAZ-PoliceDBC-INPUT"* ]]; then
    drift "FIREWALL-OWNERSHIP" "high" "owned chain ZEAZ-PoliceDBC-INPUT present" "firewall.owned.chains=${S[firewall.owned.chains]:-<missing>}" "snapshot"
  fi
  [[ "${S[firewall.foreign]:-0}" == "0" ]] || drift "FIREWALL-FOREIGN" "high" "no foreign rules in owned chains" "firewall.foreign=${S[firewall.foreign]}" "snapshot"
  if [[ ",${S[service.ssh.interfaces]:-}," == *",ether1,"* || ",${S[service.ssh.interfaces]:-}," == *",wan,"* ]]; then
    drift "MGMT-EXPOSURE" "high" "ssh on LAN/VPN only" "service.ssh.interfaces=${S[service.ssh.interfaces]}" "snapshot"
  fi
  # 8. CORE route invariants
  [[ "${S[core.route.default]:-}" == "$CORE_DEFAULT" ]] || drift "CORE-ROUTE" "high" "$CORE_DEFAULT" "${S[core.route.default]:-<missing>}" "snapshot core.route.default"
  [[ "${S[core.route.lan]:-}" == "$CORE_LAN" ]] || drift "CORE-ROUTE" "medium" "$CORE_LAN" "${S[core.route.lan]:-<missing>}" "snapshot core.route.lan"
  [[ "${S[core.route.wg]:-}" == "$CORE_WG" ]] || drift "CORE-ROUTE" "medium" "$CORE_WG" "${S[core.route.wg]:-<missing>}" "snapshot core.route.wg"
  # 9. observability fixtures (offline): NTP client + DNS resolution health
  [[ "${S[ntp.enabled]:-}" == "yes" ]] || drift "OBS-NTP" "medium" "ntp.enabled=yes" "ntp.enabled=${S[ntp.enabled]:-<missing>}" "snapshot ntp.enabled"
  [[ "${S[ntp.synced]:-}" == "yes" ]] || drift "OBS-NTP" "low" "ntp.synced=yes" "ntp.synced=${S[ntp.synced]:-<missing>}" "snapshot ntp.synced"
  [[ "${S[dns.resolves]:-}" == "1" ]] || drift "OBS-DNS" "medium" "dns.resolves=1" "dns.resolves=${S[dns.resolves]:-<missing>}" "snapshot dns.resolves"

  local generated
  generated="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local json
  json="$(DRIFTS_TSV="$drifts_tsv" SNAP="$snap" GENERATED="$generated" python3 - <<'PYEOF'
import json, os
drifts = []
for line in os.environ.get("DRIFTS_TSV", "").splitlines():
    parts = line.split("\t")
    if len(parts) != 5:
        continue
    did, sev, exp, obs, ev = parts
    drifts.append({"id": did, "severity": sev, "expected": exp,
                   "observed": obs, "evidence": ev})
sev_count = {"high": 0, "medium": 0, "low": 0}
for d in drifts:
    sev_count[d["severity"]] = sev_count.get(d["severity"], 0) + 1
print(json.dumps({"generated_at": os.environ["GENERATED"],
                  "contract": "config/topology.env.example + RSC phases",
                  "snapshot": os.environ["SNAP"],
                  "drifts": drifts,
                  "summary": {"total": len(drifts), **sev_count}}, indent=2))
PYEOF
)"
  if [[ -n "$report" ]]; then
    printf '%s\n' "$json" > "$report"
    chmod 600 "$report" 2>/dev/null || true
  else
    printf '%s\n' "$json"
  fi
  local total
  total="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"]["total"])' <<<"$json")"
  if (( total == 0 )); then
    echo "No drift: snapshot matches repository contract" >&2
    return 0
  fi
  echo "Drift detected: $total finding(s) (no mutation performed)" >&2
  return 2
}

live_audit() {
  local target="$1"
  if [[ "${OMEGA_ALLOW_LIVE_AUDIT:-0}" != "1" ]]; then
    echo "ERROR: live audit blocked: OMEGA_ALLOW_LIVE_AUDIT=1 is required" >&2
    return 3
  fi
  if [[ -z "${OMEGA_AUDIT_AUTHORIZED_BY:-}" ]]; then
    echo "ERROR: live audit blocked: OMEGA_AUDIT_AUTHORIZED_BY=<operator> is required" >&2
    return 3
  fi
  for blocked in 192.168.1.1 core.zeaz.dev prod.zeaz.dev; do
    if [[ "$target" == *"$blocked"* ]]; then
      echo "ERROR: live audit target matches production ($blocked); refusing" >&2
      return 3
    fi
  done
  echo "ERROR: live audit BLOCKED: no verified isolated target execution path in this environment; no collection performed" >&2
  return 4
}

case "${1:-}" in
  --snapshot)
    [[ $# -ge 2 ]] || { echo "Usage: $0 --snapshot <file> [--report <file>]" >&2; exit 3; }
    _report=""
    if [[ "${3:-}" == "--report" ]]; then _report="${4:-}"; [[ -n "$_report" ]] || { echo "ERROR: --report needs a file" >&2; exit 3; }; fi
    snapshot_audit "$2" "$_report"
    ;;
  --live)
    [[ "${2:-}" == "--target" && -n "${3:-}" ]] || { echo "Usage: $0 --live --target <user@host>" >&2; exit 3; }
    live_audit "$3"
    ;;
  --help|-h) sed -n '2,30p' "$0" ;;
  "") offline_contract_checks ;;
  *) echo "Unknown argument: $1 (see --help)" >&2; exit 3 ;;
esac
