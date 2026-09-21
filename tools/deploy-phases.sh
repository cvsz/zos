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
DRY_RUN_MAX_AGE_SECONDS="${OMEGA_DRY_RUN_MAX_AGE_SECONDS:-3600}"

phase_manifest() {
  local f
  for f in "${PHASES[@]}"; do
    sha256sum "$ROOT/$f"
  done
}

target_manifest() {
  "$CTL" fingerprint
}

record_dry_run_success() {
  mkdir -p "$STATE_DIR"
  {
    printf 'completed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'completed_epoch=%s\n' "$(date +%s)"
    printf 'git_commit=%s\n' "$(git -C "$ROOT" rev-parse HEAD)"
    target_manifest
    phase_manifest
  } > "$DRY_RUN_MARKER"
  chmod 600 "$DRY_RUN_MARKER"
}

dry_run_is_current() {
  [[ -s "$DRY_RUN_MARKER" ]] || return 1
  [[ "$DRY_RUN_MAX_AGE_SECONDS" =~ ^[0-9]+$ ]] || {
    echo 'OMEGA_DRY_RUN_MAX_AGE_SECONDS must be a non-negative integer' >&2
    return 1
  }

  local expected actual expected_target actual_target completed_epoch now_epoch marker_git
  expected="$(mktemp)"
  actual="$(mktemp)"
  expected_target="$(mktemp)"
  actual_target="$(mktemp)"
  trap 'rm -f "$expected" "$actual" "$expected_target" "$actual_target"' RETURN

  phase_manifest > "$expected"
  sed -n '/^[0-9a-f]\{64\} /p' "$DRY_RUN_MARKER" > "$actual"
  cmp -s "$expected" "$actual" || return 1

  target_manifest > "$expected_target"
  grep -E '^(router_host|router_user|env_sha256|identity|board|version|architecture)=' "$DRY_RUN_MARKER" > "$actual_target"
  cmp -s "$expected_target" "$actual_target" || return 1

  marker_git="$(sed -n 's/^git_commit=//p' "$DRY_RUN_MARKER")"
  [[ -n "$marker_git" && "$marker_git" == "$(git -C "$ROOT" rev-parse HEAD)" ]] || return 1

  completed_epoch="$(sed -n 's/^completed_epoch=//p' "$DRY_RUN_MARKER")"
  [[ "$completed_epoch" =~ ^[0-9]+$ ]] || return 1
  now_epoch="$(date +%s)"
  (( now_epoch >= completed_epoch )) || return 1
  (( now_epoch - completed_epoch <= DRY_RUN_MAX_AGE_SECONDS )) || return 1
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
      echo 'Apply blocked: production dry-run enforcement cannot be disabled.' >&2
      exit 3
    }
    [[ "${OMEGA_REQUIRE_SAFE_MODE:-1}" == "1" ]] || {
      echo 'Apply blocked: production Safe Mode enforcement cannot be disabled.' >&2
      exit 3
    }
    [[ "${OMEGA_ALLOW_LIVE_APPLY:-0}" == "1" ]] || {
      echo 'Apply blocked. Set OMEGA_ALLOW_LIVE_APPLY=1 only for an approved change window.' >&2
      exit 3
    }
    if [[ "${OMEGA_REQUIRE_DRY_RUN:-1}" == "1" ]]; then
      dry_run_is_current || {
        echo 'Apply blocked: no successful dry-run exists for the exact current phase files.' >&2
        echo 'Run make dry-run again after every phase change.' >&2
        exit 3
      }
    fi
    "$CTL" backup
    echo 'Starting one interactive RouterOS Safe Mode session for all production imports.'
    "$CTL" apply-safe "${PHASES[@]/#/$ROOT/}"
    "$CTL" verify
    ;;
  verify)
    "$CTL" verify
    ;;
  *)
    echo "Usage: $0 {dry-run|apply|verify}" >&2
    exit 2
    ;;
esac
