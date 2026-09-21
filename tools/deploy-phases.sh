#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/tools/omega-router.sh"
PHASES=(
  00-PRECHECK.rsc
  10-BACKUP-SNAPSHOT.rsc
  20-NETWORK-NORMALIZE.rsc
  30-DHCP-DNS-NTP.rsc
  40-WIREGUARD-SERVICES.rsc
  50-FIREWALL-NAT.rsc
  60-OBSERVABILITY.rsc
  90-EXPORT-EVIDENCE.rsc
  99-VERIFY-HEALTH.rsc
)

mode="${1:-dry-run}"
STATE_DIR="${OMEGA_STATE_DIR:-$ROOT/state/deploy}"
DRY_RUN_MARKER="$STATE_DIR/dry-run.success"
TOPOLOGY_FILE="${OMEGA_ENV_FILE:-$ROOT/config/topology.env}"
[[ -f "$TOPOLOGY_FILE" ]] || TOPOLOGY_FILE="$ROOT/config/topology.env.example"
DRY_RUN_MAX_AGE_SECONDS="${OMEGA_DRY_RUN_MAX_AGE_SECONDS:-3600}"

phase_manifest() {
  local f hash
  for f in "${PHASES[@]}"; do
    hash="$(sha256sum "$ROOT/$f" | awk '{print $1}')"
    printf '%s  %s\n' "$hash" "$f"
  done
}

topology_hash() {
  sha256sum "$TOPOLOGY_FILE" | awk '{print $1}'
}

git_commit() {
  git -C "$ROOT" rev-parse HEAD
}

target_fingerprint() {
  "$CTL" fingerprint | tr -d '\r'
}

record_dry_run_success() {
  mkdir -p "$STATE_DIR"
  {
    printf 'completed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'completed_epoch=%s\n' "$(date -u +%s)"
    printf 'git_commit=%s\n' "$(git_commit)"
    printf 'topology_sha256=%s\n' "$(topology_hash)"
    target_fingerprint
    printf '%s\n' '--phases--'
    phase_manifest
  } > "$DRY_RUN_MARKER"
  chmod 600 "$DRY_RUN_MARKER"
}

dry_run_is_current() {
  [[ -s "$DRY_RUN_MARKER" ]] || return 1
  [[ "$DRY_RUN_MAX_AGE_SECONDS" =~ ^[0-9]+$ ]] || return 1
  local expected actual marker_epoch now_epoch marker_git marker_topology marker_fingerprint current_fingerprint
  expected="$(mktemp)"
  actual="$(mktemp)"
  trap 'rm -f "$expected" "$actual"' RETURN

  marker_epoch="$(sed -n 's/^completed_epoch=//p' "$DRY_RUN_MARKER")"
  [[ "$marker_epoch" =~ ^[0-9]+$ ]] || return 1
  now_epoch="$(date -u +%s)"
  (( now_epoch >= marker_epoch && now_epoch - marker_epoch <= DRY_RUN_MAX_AGE_SECONDS )) || return 1

  marker_git="$(sed -n 's/^git_commit=//p' "$DRY_RUN_MARKER")"
  [[ "$marker_git" == "$(git_commit)" ]] || return 1
  marker_topology="$(sed -n 's/^topology_sha256=//p' "$DRY_RUN_MARKER")"
  [[ "$marker_topology" == "$(topology_hash)" ]] || return 1

  marker_fingerprint="$(sed -n '/^router_host=/p;/^router_identity=/p;/^router_board=/p;/^router_arch=/p;/^router_version=/p' "$DRY_RUN_MARKER")"
  current_fingerprint="$(target_fingerprint)"
  [[ "$marker_fingerprint" == "$current_fingerprint" ]] || return 1

  phase_manifest > "$expected"
  sed -n '/^[0-9a-f]\{64\}  /p' "$DRY_RUN_MARKER" > "$actual"
  cmp -s "$expected" "$actual"
}

require_flag() {
  local name="$1" value="${!1:-0}"
  [[ "$value" == 0 || "$value" == 1 ]] || { echo "$name must be 0 or 1 (got: $value)" >&2; exit 2; }
}

case "$mode" in
  dry-run)
    "$CTL" status
    "$CTL" backup
    for f in "${PHASES[@]}"; do
      echo "===== DRY RUN $f ====="
      "$CTL" dry-run "$ROOT/$f"
    done
    record_dry_run_success
    echo "All dry-runs finished successfully. RouterOS configuration was not imported."
    ;;
  apply)
    require_flag OMEGA_REQUIRE_DRY_RUN
    require_flag OMEGA_REQUIRE_SAFE_MODE
    [[ "${OMEGA_REQUIRE_DRY_RUN:-1}" == "1" ]] || {
      echo 'Apply blocked: production dry-run bypass is disabled.' >&2
      exit 3
    }
    [[ "${OMEGA_REQUIRE_SAFE_MODE:-1}" == "1" ]] || {
      echo 'Apply blocked: production Safe Mode bypass is disabled.' >&2
      exit 3
    }
    [[ "${OMEGA_ALLOW_LIVE_APPLY:-0}" == "1" ]] || {
      echo 'Apply blocked. Set OMEGA_ALLOW_LIVE_APPLY=1 only for an approved change window.' >&2
      exit 3
    }
    dry_run_is_current || {
      echo 'Apply blocked: dry-run evidence is missing, stale, targets another router/runtime, or does not match the exact current phase/config/git state.' >&2
      echo 'Run make dry-run again immediately before the approved change.' >&2
      exit 3
    }
    "$CTL" backup
    echo 'Starting one interactive RouterOS Safe Mode transaction for all production imports and in-transaction verification.'
    "$CTL" apply-safe "${PHASES[@]/#/$ROOT/}"
    "$CTL" verify
    "$CTL" fetch-export omega-policedbc-evidence || true
    "$CTL" fetch-export omega-policedbc-after || true
    ;;
  verify)
    "$CTL" verify
    ;;
  *)
    echo "Usage: $0 {dry-run|apply|verify}" >&2
    exit 2
    ;;
esac
