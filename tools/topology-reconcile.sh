#!/usr/bin/env bash
# Read-only topology reconciliation (P1-3 preparation). Offline only.
# Compares repository contracts without touching production devices, mutating
# state, or using credentials. Exit 0 when contracts agree; exit 2 otherwise.
set -Euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

disagree() { echo "DISAGREE: $1"; FAIL=1; }

TOPO="$ROOT/config/topology.env.example"

# Canonical production contract from topology example.
grep -q '^ROUTER_WAN_MODE=dhcp$' "$TOPO" || disagree "topology.example missing ROUTER_WAN_MODE=dhcp"
grep -q '^ROUTER_WAN_INTERFACE=ether1$' "$TOPO" || disagree "topology.example missing ether1 WAN"
grep -q '^ROUTER_LAN_BRIDGE=DBC-Bridge-Local$' "$TOPO" || disagree "topology.example missing DBC-Bridge-Local"
grep -q '^ROUTER_LAN_CIDR=192\.168\.1\.0/24$' "$TOPO" || disagree "topology.example LAN CIDR must be 192.168.1.0/24"
grep -q '^ROUTER_LAN_IP=192\.168\.1\.1$' "$TOPO" || disagree "topology.example LAN gateway must be 192.168.1.1"
grep -q '^DEV_LAN_IP=192\.168\.1\.123$' "$TOPO" || disagree "CORE .123 missing"
grep -q '^PROD_LAN_IP=192\.168\.1\.122$' "$TOPO" || disagree "PROD .122 missing"

# RSC contracts must agree with canonical LAN CIDR/gateway and owned resources.
grep -q '192\.168\.1\.1/24' "$ROOT/00-PRECHECK.rsc" || disagree "00-PRECHECK missing 192.168.1.1/24"
grep -q '192\.168\.1\.0/24' "$ROOT/30-DHCP-DNS-NTP.rsc" || disagree "30-DHCP missing 192.168.1.0/24 network contract"
grep -Fq 'lan-pool' "$ROOT/30-DHCP-DNS-NTP.rsc" || disagree "30-DHCP missing lan-pool"
grep -Fq 'ZEAZ-PoliceDBC-INPUT' "$ROOT/50-FIREWALL-NAT.rsc" || disagree "50-FIREWALL missing owned chain"

# Observability/verification must assert the same production contract.
grep -Fq 'OMEGA VERIFY PASS' "$ROOT/99-VERIFY-HEALTH.rsc" || disagree "99-VERIFY missing OMEGA VERIFY PASS"
grep -Fq 'lan-pool ranges do not match production contract' "$ROOT/99-VERIFY-HEALTH.rsc" || disagree "99-VERIFY missing pool contract assertion"
grep -q '192\.168\.1\.1/24' "$ROOT/99-VERIFY-HEALTH.rsc" || disagree "99-VERIFY missing LAN gateway contract"

if (( FAIL == 0 )); then
  echo "Topology reconciliation PASS (offline, read-only, no production access)"
else
  echo "Topology reconciliation found disagreements (no mutation performed)" >&2
fi
exit "$FAIL"
