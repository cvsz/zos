#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${OMEGA_ENV_FILE:-$ROOT/config/topology.env}"
[[ -f "$ENV_FILE" ]] || ENV_FILE="$ROOT/config/topology.env.example"
_LIVE_APPLY="${OMEGA_ALLOW_LIVE_APPLY:-}"
# shellcheck disable=SC1090
source "$ENV_FILE"
[[ -n "$_LIVE_APPLY" ]] && OMEGA_ALLOW_LIVE_APPLY="$_LIVE_APPLY"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=20 -o ServerAliveCountMax=3)
if [[ -n "${ROUTER_SSH_KEY:-}" ]]; then
  [[ -f "$ROUTER_SSH_KEY" ]] || { echo "Configured ROUTER_SSH_KEY not found: $ROUTER_SSH_KEY" >&2; exit 2; }
  SSH_OPTS+=(-i "$ROUTER_SSH_KEY" -o IdentitiesOnly=yes)
fi
TARGET="${ROUTER_SSH_USER}@${ROUTER_HOST}"

usage() {
  cat <<'EOF'
Usage: tools/omega-router.sh <command> [args]

Commands:
  status                    Read-only router status
  audit                     Read-only full audit
  backup                    Export + encrypted binary backup, then clean router file store
  upload <file.rsc>         Upload an RSC only
  dry-run <file.rsc>        Upload a unique temporary RSC, dry-run import, then remove it
  apply <file.rsc>          Apply only when OMEGA_ALLOW_LIVE_APPLY=1
  apply-safe <files...>     Apply all files in one interactive RouterOS Safe Mode session
  verify                    Run read-only post-change verification
  fingerprint               Print stable target/config fingerprint for dry-run binding
  fetch-export <name>       Download <name>.rsc from router
EOF
}

# RouterOS commands are intentionally passed to the remote shell.
# shellcheck disable=SC2029
ssh_mt() { ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }

status() {
  ssh_mt '/system identity print; /system resource print; /ip address print; /ip route print where dst-address="0.0.0.0/0"; /interface wireguard peers print detail'
}

audit() {
  ssh_mt '/system identity print; /system resource print; /interface print; /interface bridge port print; /interface list member print; /ip address print detail; /ip route print detail; /ip dhcp-server print detail; /ip dhcp-server network print detail; /ip dhcp-server lease print detail; /interface wireguard print detail; /interface wireguard peers print detail; /ip firewall filter print detail; /ip firewall nat print detail; /ip service print detail; /log print'
}

fingerprint() {
  local env_sha
  env_sha="$(sha256sum "$ENV_FILE" | awk '{print $1}')"
  printf 'router_host=%s\n' "$ROUTER_HOST"
  printf 'router_user=%s\n' "$ROUTER_SSH_USER"
  printf 'env_sha256=%s\n' "$env_sha"
  ssh_mt ':put ("identity=" . [/system identity get name]); :put ("board=" . [/system resource get board-name]); :put ("version=" . [/system resource get version]); :put ("architecture=" . [/system resource get architecture-name])'
}

backup() {
  local stamp name password password_file password_dir
  stamp="$(date +%Y%m%d-%H%M%S)"
  name="omega-policedbc-$stamp"
  password_dir="${OMEGA_BACKUP_PASSWORD_DIR:-$ROOT/state/backup-secrets}"
  mkdir -p "$ROOT/backups" "$password_dir"
  chmod 700 "$password_dir"
  umask 077
  password="${OMEGA_BACKUP_PASSWORD:-}"
  if [[ -z "$password" ]]; then
    command -v openssl >/dev/null 2>&1 || { echo 'openssl is required to generate an encrypted backup password' >&2; exit 1; }
    password="$(openssl rand -hex 32)"
  fi
  [[ "$password" =~ ^[A-Za-z0-9_-]{24,}$ ]] || {
    echo 'OMEGA_BACKUP_PASSWORD must contain only letters, digits, _ or - and be at least 24 characters' >&2
    exit 2
  }
  password_file="$password_dir/$name.backup.password"
  printf '%s\n' "$password" > "$password_file"
  chmod 600 "$password_file"

  ssh_mt "/export terse file=$name; /system backup save name=$name encryption=aes-sha256 password=$password"
  scp "${SSH_OPTS[@]}" "$TARGET:$name.rsc" "$ROOT/backups/$name.rsc"
  scp "${SSH_OPTS[@]}" "$TARGET:$name.backup" "$ROOT/backups/$name.backup"
  ssh_mt ":foreach f in=[/file find where name=\"$name.rsc\"] do={ /file remove \$f }; :foreach f in=[/file find where name=\"$name.backup\"] do={ /file remove \$f }"
  echo "Saved $ROOT/backups/$name.rsc"
  echo "Saved encrypted binary backup $ROOT/backups/$name.backup"
  echo "Backup password saved with mode 600 at $password_file"
}

upload() {
  local file="$1"
  [[ -f "$file" ]] || { echo "File not found: $file" >&2; exit 2; }
  [[ "$file" == *.rsc ]] || { echo "Only .rsc files are supported" >&2; exit 2; }
  scp "${SSH_OPTS[@]}" "$file" "$TARGET:$(basename "$file")"
}

dry_run() {
  local file="$1" remote rc
  [[ -f "$file" ]] || { echo "File not found: $file" >&2; exit 2; }
  [[ "$file" == *.rsc ]] || { echo "Only .rsc files are supported" >&2; exit 2; }
  remote="omega-dry-run-$$-$(basename "$file")"
  scp "${SSH_OPTS[@]}" "$file" "$TARGET:$remote"
  set +e
  ssh_mt "/import file-name=$remote verbose=yes dry-run"
  rc=$?
  set -e
  ssh_mt ":foreach f in=[/file find where name=\"$remote\"] do={ /file remove \$f }" >/dev/null 2>&1 || true
  return "$rc"
}

apply_file() {
  local file="$1" remote
  [[ "${OMEGA_ALLOW_LIVE_APPLY:-0}" == "1" ]] || {
    echo "Live apply blocked. Set OMEGA_ALLOW_LIVE_APPLY=1 only after backup, dry-run and Safe Mode." >&2
    exit 3
  }
  remote="$(basename "$file")"
  upload "$file"
  ssh_mt "/import file-name=$remote verbose=yes"
}

apply_safe() {
  [[ "${OMEGA_ALLOW_LIVE_APPLY:-0}" == "1" ]] || { echo 'Live apply blocked: OMEGA_ALLOW_LIVE_APPLY=1 is required' >&2; exit 3; }
  local file remote cmd output session_rc output_file apply_state_dir lock_file lock_fd evidence_dir stamp
  (( $# > 0 )) || { echo 'apply-safe requires at least one .rsc file' >&2; exit 2; }

  apply_state_dir="${OMEGA_STATE_DIR:-$ROOT/state/deploy}"
  mkdir -p "$apply_state_dir"
  lock_file="$apply_state_dir/apply-safe.lock"
  command -v flock >/dev/null 2>&1 || { echo 'flock is required for apply-safe concurrency protection' >&2; exit 2; }
  exec {lock_fd}>"$lock_file"
  flock -n "$lock_fd" || {
    echo 'Another apply-safe session is already active on this controller; refusing concurrent RouterOS Safe Mode apply.' >&2
    exit 4
  }

  # One RouterOS :do transaction. /quit exists only on the success path.
  # On an import/assertion error, no /quit is sent; stdin closes and the
  # Safe Mode owner disconnects so RouterOS can roll back floating changes.
  cmd=':do {'
  for file in "$@"; do
    [[ -f "$file" && "$file" == *.rsc ]] || { echo "Invalid RSC file: $file" >&2; exit 2; }
    remote="$(basename "$file")"
    scp "${SSH_OPTS[@]}" "$file" "$TARGET:$remote"
    cmd+=" /import file-name=$remote verbose=yes;"
  done
  cmd+=' :put "OMEGA_APPLY_PASS"; /quit } on-error={ :put "OMEGA_PHASE_FAIL"; :error "OMEGA transactional apply failed" }'

  output_file="$(mktemp)"
  trap 'rm -f "${output_file:-}"' RETURN
  set +e
  {
    printf '\030'
    sleep 1
    printf '%s\n' "$cmd"
  } | ssh -tt "${SSH_OPTS[@]}" "$TARGET" 2>&1 | tee "$output_file"
  session_rc=${PIPESTATUS[1]}
  set -e
  output="$(cat "$output_file")"

  grep -Fq 'Hijacking Safe Mode from someone' <<<"$output" && {
    echo 'RouterOS reported an existing Safe Mode owner; no concurrent apply can be trusted. Clear the stale Safe Mode session before retrying.' >&2
    exit 4
  }

  for file in "$@"; do
    remote="$(basename "$file")"
    ssh_mt ":foreach f in=[/file find where name=\"$remote\"] do={ /file remove \\$f }" >/dev/null 2>&1 || true
  done

  (( session_rc == 0 )) || { echo 'Safe Mode apply session failed' >&2; exit 4; }
  grep -Fq '[Safe Mode taken]' <<<"$output" || {
    echo 'RouterOS did not confirm Safe Mode; refusing to treat apply as successful' >&2
    exit 4
  }
  grep -Fq 'OMEGA_APPLY_PASS' <<<"$output" || {
    echo 'RouterOS did not confirm that all production phases completed successfully' >&2
    exit 4
  }
  ! grep -Fq 'OMEGA_PHASE_FAIL' <<<"$output" || {
    echo 'At least one production phase failed inside Safe Mode' >&2
    exit 4
  }

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  evidence_dir="$ROOT/backups/evidence/$stamp"
  mkdir -p "$evidence_dir"
  for remote in omega-policedbc-evidence.rsc omega-policedbc-after.rsc; do
    if scp "${SSH_OPTS[@]}" "$TARGET:$remote" "$evidence_dir/$remote" >/dev/null 2>&1; then
      ssh_mt ":foreach f in=[/file find where name=\"$remote\"] do={ /file remove \\$f }" >/dev/null 2>&1 || true
    else
      echo "WARN: post-apply evidence file was not available: $remote" >&2
    fi
  done
}
verify() {
  ssh_mt '/system resource print; /ip address print; /ip route print where dst-address="0.0.0.0/0"; /interface wireguard print detail; /interface wireguard peers print detail; /ip dhcp-server print detail; /ip dhcp-server lease print detail where mac-address~"88:DC:96"; /ip firewall filter print stats where comment~"PoliceDBC:"; /ip firewall nat print stats where comment~"PoliceDBC:"; /ip service print; :put ("upstream_replies=" . [/ping 192.168.200.1 count=3]); :put ("internet_replies=" . [/ping 1.1.1.1 count=3]); :put ("cloudflare_dns=" . [/resolve cloudflare.com])'
}

case "${1:-}" in
  status) status ;;
  audit) audit ;;
  backup) backup ;;
  upload) [[ $# -eq 2 ]] || { usage; exit 2; }; upload "$2" ;;
  dry-run) [[ $# -eq 2 ]] || { usage; exit 2; }; dry_run "$2" ;;
  apply) [[ $# -eq 2 ]] || { usage; exit 2; }; apply_file "$2" ;;
  apply-safe) shift; apply_safe "$@" ;;
  verify) verify ;;
  fingerprint) fingerprint ;;
  fetch-export) [[ $# -eq 2 ]] || { usage; exit 2; }; mkdir -p "$ROOT/backups"; scp "${SSH_OPTS[@]}" "$TARGET:$2.rsc" "$ROOT/backups/$2.rsc" ;;
  *) usage; exit 2 ;;
esac
