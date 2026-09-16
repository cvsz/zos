#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-status}"
LAN_IFACE="${LAN_IFACE:-ens33}"
WG_IFACE="${WG_IFACE:-policedbc}"
LAN_CIDR="${LAN_CIDR:-192.168.1.0/24}"
GW="${GW:-192.168.1.1}"

show_state() {
  echo '=== links ==='
  ip -br link
  echo '=== addresses ==='
  ip -br addr
  echo '=== routes ==='
  ip route
  echo '=== route decisions ==='
  ip route get "$GW" || true
  ip route get 1.1.1.1 || true
  echo '=== wireguard ==='
  wg show 2>/dev/null || true
  echo '=== networkd ==='
  networkctl status "$LAN_IFACE" --no-pager 2>/dev/null || true
}

check() {
  show_state
  local carrier=unknown
  [[ -r "/sys/class/net/$LAN_IFACE/carrier" ]] && carrier="$(cat "/sys/class/net/$LAN_IFACE/carrier" 2>/dev/null || true)"
  echo "carrier=$carrier"

  if ip route | grep -qE "^${LAN_CIDR//./\.} dev ${WG_IFACE}([[:space:]]|$)"; then
    echo "ERROR: physical LAN route is incorrectly installed on $WG_IFACE" >&2
    return 10
  fi
  if [[ "$carrier" != "1" ]]; then
    echo "ERROR: $LAN_IFACE has no carrier; fix VMware Bridged/VMnet0 first" >&2
    return 11
  fi
  if ! ip route get "$GW" 2>/dev/null | grep -q "dev $LAN_IFACE"; then
    echo "ERROR: gateway $GW is not routed via $LAN_IFACE" >&2
    return 12
  fi
  echo 'CORE network routing looks structurally correct.'
}

repair_runtime() {
  [[ -r "/sys/class/net/$LAN_IFACE/carrier" ]] || { echo "Missing $LAN_IFACE" >&2; exit 20; }
  [[ "$(cat "/sys/class/net/$LAN_IFACE/carrier" 2>/dev/null || echo 0)" == "1" ]] || {
    echo "Refusing repair: $LAN_IFACE has no carrier. Fix VMware bridge first." >&2
    exit 21
  }

  sudo ip link set "$LAN_IFACE" up
  sudo ip route del "$LAN_CIDR" dev "$WG_IFACE" 2>/dev/null || true
  sudo networkctl reconfigure "$LAN_IFACE" || true
  sudo networkctl renew "$LAN_IFACE" || true
  sleep 4
  show_state

  ip route get "$GW" | grep -q "dev $LAN_IFACE" || {
    echo "Repair incomplete: $GW still not routed via $LAN_IFACE" >&2
    exit 22
  }

  ping -c 3 "$GW"
  ping -c 3 1.1.1.1
  getent hosts cloudflare.com
}

find_persistent_conflict() {
  local conf found=0
  local -a configs=()

  echo '=== active WireGuard AllowedIPs configuration ==='

  mapfile -t configs < <(sudo find /etc/wireguard -maxdepth 1 -name '*.conf' 2>/dev/null || true)

  if (("${#configs[@]}" == 0)); then
    echo 'No active /etc/wireguard/*.conf files found.'
    return 0
  fi

  for conf in "${configs[@]}"; do
    echo "--- $conf"
    sudo grep -nE '^[[:space:]]*AllowedIPs[[:space:]]*=' "$conf" 2>/dev/null || true

    if sudo grep -E '^[[:space:]]*AllowedIPs[[:space:]]*=' "$conf" 2>/dev/null | grep -Fq "$LAN_CIDR"; then
      echo "ERROR: physical LAN $LAN_CIDR is present in AllowedIPs in $conf" >&2
      found=1
    fi
  done

  echo
  if ((found != 0)); then
    echo "The physical LAN $LAN_CIDR must not be an AllowedIPs route on the CORE $WG_IFACE tunnel." >&2
    return 13
  fi

  echo "PASS: no active WireGuard config routes physical LAN $LAN_CIDR through $WG_IFACE."
  echo 'Backup files are intentionally ignored by this check.'
}

case "$MODE" in
  status) show_state ;;
  check) check ;;
  repair-runtime) repair_runtime ;;
  find-conflict) find_persistent_conflict ;;
  *) echo "Usage: $0 {status|check|repair-runtime|find-conflict}" >&2; exit 2 ;;
esac
