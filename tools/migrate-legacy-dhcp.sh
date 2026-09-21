#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/tools/omega-router.sh"
MIGRATION="$ROOT/migrations/20260921-legacy-dhcp-quarantine.rsc"

[[ -f "$MIGRATION" ]] || { echo "Migration file not found: $MIGRATION" >&2; exit 2; }
[[ "${OMEGA_ALLOW_LEGACY_DHCP_MIGRATION:-0}" == "1" ]] || {
  echo "Legacy DHCP migration blocked: set OMEGA_ALLOW_LEGACY_DHCP_MIGRATION=1 after reviewing the live inspection evidence." >&2
  exit 3
}
[[ "${OMEGA_ALLOW_LIVE_APPLY:-0}" == "1" ]] || {
  echo "Legacy DHCP migration blocked: OMEGA_ALLOW_LIVE_APPLY=1 is also required." >&2
  exit 3
}

echo "Validating repository safety before legacy DHCP quarantine..."
"$ROOT/tools/validate-repo.sh"
python3 "$ROOT/tools/validate-docs.py"

echo "Backing up RouterOS before legacy DHCP quarantine..."
"$CTL" backup

echo "Syntax dry-run of guarded legacy DHCP migration..."
"$CTL" dry-run "$MIGRATION"

echo "Applying guarded legacy DHCP quarantine in RouterOS Safe Mode..."
"$CTL" apply-safe "$MIGRATION"

echo "Read-only post-migration legacy DHCP status..."
"$CTL" legacy-dhcp-status

echo "Legacy DHCP quarantine migration completed. Run a fresh production make dry-run before make apply."
