#!/usr/bin/env bash
# Regression tests for routeros-audit (P2-1). Mocked only, no live router.
# Tests validation gates: production blocklist, auth, host key, args, JSON.
set -Euo pipefail
set +o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="$ROOT/tools/routeros-audit.sh"
FAIL=0
PASS=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

mkdir -p "$ROOT/artifacts/routeros-audit"
chmod 700 "$ROOT/artifacts/routeros-audit" 2>/dev/null || true
trap 'rm -rf "$T0" 2>/dev/null || true' EXIT

# Create a valid identity file for later tests
T0="$(mktemp -d)"
IDENTITY_VALID="$T0/id_rsa"
touch "$IDENTITY_VALID"
chmod 600 "$IDENTITY_VALID"

# AUD-01: help exits 0
if bash "$AUDIT" --help >/dev/null 2>&1; then ok "AUD-01 help exits 0"; else bad "AUD-01 help"; fi

# AUD-02: missing target fails closed
if OUT=$(bash "$AUDIT" --fingerprint "abc" --identity /tmp/nonexistent 2>&1); then
  bad "AUD-02 missing target allowed"
else
  if grep -Eiq 'target.*required' <<<"$OUT"; then ok "AUD-02 missing target fails closed"; else bad "AUD-02 wrong error: $OUT"; fi
fi

# AUD-03: missing fingerprint fails closed
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --identity /tmp/nonexistent 2>&1); then
  bad "AUD-03 missing fingerprint allowed"
else
  if grep -Eiq 'fingerprint.*required' <<<"$OUT"; then ok "AUD-03 missing fingerprint fails closed"; else bad "AUD-03 wrong error: $OUT"; fi
fi

# AUD-04: missing identity fails closed
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc" 2>&1); then
  bad "AUD-04 missing identity allowed"
else
  if grep -Eiq 'identity.*required' <<<"$OUT"; then ok "AUD-04 missing identity fails closed"; else bad "AUD-04 wrong error: $OUT"; fi
fi

# AUD-05: identity file not found fails closed
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc" --identity /tmp/definitely-not-a-key 2>&1); then
  bad "AUD-05 nonexistent identity allowed"
else
  if grep -Eiq 'not found|not readable' <<<"$OUT"; then ok "AUD-05 nonexistent identity fails closed"; else bad "AUD-05 wrong error: $OUT"; fi
fi

# AUD-06: production target refused without authorization
if OUT=$(bash "$AUDIT" --target "admin@192.168.1.1" --fingerprint "abc" --identity "$IDENTITY_VALID" --allow-live-audit 2>&1); then
  bad "AUD-06 production target allowed"
else
  if grep -Eiq 'blocklist|production' <<<"$OUT"; then ok "AUD-06 production target refused"; else bad "AUD-06 wrong error: $OUT"; fi
fi

# AUD-07: live without OMEGA_AUDIT_AUTHORIZED_BY fails closed
export OMEGA_ALLOW_LIVE_AUDIT=1
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc" --identity "$IDENTITY_VALID" --allow-live-audit 2>&1); then
  bad "AUD-07 unauthorized live allowed"
else
  if grep -Eiq 'authorization|OMEGA_AUDIT' <<<"$OUT"; then ok "AUD-07 live without auth fails closed"; else bad "AUD-07 wrong error: $OUT"; fi
fi
unset OMEGA_ALLOW_LIVE_AUDIT

# AUD-08: live without OMEGA_AUDIT_AUTHORIZED_BY fails closed
export OMEGA_ALLOW_LIVE_AUDIT=1
# shellcheck disable=SC2209
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc" --identity "$IDENTITY_VALID" --allow-live-audit 2>&1); then
  bad "AUD-08 unauthorized live allowed"
else
  if grep -Eiq 'OMEGA_AUDIT_AUTHORIZED_BY|fail-closed' <<<"$OUT"; then ok "AUD-08 live without auth fails closed"; else bad "AUD-08 wrong error: $OUT"; fi
fi
unset OMEGA_ALLOW_LIVE_AUDIT

# AUD-09: live audit with valid env produces JSON (SSH will fail but validation passes)
EV9="$ROOT/artifacts/routeros-audit/audit-$(date +%s).json"
export OMEGA_ALLOW_LIVE_AUDIT=1
export OMEGA_AUDIT_AUTHORIZED_BY="test-operator"
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc123" --identity "$IDENTITY_VALID" --allow-live-audit --timeout 2 --output "$EV9" 2>/dev/null) || true; then
  if [[ -s "$EV9" ]] && python3 -c 'import json; json.load(open("'"$EV9"'"))' 2>/dev/null; then
    ok "AUD-09 produces valid JSON snapshot"
  else
    bad "AUD-09 no valid JSON evidence"
  fi
else
  bad "AUD-09 script failed"
fi
rm -f "$EV9"
unset OMEGA_ALLOW_LIVE_AUDIT
unset OMEGA_AUDIT_AUTHORIZED_BY

# AUD-10: identity file not readable fails closed
T4="$(mktemp -d)"
UNREADABLE="$T4/no-such-file"
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc" --identity "$UNREADABLE" 2>&1); then
  bad "AUD-10 unreadable identity allowed"
else
  ok "AUD-10 unreadable identity fails closed"
fi
rm -rf "$T4"

# AUD-11: StrictHostKeyChecking is enforced (grep script)
if grep -Fq 'StrictHostKeyChecking=yes' "$AUDIT"; then
  ok "AUD-11 StrictHostKeyChecking=yes enforced"
else
  bad "AUD-11 StrictHostKeyChecking not enforced"
fi

# AUD-12: BatchMode and no password prompts
if grep -Fq 'BatchMode=yes' "$AUDIT" && grep -Fq 'NumberOfPasswordPrompts=0' "$AUDIT"; then
  ok "AUD-12 BatchMode + no password prompts"
else
  bad "AUD-12 SSH auth not key-only"
fi

# AUD-13: no mutation commands in allowlist
MUTATE_CMDS=("/set" "/remove" "/add" "/export" "/import" "/reset" "/commit" "/rollback" "/save" "/sync")
for mc in "${MUTATE_CMDS[@]}"; do
  if grep -Fq "$mc " "$AUDIT" 2>/dev/null; then
    bad "AUD-13 mutation command allowed: $mc"
  fi
done
ok "AUD-13 no mutation commands in allowlist"

echo "---"
echo "routeros-audit regression: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
