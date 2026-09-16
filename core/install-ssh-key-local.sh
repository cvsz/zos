#!/usr/bin/env bash
set -Eeuo pipefail

SSH_DIR="$HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

echo "========================================"
echo " CORE SSH Public Key Installer"
echo " User: $USER"
echo " Home: $HOME"
echo "========================================"
echo
echo "Paste ONE public key line below."
echo "Example:"
echo "ssh-ed25519 AAAAC3... cvsz@Win11ENT"
echo
read -r -p "Public key: " PUBKEY

if [[ -z "$PUBKEY" ]]; then
    echo "ERROR: public key is empty"
    exit 1
fi

if [[ ! "$PUBKEY" =~ ^ssh-ed25519[[:space:]]+ ]]; then
    echo "ERROR: expected an ssh-ed25519 public key"
    exit 1
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

touch "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"

if grep -qxF "$PUBKEY" "$AUTHORIZED_KEYS"; then
    echo
    echo "Key already exists."
else
    printf '%s\n' "$PUBKEY" >> "$AUTHORIZED_KEYS"
    echo
    echo "Key added successfully."
fi

chown -R "$USER":"$(id -gn)" "$SSH_DIR"

echo
echo "=== Permissions ==="
ls -ld "$SSH_DIR"
ls -l "$AUTHORIZED_KEYS"

echo
echo "=== Installed key fingerprints ==="
ssh-keygen -lf "$AUTHORIZED_KEYS" || true

echo
echo "=== Effective SSH configuration ==="
sudo sshd -T | grep -E \
'^(pubkeyauthentication|passwordauthentication|authorizedkeysfile|permitrootlogin)' || true

echo
echo "========================================"
echo "DONE"
echo "Test from Windows PowerShell:"
echo
echo 'ssh -i "C:\Users\cvsz\.ssh\id_ed25519_Win11ENT" -o IdentitiesOnly=yes -o PasswordAuthentication=no cvsz@192.168.1.123'
echo "========================================"
