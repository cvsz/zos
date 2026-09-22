#!/usr/bin/env bash
# Regression tests for restore-drill (P0-3). Mocked only, no live router.
set -Euo pipefail
set +o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRILL="$ROOT/tools/restore-drill.sh"
FAIL=0
PASS=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

make_backup_set() {
  local dir="$1" pwdir="$2" id="$3"
  mkdir -p "$dir" "$pwdir"
  printf 'mock export for %s\n' "$id" > "$dir/$id.rsc"
  printf 'mock binary for %s with enough bytes to look real\n' "$id" > "$dir/$id.backup"
  (cd "$dir" && sha256sum "$id.rsc" > "$id.rsc.sha256" && sha256sum "$id.backup" > "$id.backup.sha256")
  local rsc_sha bin_sha
  rsc_sha="$(sha256sum "$dir/$id.rsc" | awk '{print $1}')"
  bin_sha="$(sha256sum "$dir/$id.backup" | awk '{print $1}')"
  cat > "$dir/$id.manifest.json" <<EOF
{"backup_id": "$id", "commit_sha": "test-commit", "created_at": "2026-09-22T00:00:00Z",
 "router_host": "chr-lab", "router_user": "admin", "router_version": "7.25",
 "artifacts": [{"name": "$id.rsc", "sha256": "$rsc_sha", "bytes": 10}, {"name": "$id.backup", "sha256": "$bin_sha", "bytes": 10}],
 "password_file": "$id.backup.password"}
EOF
  printf 'testPASSWORD-1234_ABCD-xyz-%s\n' "$id" > "$pwdir/$id.backup.password"
  # Ensure password meets format (>=24, allowed chars only)
  printf 'ABCD1234abcd1234ABCD1234xyz\n' > "$pwdir/$id.backup.password"
}

# RD-01: mock happy path produces MOCK PASS with elapsed + no secrets
T1="$(mktemp -d)"; trap 'rm -rf "$T1"' EXIT
ID1="omega-policedbc-20260922-000001-1-aabbccdd"
make_backup_set "$T1/backups" "$T1/secrets" "$ID1"
if OUT="$(bash "$DRILL" --backup-id "$ID1" --backup-dir "$T1/backups" --password-dir "$T1/secrets" --mock 2>&1)"; then
  ok "RD-01 mock drill exits 0"
  if [[ -s "$T1/backups/$ID1.rsc" ]]; then ok "RD-01 artifacts preserved (no delete of verified copy)"; else bad "RD-01 artifacts missing"; fi
else
  bad "RD-01 mock drill failed: $OUT"
fi
EV1="$ROOT/artifacts/restore-drill/manifest-$ID1.json"
if [[ -s "$EV1" ]] && grep -Fq '"status": "MOCK PASS"' "$EV1" && grep -Fq '"elapsed_ms"' "$EV1"; then
  ok "RD-01 MOCK PASS evidence with elapsed time"
else
  bad "RD-01 evidence missing MOCK PASS/elapsed"
fi
if grep -Fq "ABCD1234abcd1234ABCD1234xyz" "$EV1" 2>/dev/null; then
  bad "RD-01 evidence leaks backup password"
else
  ok "RD-01 evidence sanitized (no password)"
fi
rm -f "$EV1"
rm -rf "$T1"; trap - EXIT

# RD-02: checksum mismatch fails closed with no restore
T2="$(mktemp -d)"
make_backup_set "$T2/backups" "$T2/secrets" "$ID1"
printf 'tampered\n' >> "$T2/backups/$ID1.backup"
if OUT="$(bash "$DRILL" --backup-id "$ID1" --backup-dir "$T2/backups" --password-dir "$T2/secrets" --mock 2>&1)"; then
  bad "RD-02 tampered backup reported success"
else
  if grep -Eiq 'checksum|integrity|unverified' <<<"$OUT"; then ok "RD-02 checksum mismatch fails closed"; else bad "RD-02 wrong error: $OUT"; fi
fi
rm -rf "$T2"

# RD-03: missing password fails closed
T3="$(mktemp -d)"
make_backup_set "$T3/backups" "$T3/secrets" "$ID1"
rm -f "$T3/secrets/$ID1.backup.password"
if OUT="$(bash "$DRILL" --backup-id "$ID1" --backup-dir "$T3/backups" --password-dir "$T3/secrets" --mock 2>&1)"; then
  bad "RD-03 missing password reported success"
else
  if grep -Eiq 'password' <<<"$OUT"; then ok "RD-03 missing password fails closed"; else bad "RD-03 wrong error: $OUT"; fi
fi
rm -rf "$T3"

# RD-04: production target refused even with authorization
T4="$(mktemp -d)"
make_backup_set "$T4/backups" "$T4/secrets" "$ID1"
if OUT="$(OMEGA_ALLOW_LIVE_RESTORE=1 OMEGA_CHR_ISOLATED=1 OMEGA_CHR_AUTHORIZED_BY=test bash "$DRILL" --backup-id "$ID1" --backup-dir "$T4/backups" --password-dir "$T4/secrets" --target "admin@192.168.1.1" --allow-live-restore 2>&1)"; then
  bad "RD-04 production target allowed"
else
  if grep -Eiq 'blocklist|production' <<<"$OUT"; then ok "RD-04 production target refused"; else bad "RD-04 wrong error: $OUT"; fi
fi
rm -rf "$T4"

# RD-05: live without authorization fails closed, no mutation
T5="$(mktemp -d)"
make_backup_set "$T5/backups" "$T5/secrets" "$ID1"
if OUT="$(bash "$DRILL" --backup-id "$ID1" --backup-dir "$T5/backups" --password-dir "$T5/secrets" --target "admin@chr-lab.local" --allow-live-restore 2>&1)"; then
  bad "RD-05 unauthorized live restore allowed"
else
  if grep -Eiq 'OMEGA_ALLOW_LIVE_RESTORE|OMEGA_CHR_ISOLATED|authorization|fail-closed' <<<"$OUT"; then ok "RD-05 live without auth fails closed"; else bad "RD-05 wrong error: $OUT"; fi
fi
rm -rf "$T5"

# RD-06: missing manifest fails closed
T6="$(mktemp -d)"
make_backup_set "$T6/backups" "$T6/secrets" "$ID1"
rm -f "$T6/backups/$ID1.manifest.json"
if bash "$DRILL" --backup-id "$ID1" --backup-dir "$T6/backups" --password-dir "$T6/secrets" --mock >/dev/null 2>&1; then
  bad "RD-06 missing manifest allowed"
else
  ok "RD-06 missing manifest fails closed"
fi
rm -rf "$T6"

echo "---"
echo "restore-drill regression: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
