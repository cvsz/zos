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
T0=""
trap '[[ -z "${T0:-}" ]] || rm -rf "$T0" 2>/dev/null || true' EXIT

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

# AUD-07: missing explicit --allow-live-audit flag fails before operator authorization
export OMEGA_ALLOW_LIVE_AUDIT=1
export OMEGA_AUDIT_AUTHORIZED_BY="test-operator"
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc" --identity "$IDENTITY_VALID" 2>&1); then
  bad "AUD-07 missing --allow-live-audit flag allowed"
else
  if grep -Fq -- '--allow-live-audit' <<<"$OUT"; then ok "AUD-07 explicit live-audit flag required"; else bad "AUD-07 wrong error: $OUT"; fi
fi
unset OMEGA_AUDIT_AUTHORIZED_BY

# AUD-08: missing OMEGA_AUDIT_AUTHORIZED_BY fails after live-audit flag/gate pass
if OUT=$(bash "$AUDIT" --target "admin@chr-lab" --fingerprint "abc" --identity "$IDENTITY_VALID" --allow-live-audit 2>&1); then
  bad "AUD-08 unauthorized live allowed"
else
  if grep -Fq 'OMEGA_AUDIT_AUTHORIZED_BY' <<<"$OUT"; then ok "AUD-08 operator authorization required"; else bad "AUD-08 wrong error: $OUT"; fi
fi
unset OMEGA_ALLOW_LIVE_AUDIT

# AUD-09: only pinned host-key and successful mocked SSH may produce PASS.
ssh-keygen -q -t ed25519 -N '' -f "$T0/hostkey" >/dev/null 2>&1
KNOWN_HOSTS="$T0/known_hosts"
printf 'chr-lab %s\n' "$(cat "$T0/hostkey.pub")" > "$KNOWN_HOSTS"
FINGERPRINT="$(ssh-keygen -lf "$KNOWN_HOSTS" -E sha256 | awk '{print $2}')"
mkdir -p "$T0/bin"
cat > "$T0/bin/ssh" <<'MOCKSSH'
#!/usr/bin/env bash
printf 'mock read-only response\n'
MOCKSSH
chmod 700 "$T0/bin/ssh"
EV9="$ROOT/artifacts/routeros-audit/audit-$(date +%s)-$$.json"
export OMEGA_ALLOW_LIVE_AUDIT=1
export OMEGA_AUDIT_AUTHORIZED_BY="test-operator"
export OMEGA_AUDIT_KNOWN_HOSTS="$KNOWN_HOSTS"
if PATH="$T0/bin:$PATH" bash "$AUDIT" --target "admin@chr-lab" --fingerprint "$FINGERPRINT" --identity "$IDENTITY_VALID" --allow-live-audit --timeout 2 --output "$EV9" >/dev/null 2>&1; then
  if [[ -s "$EV9" ]] && python3 - "$EV9" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    result = json.load(fh)
assert result["status"] == "PASS"
assert result["live_audit"] is True
assert result["commands"]
PY
  then
    ok "AUD-09 pinned-host mocked SSH produces valid PASS JSON"
  else
    bad "AUD-09 missing or invalid PASS JSON evidence"
  fi
else
  bad "AUD-09 authorized mocked SSH unexpectedly failed"
fi
rm -f "$EV9"
unset OMEGA_ALLOW_LIVE_AUDIT OMEGA_AUDIT_AUTHORIZED_BY OMEGA_AUDIT_KNOWN_HOSTS

# AUD-14: SSH failures must never report a successful audit.
cat > "$T0/bin/ssh" <<'FAILSSH'
#!/usr/bin/env bash
exit 255
FAILSSH
chmod 700 "$T0/bin/ssh"
export OMEGA_ALLOW_LIVE_AUDIT=1 OMEGA_AUDIT_AUTHORIZED_BY="test-operator" OMEGA_AUDIT_KNOWN_HOSTS="$KNOWN_HOSTS"
if PATH="$T0/bin:$PATH" bash "$AUDIT" --target "admin@chr-lab" --fingerprint "$FINGERPRINT" --identity "$IDENTITY_VALID" --allow-live-audit --timeout 2 >/dev/null 2>&1; then
  bad "AUD-14 failed SSH was accepted as PASS"
else
  ok "AUD-14 SSH failure exits nonzero"
fi
# AUD-15: mismatched fingerprint must fail before any SSH command.
if PATH="$T0/bin:$PATH" bash "$AUDIT" --target "admin@chr-lab" --fingerprint 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' --identity "$IDENTITY_VALID" --allow-live-audit --timeout 2 >/dev/null 2>&1; then
  bad "AUD-15 mismatched host-key accepted"
else
  ok "AUD-15 mismatched fingerprint rejected"
fi
unset OMEGA_ALLOW_LIVE_AUDIT OMEGA_AUDIT_AUTHORIZED_BY OMEGA_AUDIT_KNOWN_HOSTS

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
if grep -Fq 'StrictHostKeyChecking=yes' "$AUDIT" && grep -Fq 'UserKnownHostsFile=' "$AUDIT" && grep -Fq 'KNOWN_HOSTS' "$AUDIT" && ! grep -Fq 'UserKnownHostsFile=/dev/null' "$AUDIT"; then
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
