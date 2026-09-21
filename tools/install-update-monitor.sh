#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR=/opt/zeaz-mikrotik
ETC_DIR=/etc/zeaz-mikrotik
SECRET_DIR=/var/lib/zeaz-mikrotik/secrets

sudo install -d -m 0755 "$INSTALL_DIR" "$INSTALL_DIR/tools" "$INSTALL_DIR/state" "$INSTALL_DIR/backups" "$ETC_DIR"
sudo install -d -m 0700 "$SECRET_DIR"
sudo install -m 0755 "$ROOT/tools/omega-router.sh" "$INSTALL_DIR/tools/omega-router.sh"
sudo install -m 0755 "$ROOT/tools/routeros-auto-update.sh" "$INSTALL_DIR/tools/routeros-auto-update.sh"

if [[ -f "$ROOT/config/topology.env" ]]; then
  sudo install -m 0600 "$ROOT/config/topology.env" "$ETC_DIR/topology.env"
else
  sudo install -m 0600 "$ROOT/config/topology.env.example" "$ETC_DIR/topology.env"
  echo "Installed template config to $ETC_DIR/topology.env; fill notification URL/token and verify topology before enabling auto-update."
fi

sudo install -m 0644 "$ROOT/systemd/omega-routeros-update.service" /etc/systemd/system/omega-routeros-update.service
sudo install -m 0644 "$ROOT/systemd/omega-routeros-update.timer" /etc/systemd/system/omega-routeros-update.timer
sudo systemctl daemon-reload
sudo systemctl enable --now omega-routeros-update.timer

cat <<'EOF'
RouterOS update monitor installed.

Check timer:
  systemctl status omega-routeros-update.timer
  systemctl list-timers omega-routeros-update.timer

Run an immediate safe check:
  sudo systemctl start omega-routeros-update.service
  journalctl -u omega-routeros-update.service -n 100 --no-pager

Default behavior is check + notify only.
Automatic RouterOS install requires BOTH:
  OMEGA_AUTO_ROUTEROS_UPDATE=1
  OMEGA_ALLOW_ROUTER_REBOOT=1
in /etc/zeaz-mikrotik/topology.env.
EOF
