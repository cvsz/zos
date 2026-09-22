#!/usr/bin/env bash
# Restore drill for disposable CHR only (P0-3). Never restores to production.
# Verifies manifest integrity, checksums, provenance and password availability
# before any restore; requires isolated CHR target, recovery-capable
# management path and explicit authorization. Mock mode produces MOCK PASS
# evidence without touching any router. Live restore without CHR stays BLOCKED.
set -Euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: tools/restore-drill.sh --backup-id <id> [options]

Options:
  --backup-id <id>        Backup identifier (omega-policedbc-...), required
  --backup-dir <dir>      Directory holding backup artifacts (default: $ROOT/backups)
  --password-dir <dir>    Directory holding backup passwords (default: $ROOT/state/backup-secrets)
  --target <user@host>    Isolated CHR management target (required for live)
  --allow-live-restore    Explicit live-restore opt-in flag (required for live)
  --mock                  Run fully mocked drill without network (default if no --target)
  --evidence-dir <dir>    Evidence output dir (default: artifacts/restore-drill)
  --help                  Show this help
EOF
}

BACKUP_ID=""
BACKUP_DIR=""
PASSWORD_DIR=""
TARGET=""
ALLOW_LIVE=0
MOCK=0
EVIDENCE_DIR=""

while (($# > 0)); do
  case "$1" in
    --backup-id) BACKUP_ID="${2:-}"; shift 2 ;;
    --backup-dir) BACKUP_DIR="${2:-}"; shift 2 ;;
    --password-dir) PASSWORD_DIR="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --allow-live-restore) ALLOW_LIVE=1; shift ;;
    --mock) MOCK=1; shift ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$BACKUP_ID" ]] || { echo 'ERROR: --backup-id is required' >&2; exit 2; }
BACKUP_DIR="${BACKUP_DIR:-${OMEGA_BACKUP_DIR:-$ROOT/backups}}"
PASSWORD_DIR="${PASSWORD_DIR:-${OMEGA_BACKUP_PASSWORD_DIR:-$ROOT/state/backup-secrets}}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/artifacts/restore-drill}"

# Production blocklist: never restore to these, even with authorization.
PROD_BLOCKLIST=("192.168.1.1" "192.168.1.100" "192.168.1.122" "192.168.1.123" "core.zeaz.dev" "prod.zeaz.dev")
for blocked in "${PROD_BLOCKLIST[@]}"; do
  if [[ -n "$TARGET" && "$TARGET" == *"$blocked"* ]]; then
    echo "ERROR: restore target matches production blocklist ($blocked); refusing even with authorization" >&2
    exit 3
  fi
done

RSC="$BACKUP_DIR/$BACKUP_ID.rsc"
BIN="$BACKUP_DIR/$BACKUP_ID.backup"
MANIFEST="$BACKUP_DIR/$BACKUP_ID.manifest.json"
RSC_SHA="$BACKUP_DIR/$BACKUP_ID.rsc.sha256"
BIN_SHA="$BACKUP_DIR/$BACKUP_ID.backup.sha256"

START_MS="$(date +%s%3N 2>/dev/null || date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMIT_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
RUN_ID="$(printf '%s-%s' "$BACKUP_ID" "$START_MS")"

mkdir -p "$EVIDENCE_DIR"
chmod 700 "$EVIDENCE_DIR" 2>/dev/null || true
EVIDENCE_FILE="$EVIDENCE_DIR/manifest-$BACKUP_ID.json"

# ห้าม leak secret: ปิด tracing รอบ password handling
XTRACE_WAS_ON=0
if [[ $- == *x* ]]; then XTRACE_WAS_ON=1; fi
set +x

fail_closed() {
  local msg="$1"
  local elapsed_ms="$2"
  echo "ERROR: $msg" >&2
  {
    printf '{\n  "run_id": "%s",\n  "commit_sha": "%s",\n' "$RUN_ID" "$COMMIT_SHA"
    printf '  "backup_id": "%s",\n  "started_at": "%s",\n' "$BACKUP_ID" "$START_ISO"
    printf '  "completed_at": "%s",\n  "elapsed_ms": %s,\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$elapsed_ms"
    printf '  "status": "FAIL",\n  "error": "%s",\n' "$msg"
    printf '  "live_restore_attempted": false\n}\n'
  } > "$EVIDENCE_FILE"
  chmod 600 "$EVIDENCE_FILE" 2>/dev/null || true
  if (( XTRACE_WAS_ON )); then set -x; fi
  return 1
}

elapsed_now() {
  local now_ms
  now_ms="$(date +%s%3N 2>/dev/null || date +%s)"
  if [[ "$START_MS" =~ ^[0-9]+$ && "$now_ms" =~ ^[0-9]+$ && ${#START_MS} -gt 10 ]]; then
    printf '%s' "$(( now_ms - START_MS ))"
  else
    printf '%s' "$(( ($(date +%s) - ${START_MS:0:10}) * 1000 ))"
  fi
}

# 1. ตรวจสอบ manifest + provenance + checksum ก่อน restore ใดๆ
[[ -s "$MANIFEST" ]] || { fail_closed "backup manifest is missing or empty ($MANIFEST)" "$(elapsed_now)"; exit 1; }
if ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("backup_id"); assert len(d.get("artifacts",[]))==2' "$MANIFEST" 2>/dev/null; then
  fail_closed "backup manifest integrity check failed (invalid JSON or missing backup_id/artifacts)" "$(elapsed_now)"; exit 1
fi
[[ -s "$RSC" ]] || { fail_closed "export artifact missing or empty ($RSC); both artifacts required" "$(elapsed_now)"; exit 1; }
[[ -s "$BIN" ]] || { fail_closed "binary artifact missing or empty ($BIN); both artifacts required" "$(elapsed_now)"; exit 1; }
if ! (cd "$BACKUP_DIR" && sha256sum -c "$(basename "$RSC_SHA")" >/dev/null 2>&1); then
  fail_closed "export checksum mismatch (not restoring unverified backup)" "$(elapsed_now)"; exit 1
fi
if ! (cd "$BACKUP_DIR" && sha256sum -c "$(basename "$BIN_SHA")" >/dev/null 2>&1); then
  fail_closed "binary checksum mismatch (not restoring unverified backup)" "$(elapsed_now)"; exit 1
fi

# 2. ตรวจสอบ password availability (อ่านเฉพาะ existence/size ไม่พิมพ์ content)
PASSWORD_BASENAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("password_file",""))' "$MANIFEST" 2>/dev/null || true)"
[[ -n "$PASSWORD_BASENAME" ]] || { fail_closed "manifest missing password_file provenance" "$(elapsed_now)"; exit 1; }
PASSWORD_FILE="$PASSWORD_DIR/$PASSWORD_BASENAME"
[[ -s "$PASSWORD_FILE" ]] || { fail_closed "backup password unavailable ($PASSWORD_FILE missing or empty); refusing restore" "$(elapsed_now)"; exit 1; }
if ! grep -Eq '^[A-Za-z0-9_-]{24,}$' "$PASSWORD_FILE" 2>/dev/null; then
  fail_closed "backup password format invalid (refusing restore without valid secret)" "$(elapsed_now)"; exit 1
fi

RSC_SHA_VAL="$(sha256sum "$RSC" | awk '{print $1}')"
BIN_SHA_VAL="$(sha256sum "$BIN" | awk '{print $1}')"

# 3. Mock drill: ไม่แตะ network ใดๆ ผลิต MOCK PASS evidence
if (( MOCK )) || [[ -z "$TARGET" ]]; then
  ELAPSED="$(elapsed_now)"
  {
    printf '{\n  "run_id": "%s",\n  "commit_sha": "%s",\n' "$RUN_ID" "$COMMIT_SHA"
    printf '  "backup_id": "%s",\n  "started_at": "%s",\n' "$BACKUP_ID" "$START_ISO"
    printf '  "completed_at": "%s",\n  "elapsed_ms": %s,\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ELAPSED"
    printf '  "status": "MOCK PASS",\n'
    printf '  "mode": "mock",\n'
    printf '  "checks": {"manifest_integrity": true, "checksums": true, "provenance": true, "password_available": true},\n'
    printf '  "artifacts": [{"name": "%s", "sha256": "%s"}, {"name": "%s", "sha256": "%s"}],\n' "$(basename "$RSC")" "$RSC_SHA_VAL" "$(basename "$BIN")" "$BIN_SHA_VAL"
    printf '  "live_restore_attempted": false,\n'
    printf '  "note": "CHR live restore BLOCKED (no isolated CHR); mock drill only, not proof of recoverability"\n}\n'
  } > "$EVIDENCE_FILE"
  chmod 600 "$EVIDENCE_FILE"
  if (( XTRACE_WAS_ON )); then set -x; fi
  echo "Mock restore drill PASS for $BACKUP_ID (elapsed ${ELAPSED}ms); evidence: $EVIDENCE_FILE"
  echo "Live CHR restore remains BLOCKED until an isolated disposable CHR is authorized."
  exit 0
fi

# 4. Live path: ต้องมี authorization ครบ + isolated CHR + recovery path
if (( ALLOW_LIVE == 0 )) || [[ "${OMEGA_ALLOW_LIVE_RESTORE:-0}" != "1" ]]; then
  fail_closed "live restore requires --allow-live-restore AND OMEGA_ALLOW_LIVE_RESTORE=1 (fail-closed)" "$(elapsed_now)"; exit 3
fi
if [[ "${OMEGA_CHR_ISOLATED:-0}" != "1" ]]; then
  fail_closed "live restore requires OMEGA_CHR_ISOLATED=1 proving a disposable isolated CHR target" "$(elapsed_now)"; exit 3
fi
if [[ -z "${OMEGA_CHR_AUTHORIZED_BY:-}" ]]; then
  fail_closed "live restore requires OMEGA_CHR_AUTHORIZED_BY=<operator> explicit authorization" "$(elapsed_now)"; exit 3
fi

# recovery-capable management path: พิสูจน์ SSH ก่อน restore
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$TARGET" '/system identity print' >/dev/null 2>&1; then
  fail_closed "CHR management path not proven before restore (ssh failed); refusing" "$(elapsed_now)"; exit 3
fi

# Live restore ยังไม่ implement เต็ม (ต้องมี CHR จริง + Safe Mode + reboot gates)
ELAPSED="$(elapsed_now)"
{
  printf '{\n  "run_id": "%s",\n  "commit_sha": "%s",\n' "$RUN_ID" "$COMMIT_SHA"
  printf '  "backup_id": "%s",\n  "started_at": "%s",\n' "$BACKUP_ID" "$START_ISO"
  printf '  "completed_at": "%s",\n  "elapsed_ms": %s,\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ELAPSED"
  printf '  "status": "BLOCKED",\n  "mode": "live-gated",\n'
  printf '  "target": "%s",\n' "$TARGET"
  printf '  "live_restore_attempted": false,\n'
  printf '  "note": "Authorization gates passed but no verified CHR execution path yet; no mutation performed"\n}\n'
} > "$EVIDENCE_FILE"
chmod 600 "$EVIDENCE_FILE"
if (( XTRACE_WAS_ON )); then set -x; fi
echo "Restore drill BLOCKED: authorization gates passed for $TARGET but no verified CHR execution path; no mutation performed." >&2
echo "Evidence: $EVIDENCE_FILE"
exit 4
