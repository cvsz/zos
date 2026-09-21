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
ROUTER_SSH_KEY="${ROUTER_SSH_KEY:-$HOME/.ssh/omega_mikrotik}"
if [[ -f "$ROUTER_SSH_KEY" ]]; then
  SSH_OPTS+=(-o IdentitiesOnly=yes -i "$ROUTER_SSH_KEY")
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
  fingerprint               Print deterministic target identity/runtime fingerprint
  fetch-export <name>       Download <name>.rsc evidence with a timestamp and remove the remote copy
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

backup() {
  local stamp name password password_file secret_dir
  stamp="$(date +%Y%m%d-%H%M%S)"
  name="omega-policedbc-$stamp"
  mkdir -p "$ROOT/backups"
  secret_dir="${OMEGA_BACKUP_SECRET_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/zos-mikrotik/secrets}"
  mkdir -p "$secret_dir"
  chmod 700 "$secret_dir"
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
  password_file="$secret_dir/$name.backup.password"
  printf '%s\n' "$password" > "$password_file"
  chmod 600 "$password_file"

  ssh_mt "/export terse file=$name; /system backup save name=$name encryption=aes-sha256 password=$password"
  scp "${SSH_OPTS[@]}" "$TARGET:$name.rsc" "$ROOT/backups/$name.rsc"
  scp "${SSH_OPTS[@]}" "$TARGET:$name.backup" "$ROOT/backups/$name.backup"
  ssh_mt ":foreach f in=[/file find where name=\"$name.rsc\"] do={ /file remove \$f }; :foreach f in=[/file find where name=\"$name.backup\"] do={ /file remove \$f }"
  echo "Saved $ROOT/backups/$name.rsc"
  echo "Saved encrypted binary backup $ROOT/backups/$name.backup"
  echo "Backup password saved separately from backup artifacts with mode 600 at $password_file"
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
  local file remote output_file apply_state_dir lock_file lock_fd
  local session_pid read_fd write_fd wait_result session_rc
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

  for file in "$@"; do
    [[ -f "$file" && "$file" == *.rsc ]] || { echo "Invalid RSC file: $file" >&2; exit 2; }
    scp "${SSH_OPTS[@]}" "$file" "$TARGET:$(basename "$file")"
  done

  output_file="$(mktemp)"
  cleanup_output() { rm -f "$output_file"; }
  trap cleanup_output EXIT

  cleanup_remote_files() {
    for file in "$@"; do
      remote="$(basename "$file")"
      ssh_mt ":foreach f in=[/file find where name=\"$remote\"] do={ /file remove \$f }" >/dev/null 2>&1 || true
    done
  }

  coproc OMEGA_SAFE_SESSION { ssh -tt "${SSH_OPTS[@]}" "$TARGET" 2>&1; }
  session_pid=$OMEGA_SAFE_SESSION_PID
  read_fd=${OMEGA_SAFE_SESSION[0]}
  write_fd=${OMEGA_SAFE_SESSION[1]}

  wait_for_marker() {
    local success_marker="$1" failure_marker="$2" timeout_seconds="${3:-180}"
    local line start_seconds=$SECONDS
    wait_result=timeout
    while (( SECONDS - start_seconds < timeout_seconds )); do
      if IFS= read -r -t 1 line <&"$read_fd"; then
        line="${line//$'\r'/}"
        printf '%s\n' "$line" | tee -a "$output_file"
        if [[ "$line" == *'Hijacking Safe Mode from someone'* ]]; then
          wait_result=hijack
          return 0
        fi
        if [[ "$line" == *'Safe mode released by another user'* ]]; then
          wait_result=released
          return 0
        fi
        if [[ -n "$failure_marker" && "$line" == *"$failure_marker"* ]]; then
          wait_result=fail
          return 0
        fi
        if [[ "$line" == *"$success_marker"* ]]; then
          wait_result=pass
          return 0
        fi
      elif ! kill -0 "$session_pid" 2>/dev/null; then
        wait_result=closed
        return 0
      fi
    done
  }

  rollback_session() {
    printf '\004' >&"$write_fd" 2>/dev/null || true
    set +e
    wait "$session_pid"
    set -e
  }

  printf '\030' >&"$write_fd"
  wait_for_marker '[Safe Mode taken]' 'Hijacking Safe Mode from someone' 30
  if [[ "$wait_result" == hijack ]]; then
    printf 'd\n/quit\n' >&"$write_fd" 2>/dev/null || true
    set +e
    wait "$session_pid"
    set -e
    cleanup_remote_files "$@"
    echo 'RouterOS reported an existing Safe Mode owner; refused to hijack it.' >&2
    exit 4
  fi
  [[ "$wait_result" == pass ]] || {
    rollback_session
    cleanup_remote_files "$@"
    echo "RouterOS did not enter Safe Mode cleanly (result: $wait_result)." >&2
    exit 4
  }

  for file in "$@"; do
    remote="$(basename "$file")"
    printf ':do { /import file-name=%s verbose=yes; :put "OMEGA_PHASE_PASS %s" } on-error={ :put "OMEGA_PHASE_FAIL %s" }\n' "$remote" "$remote" "$remote" >&"$write_fd"
    wait_for_marker "OMEGA_PHASE_PASS $remote" "OMEGA_PHASE_FAIL $remote" 240
    if [[ "$wait_result" != pass ]]; then
      echo "Safe Mode phase failed before commit: $remote (result: $wait_result). Rolling back with Ctrl-D." >&2
      rollback_session
      cleanup_remote_files "$@"
      exit 4
    fi

    printf ':local omegaHistory [/system/history/print detail as-value where floating-undo=yes]; :if ([:len $omegaHistory] > 80) do={ :put "OMEGA_SAFE_BUDGET_FAIL" } else={ :put "OMEGA_SAFE_BUDGET_PASS" }\n' >&"$write_fd"
    wait_for_marker 'OMEGA_SAFE_BUDGET_PASS' 'OMEGA_SAFE_BUDGET_FAIL' 30
    if [[ "$wait_result" != pass ]]; then
      echo "Safe Mode floating-undo budget exceeded or could not be verified after $remote. Rolling back with Ctrl-D." >&2
      rollback_session
      cleanup_remote_files "$@"
      exit 4
    fi
  done

  printf ':put "OMEGA_APPLY_PASS"\n' >&"$write_fd"
  wait_for_marker 'OMEGA_APPLY_PASS' 'OMEGA_PHASE_FAIL' 30
  if [[ "$wait_result" != pass ]]; then
    echo "Safe Mode success sentinel was not confirmed (result: $wait_result). Rolling back with Ctrl-D." >&2
    rollback_session
    cleanup_remote_files "$@"
    exit 4
  fi

  # All phases, including assertive 99-VERIFY-HEALTH.rsc, passed while Safe Mode
  # was still owned by this SSH session. /quit now commits the verified changes.
  printf '/quit\n' >&"$write_fd"
  set +e
  wait "$session_pid"
  session_rc=$?
  set -e
  cleanup_remote_files "$@"

  (( session_rc == 0 )) || {
    echo "Safe Mode session exited unexpectedly after verified commit request (rc=$session_rc)." >&2
    exit 4
  }
}

verify() {
  ssh_mt ':local up [/ping 192.168.200.1 count=3]; :local internet [/ping 1.1.1.1 count=3]; :if ($up = 0) do={ :error "upstream reachability failed" }; :if ($internet = 0) do={ :error "internet reachability failed" }; /system resource print; /ip address print; /ip route print where dst-address="0.0.0.0/0"; /interface wireguard print detail; /interface wireguard peers print detail; /ip dhcp-server print detail where name="lan-dhcp"; /ip dhcp-server lease print detail where mac-address~"88:DC:96"; /ip firewall filter print stats where comment~"PoliceDBC|ZEAZ-PoliceDBC"; /ip firewall nat print stats where comment~"PoliceDBC|ZEAZ-PoliceDBC"; /ip service print; :put [/resolve cloudflare.com]'
}

fingerprint() {
  printf 'router_host=%s\n' "$ROUTER_HOST"
  ssh_mt ':put ("router_identity=" . [/system identity get name]); :put ("router_board=" . [/system resource get board-name]); :put ("router_arch=" . [/system resource get architecture-name]); :put ("router_version=" . [/system resource get version])'
}

fetch_export() {
  local name="$1" stamp destination
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid export name: $name" >&2; exit 2; }
  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ROOT/backups"
  destination="$ROOT/backups/$name-$stamp.rsc"
  scp "${SSH_OPTS[@]}" "$TARGET:$name.rsc" "$destination"
  ssh_mt ":foreach f in=[/file find where name=\"$name.rsc\"] do={ /file remove \$f }" >/dev/null
  echo "Saved evidence export $destination"
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
  fetch-export) [[ $# -eq 2 ]] || { usage; exit 2; }; fetch_export "$2" ;;
  *) usage; exit 2 ;;
esac
