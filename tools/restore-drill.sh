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
[[ "$BACKUP_ID" =~ ^omega-policedbc-[A-Za-z0-9_-]+$ ]] || { echo 'ERROR: invalid backup identifier' >&2; exit 2; }
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
# shellcheck disable=SC2034
RSC_SHA="$BACKUP_DIR/$BACKUP_ID.rsc.sha256"  # retained for manifest reference
# shellcheck disable=SC2034
BIN_SHA="$BACKUP_DIR/$BACKUP_ID.backup.sha256"  # retained for manifest reference

START_MS="$(date +%s%3N 2>/dev/null || date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMIT_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
RUN_ID="$(printf '%s-%s-%s-%s' "$BACKUP_ID" "$START_MS" "$" "$RANDOM")"

umask 077
mkdir -p "$EVIDENCE_DIR"
chmod 700 "$EVIDENCE_DIR" 2>/dev/null || true
EVIDENCE_FILE="$EVIDENCE_DIR/manifest-$RUN_ID.json"

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

# Verify canonical backup manifest against the actual requested files, never sidecars.
[[ -s "$MANIFEST" && -s "$RSC" && -s "$BIN" ]] || {
  fail_closed "backup manifest or required artifact missing" "$(elapsed_now)"
  exit 1
}
if ! python3 - "$MANIFEST" "$BACKUP_ID" "$RSC" "$BIN" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

manifest_file, expected_id, rsc_file, bin_file = sys.argv[1:]
with open(manifest_file, encoding="utf-8") as stream:
    manifest = json.load(stream)
assert manifest.get("backup_id") == expected_id, "backup identifier mismatch"
for required in ("commit_sha", "created_at", "router_host"):
    assert isinstance(manifest.get(required), str) and manifest[required].strip(), "missing provenance"
assert manifest.get("password_file") == expected_id + ".backup.password", "password file mismatch"
records = manifest.get("artifacts")
assert isinstance(records, list) and len(records) == 2, "expected exactly two artifacts"
expected = {Path(rsc_file).name: Path(rsc_file), Path(bin_file).name: Path(bin_file)}
names = [record.get("name") for record in records if isinstance(record, dict)]
assert len(names) == 2 and set(names) == set(expected), "artifact filenames mismatch"
for record in records:
    assert isinstance(record, dict), "invalid artifact record"
    assert isinstance(record.get("sha256"), str) and re.fullmatch(r"[a-fA-F0-9]{64}", record["sha256"]), "invalid SHA-256"
    assert type(record.get("bytes")) is int and record["bytes"] > 0, "invalid byte count"
    artifact = expected[record["name"]]
    assert artifact.is_file() and artifact.stat().st_size == record["bytes"], "artifact size mismatch"
    digest = hashlib.sha256()
    with artifact.open("rb") as source:
        for chunk in iter(lambda: source.read(1048576), b""):
            digest.update(chunk)
    assert digest.hexdigest() == record["sha256"].lower(), "artifact checksum mismatch"
PY
then
  fail_closed "backup provenance, bytes or checksum mismatch" "$(elapsed_now)"
  exit 1
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

# No live SSH or restoration is attempted until independent isolated-CHR evidence exists.
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
