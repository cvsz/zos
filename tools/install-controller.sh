#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/omega_mikrotik"

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-client git jq curl ca-certificates shellcheck
mkdir -p "$BIN_DIR" "$SSH_DIR" "$ROOT/backups" "$ROOT/state"
chmod 700 "$SSH_DIR"

if [[ ! -f "$KEY" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$KEY" -C 'omega-core-to-policedbc'
fi
chmod 600 "$KEY"
chmod 644 "$KEY.pub"

cat > "$BIN_DIR/omega-mikrotik" <<EOF
#!/usr/bin/env bash
exec "$ROOT/tools/omega-router.sh" "\$@"
EOF
chmod 700 "$BIN_DIR/omega-mikrotik"

if [[ ! -f "$ROOT/config/topology.env" ]]; then
  cp "$ROOT/config/topology.env.example" "$ROOT/config/topology.env"
  chmod 600 "$ROOT/config/topology.env"
fi

if grep -q '^ROUTER_SSH_KEY=

if ! grep -q 'HOME/.local/bin' "$HOME/.profile" 2>/dev/null; then
  cat >> "$HOME/.profile" <<'EOF'

export PATH="$HOME/.local/bin:$PATH"
EOF
fi

cat <<EOF
Controller installed.

Public key to import on MikroTik:
  $KEY.pub

Next:
  cat "$KEY.pub"
  source ~/.profile
  omega-mikrotik status

The installer does not modify the live router and does not store passwords.
EOF
 "$ROOT/config/topology.env"; then
  sed -i "s|^ROUTER_SSH_KEY=$|ROUTER_SSH_KEY=$KEY|" "$ROOT/config/topology.env"
elif ! grep -q '^ROUTER_SSH_KEY=' "$ROOT/config/topology.env"; then
  printf 'ROUTER_SSH_KEY=%s\n' "$KEY" >> "$ROOT/config/topology.env"
fi

if ! grep -q 'HOME/.local/bin' "$HOME/.profile" 2>/dev/null; then
  cat >> "$HOME/.profile" <<'EOF'

export PATH="$HOME/.local/bin:$PATH"
EOF
fi

cat <<EOF
Controller installed.

Public key to import on MikroTik:
  $KEY.pub

Next:
  cat "$KEY.pub"
  source ~/.profile
  omega-mikrotik status

The installer does not modify the live router and does not store passwords.
EOF
