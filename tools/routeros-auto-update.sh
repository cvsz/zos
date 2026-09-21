#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${OMEGA_ENV_FILE:-$ROOT/config/topology.env}"
[[ -f "$ENV_FILE" ]] || ENV_FILE="$ROOT/config/topology.env.example"
# shellcheck disable=SC1090
source "$ENV_FILE"

ROUTER_CTL="$ROOT/tools/omega-router.sh"
STATE_DIR="$ROOT/state/routeros-update"
mkdir -p "$STATE_DIR"

MODE="${1:-check}"
REQUESTED_CHANNEL="${ROUTEROS_UPDATE_CHANNEL:-stable}"
AUTO_UPDATE="${OMEGA_AUTO_ROUTEROS_UPDATE:-0}"
NOTIFY_URL="${ROUTEROS_UPDATE_NOTIFY_URL:-}"
NOTIFY_TOKEN="${ROUTEROS_UPDATE_NOTIFY_TOKEN:-}"
ALLOW_REBOOT="${OMEGA_ALLOW_ROUTER_REBOOT:-0}"

log(){ printf '[routeros-update] %s\n' "$*"; }
die(){ printf '[routeros-update] ERROR: %s\n' "$*" >&2; exit 1; }

router_cmd() {
  local cmd="$1"
  ssh -o BatchMode=yes -o ConnectTimeout=8 \
      -o ServerAliveInterval=20 -o ServerAliveCountMax=3 \
      "${ROUTER_SSH_USER}@${ROUTER_HOST}" "$cmd"
}

collect_update_state() {
  local raw installed latest status channel identity board arch version
  raw="$(router_cmd '/system package update check-for-updates once; /system package update print')"
  printf '%s\n' "$raw" > "$STATE_DIR/update.txt"
  installed="$(sed -n 's/^[[:space:]]*installed-version:[[:space:]]*//p' <<<"$raw" | tail -1)"
  latest="$(sed -n 's/^[[:space:]]*latest-version:[[:space:]]*//p' <<<"$raw" | tail -1)"
  status="$(sed -n 's/^[[:space:]]*status:[[:space:]]*//p' <<<"$raw" | tail -1)"
  channel="$(sed -n 's/^[[:space:]]*channel:[[:space:]]*//p' <<<"$raw" | tail -1)"
  [[ -n "$channel" ]] || die 'RouterOS did not report the current update channel'
  [[ "$channel" == "$REQUESTED_CHANNEL" ]] || die "configured RouterOS update channel is '$channel', requested '$REQUESTED_CHANNEL'; refusing to mutate channel during check"
  identity="$(router_cmd ':put [/system identity get name]' | tr -d '\r')"
  board="$(router_cmd ':put [/system resource get board-name]' | tr -d '\r')"
  arch="$(router_cmd ':put [/system resource get architecture-name]' | tr -d '\r')"
  version="$(router_cmd ':put [/system resource get version]' | tr -d '\r')"
  jq -n \
    --arg event "routeros_update_check" --arg router "$identity" --arg host "$ROUTER_HOST" \
    --arg board "$board" --arg architecture "$arch" --arg running_version "$version" \
    --arg installed_version "$installed" --arg latest_version "$latest" --arg status "$status" \
    --arg channel "$channel" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson update_available "$([[ -n "$latest" && -n "$installed" && "$latest" != "$installed" ]] && echo true || echo false)" \
    '{event:$event,router:$router,host:$host,board:$board,architecture:$architecture,running_version:$running_version,installed_version:$installed_version,latest_version:$latest_version,status:$status,channel:$channel,update_available:$update_available,checked_at:$checked_at}' \
    | tee "$STATE_DIR/latest.json"
}

notify_server() {
  [[ -n "$NOTIFY_URL" ]] || { log 'ROUTEROS_UPDATE_NOTIFY_URL not set; notification skipped'; return 0; }
  local curl_args=(--fail --silent --show-error --connect-timeout 10 --max-time 20 -H 'Content-Type: application/json' --data-binary "@$STATE_DIR/latest.json")
  [[ -z "$NOTIFY_TOKEN" ]] || curl_args+=(-H "Authorization: Bearer $NOTIFY_TOKEN")
  curl "${curl_args[@]}" "$NOTIFY_URL"
  printf '\n'
}

update_available() { jq -e '.update_available == true' "$STATE_DIR/latest.json" >/dev/null; }

perform_update() {
  [[ "$AUTO_UPDATE" == "1" ]] || { log 'update found, but OMEGA_AUTO_ROUTEROS_UPDATE=0; notification only'; return 0; }
  [[ "$ALLOW_REBOOT" == "1" ]] || die 'auto-update requires OMEGA_ALLOW_ROUTER_REBOOT=1 because RouterOS install reboots the router'
  "$ROUTER_CTL" backup
  "$ROUTER_CTL" verify
  local before after expected install_rc
  expected="$(jq -r '.latest_version // empty' "$STATE_DIR/latest.json")"
  [[ -n "$expected" ]] || die 'latest RouterOS version is unknown; refusing unattended install'
  before="$(router_cmd ':put [/system resource get version]' | tr -d '\r')"
  log "installing RouterOS update from $before; router will reboot"
  set +e
  router_cmd '/system package update install'
  install_rc=$?
  set -e
  if (( install_rc != 0 && install_rc != 255 )); then die "RouterOS update command failed with exit status $install_rc"; fi
  local i
  for i in $(seq 1 60); do
    sleep 10
    if "$ROUTER_CTL" status >/dev/null 2>&1; then
      after="$(router_cmd ':put [/system resource get version]' | tr -d '\r')"
      [[ "$after" != "$before" ]] || die "RouterOS update did not change the running version (still $after)"
      [[ "$after" == "$expected" ]] || die "RouterOS returned with version $after, expected advertised version $expected"
      collect_update_state >/dev/null
      notify_server || true
      "$ROUTER_CTL" verify
      log "RouterOS update succeeded: $before -> $after"
      return 0
    fi
    log "waiting for router reboot ($i/60)"
  done
  die 'router did not become reachable within 10 minutes after update'
}

case "$MODE" in
  check) collect_update_state ;;
  notify) collect_update_state >/dev/null; notify_server ;;
  check-and-update)
    collect_update_state >/dev/null
    notify_server || true
    if update_available; then perform_update; else log 'no RouterOS update available'; fi
    ;;
  *) echo "Usage: $0 {check|notify|check-and-update}" >&2; exit 2 ;;
esac
