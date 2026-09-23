#!/usr/bin/env bash
# Deterministic offline fixture tests for topology reconciliation (Phase E).
# No network, no credentials, no production access.
set -Euo pipefail
set +o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/topology-reconcile.sh"
CLEAN="$ROOT/evidence/fixtures/topology/clean.snapshot"
DRIFTED="$ROOT/evidence/fixtures/topology/drifted.snapshot"
FAIL=0
PASS=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# TOPO-01: clean fixture produces no drift and valid JSON
if OUT="$(bash "$TOOL" --snapshot "$CLEAN" 2>/dev/null)"; then
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["summary"]["total"]==0, d["summary"]' <<<"$OUT" 2>/dev/null; then
    ok "TOPO-01 clean snapshot: no drift, valid JSON"
  else
    bad "TOPO-01 clean snapshot has unexpected drifts: $OUT"
  fi
else
  bad "TOPO-01 clean snapshot exited nonzero"
fi

# TOPO-02: drifted fixture detected with expected IDs and derived counts
if OUT="$(bash "$TOOL" --snapshot "$DRIFTED" 2>/dev/null)"; then
  bad "TOPO-02 drifted snapshot reported no drift"
else
  RC=$?
  if [[ "$RC" == "2" ]]; then ok "TOPO-02 drifted snapshot exits 2"; else bad "TOPO-02 wrong exit $RC"; fi
  for did in LAN-CIDR LAN-GATEWAY BRIDGE-MEMBERSHIP DHCP-POOL POOL-OVERLAP LEASE-DUPLICATE RESERVATION ARP-MISMATCH WG-LAN-OVERLAP FIREWALL-FOREIGN MGMT-EXPOSURE CORE-ROUTE DHCP-DNS OBS-NTP OBS-DNS; do
    if grep -Fq "\"id\": \"$did\"" <<<"$OUT"; then ok "TOPO-02 drift $did detected"; else bad "TOPO-02 drift $did missing"; fi
  done
  if python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["summary"]; assert s["total"]==len(d["drifts"]) and s["total"]==s["high"]+s["medium"]+s["low"], s' <<<"$OUT" 2>/dev/null; then
    ok "TOPO-02 counts derived from actual drift records"
  else
    bad "TOPO-02 summary counts inconsistent"
  fi
fi

# TOPO-03: default offline contract mode still passes (backward compat)
if bash "$TOOL" >/dev/null 2>&1; then
  ok "TOPO-03 default offline contract checks PASS"
else
  bad "TOPO-03 default offline contract checks failed"
fi

# TOPO-04: live audit without authorization fails closed without network
bash "$TOOL" --live --target "admin@chr-lab.local" >/dev/null 2>&1
RC=$?
if [[ "$RC" == "0" ]]; then
  bad "TOPO-04 unauthorized live audit allowed"
elif [[ "$RC" == "3" ]]; then
  ok "TOPO-04 live without gates fails closed (exit 3)"
else
  bad "TOPO-04 wrong exit $RC"
fi

# TOPO-05: missing snapshot file fails with usage error, no report written
if bash "$TOOL" --snapshot /nonexistent/file.snapshot >/dev/null 2>&1; then
  bad "TOPO-05 missing snapshot accepted"
else
  ok "TOPO-05 missing snapshot rejected"
fi

echo "---"
echo "topology-reconcile regression: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
