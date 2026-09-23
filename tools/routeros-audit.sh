#!/usr/bin/env bash
# Read-only RouterOS audit collector (P2-1). No network mutation, ever.
#
# Reads only allowlisted read-only commands. Output is a sanitized JSON
# snapshot with secret redaction. Requires explicit audit authorization
# (OMEGA_ALLOW_LIVE_AUDIT=1 + OMEGA_AUDIT_AUTHORIZED_BY=<operator>) for
# live targets. Production targets are always refused.
#
set -Euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: tools/routeros-audit.sh --target <user@host> --fingerprint <sha256> --identity <path> [options]

Options:
  --target <user@host>      RouterOS management target (required)
  --fingerprint <sha256>     Operator-provided host key fingerprint (required)
  --identity <path>          SSH identity file path (required)
  --allow-live-audit         Explicit live audit opt-in flag (required for live)
  --timeout <seconds>        SSH timeout (default: 15)
  --output <file>            JSON output file (default: stdout)
  --help                     Show this help
EOF
}

TARGET=""
FINGERPRINT=""
IDENTITY=""
ALLOW_LIVE=0
TIMEOUT=15
OUTPUT=""

while (($# > 0)); do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --fingerprint) FINGERPRINT="${2:-}"; shift 2 ;;
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --allow-live-audit) ALLOW_LIVE=1; shift ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$TARGET" ]] || { echo 'ERROR: --target is required' >&2; exit 2; }
[[ -n "$FINGERPRINT" ]] || { echo 'ERROR: --fingerprint is required' >&2; exit 2; }
[[ -n "$IDENTITY" ]] || { echo 'ERROR: --identity is required' >&2; exit 2; }
[[ -f "$IDENTITY" ]] || { echo "ERROR: identity file not found: $IDENTITY" >&2; exit 2; }
[[ -r "$IDENTITY" ]] || { echo "ERROR: identity file not readable: $IDENTITY" >&2; exit 2; }

PROD_BLOCKLIST=("192.168.1.1" "192.168.1.100" "192.168.1.122" "192.168.1.123" "core.zeaz.dev" "prod.zeaz.dev")
for blocked in "${PROD_BLOCKLIST[@]}"; do
  if [[ -n "$TARGET" && "$TARGET" == *"$blocked"* ]]; then
    echo "ERROR: audit target matches production blocklist ($blocked); refusing even with authorization" >&2
    exit 3
  fi
done

if (( ALLOW_LIVE == 0 )) || [[ "${OMEGA_ALLOW_LIVE_AUDIT:-0}" != "1" ]]; then
  echo "ERROR: live audit requires --allow-live-audit AND OMEGA_ALLOW_LIVE_AUDIT=1 (fail-closed)" >&2
  exit 3
fi
if [[ -z "${OMEGA_AUDIT_AUTHORIZED_BY:-}" ]]; then
  echo "ERROR: live audit requires OMEGA_AUDIT_AUTHORIZED_BY=<operator> explicit authorization" >&2
  exit 3
fi

START_MS="$(date +%s%3N 2>/dev/null || date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMIT_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
RUN_ID="$(printf '%s-%s' "$(date +%s)" "$$")"

ALLOWED_COMMANDS=(
  "/system resource print"
  "/system clock print"
  "/system identity print"
  "/system routerboard print"
  "/system license print"
  "/ip address print"
  "/ip route print"
  "/ip dhcp-server print"
  "/ip dhcp-server network print"
  "/ip dhcp-server lease print"
  "/ip dns print"
  "/ip firewall filter print"
  "/ip firewall nat print"
  "/ip service print"
  "/ip user print"
  "/ip user ssh-keys print"
  "/interface print"
  "/interface ethernet print"
  "/interface bridge print"
  "/interface bridge port print"
  "/interface vlan print"
  "/interface wireguard print"
  "/interface wireguard peers print"
  "/ip cloud print"
  "/system ntp client print"
  "/system ntp server print"
)

XTRACE_WAS_ON=0
if [[ $- == *x* ]]; then XTRACE_WAS_ON=1; fi
set +x

# shellcheck disable=SC2329
fail_closed() {
  local msg="$1"
  local elapsed_ms="$2"
  echo "ERROR: $msg" >&2
  {
    printf '{\n  "run_id": "%s",\n  "commit_sha": "%s",\n' "$RUN_ID" "$COMMIT_SHA"
    printf '  "target": "%s",\n  "started_at": "%s",\n' "$TARGET" "$START_ISO"
    printf '  "completed_at": "%s",\n  "elapsed_ms": %s,\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$elapsed_ms"
    printf '  "status": "FAIL",\n  "error": "%s"\n' "$msg"
    printf '}\n'
  } > "${OUTPUT:-/dev/stdout}"
  if (( XTRACE_WAS_ON )); then set -x; fi
  return 1
}

ALLOWED_CMDS_JSON="$(printf '%s\n' "${ALLOWED_COMMANDS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"

ELAPSED="$( (date +%s%3N 2>/dev/null || date +%s) )"
ELAPSED=$(( ELAPSED - START_MS ))

RAW_RESULT="$(
  for cmd in "${ALLOWED_COMMANDS[@]}"; do
    echo "=== CMD: $cmd ==="
    ssh -o BatchMode=yes \
      -o StrictHostKeyChecking=yes \
      -o UserKnownHostsFile=/dev/null \
      -o PreferredAuthentications=publickey \
      -o IdentityFile="$IDENTITY" \
      -o ConnectTimeout="$TIMEOUT" \
      -o NumberOfPasswordPrompts=0 \
      "$TARGET" \
      "echo '__BEGIN__'; $cmd; echo '__END__'" 2>&1 || echo "(command failed or timed out)"
  done
)"

SANITIZED="$(printf '%s' "$RAW_RESULT" | python3 -c '
import json, sys, re
data = sys.stdin.read()
data = re.sub(r"(password|passwd|secret|token|private-key|PSK)\s*[:=]\s*\S+", r"\1=[REDACTED]", data, flags=re.IGNORECASE)
data = re.sub(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----", "[REDACTED PRIVATE KEY BLOCK]", data)
print(data)
')"

ESCAPED_RESULT="$(printf '%s' "$SANITIZED" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

{
  printf '{\n'
  printf '  "run_id": "%s",\n' "$RUN_ID"
  printf '  "commit_sha": "%s",\n' "$COMMIT_SHA"
  printf '  "target": "%s",\n' "$TARGET"
  printf '  "fingerprint": "%s",\n' "$FINGERPRINT"
  printf '  "started_at": "%s",\n' "$START_ISO"
  printf '  "completed_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "elapsed_ms": %s,\n' "$ELAPSED"
  printf '  "status": "PASS",\n'
  printf '  "mode": "read-only",\n'
  printf '  "live_audit": true,\n'
  printf '  "authorized_by": "%s",\n' "$OMEGA_AUDIT_AUTHORIZED_BY"
  printf '  "commands": %s,\n' "$ALLOWED_CMDS_JSON"
  printf '  "result": %s\n' "$ESCAPED_RESULT"
  printf '}\n'
} > "${OUTPUT:-/dev/stdout}"

if (( XTRACE_WAS_ON )); then set -x; fi

echo "Audit complete in ${ELAPSED}ms; target: $TARGET; authorized by: ${OMEGA_AUDIT_AUTHORIZED_BY}" >&2
exit 0
