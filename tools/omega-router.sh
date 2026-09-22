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
  apply <file.rsc>          Disabled: unsafe non-transactional apply
  apply-safe <files...>     Apply all files in one interactive RouterOS Safe Mode session
  verify                    Run read-only post-change verification
  fingerprint               Print stable target/config fingerprint for dry-run binding
  legacy-dhcp-status        Read-only legacy DHCP/pool migration status
  wifi-single-network-status Read-only single-network Wi-Fi RouterOS status
  fetch-export <name>       Download <name>.rsc from router
EOF
}

# RouterOS commands are intentionally passed to the remote shell.
# shellcheck disable=SC2029
ssh_mt() { ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }

# Stdin-driven RouterOS session avoids placing secrets in ssh argv (ps-visible).
# shellcheck disable=SC2029
ssh_stdin() { ssh "${SSH_OPTS[@]}" "$TARGET"; }

status() {
  ssh_mt '/system identity print; /system resource print; /ip address print; /ip route print where dst-address="0.0.0.0/0"; /interface wireguard peers print detail'
}

audit() {
  ssh_mt '/system identity print; /system resource print; /interface print; /interface bridge port print; /interface list member print; /ip address print detail; /ip route print detail; /ip pool print detail; /ip pool used print detail; /ip dhcp-server print detail; /ip dhcp-server network print detail; /ip dhcp-server lease print detail; /interface wireguard print detail; /interface wireguard peers print detail; /ip firewall filter print detail; /ip firewall nat print detail; /ip service print detail; /log print'
}

fingerprint() {
  local env_sha
  env_sha="$(sha256sum "$ENV_FILE" | awk '{print $1}')"
  printf 'router_host=%s\n' "$ROUTER_HOST"
  printf 'router_user=%s\n' "$ROUTER_SSH_USER"
  printf 'env_sha256=%s\n' "$env_sha"
  ssh_mt ':put ("identity=" . [/system identity get name]); :put ("board=" . [/system resource get board-name]); :put ("version=" . [/system resource get version]); :put ("architecture=" . [/system resource get architecture-name])'
}

legacy_dhcp_status() {
  ssh_mt ':put "===== POOLS ====="; /ip pool print detail; :put "===== POOL USAGE ====="; /ip pool used print detail; :put "===== DHCP SERVERS ====="; /ip dhcp-server print detail; :put "===== DHCP NETWORKS ====="; /ip dhcp-server network print detail; :put "===== LEGACY ADDRESS ====="; /ip address print detail where address="192.168.0.0/24"; :put "===== LEGACY ARP ====="; /ip arp print detail where address~"^192\\.168\\.(0|10)\\."'
}

wifi_single_network_status() {
  ssh_mt ':put "===== WIFI SINGLE NETWORK ====="; :put "===== LAN GATEWAY ====="; /ip address print detail where address="192.168.1.1/24" and interface="DBC-Bridge-Local"; :put "===== DHCP SERVER ====="; /ip dhcp-server print detail where name="lan-dhcp"; :put "===== DHCP NETWORK ====="; /ip dhcp-server network print detail where address="192.168.1.0/24"; :put "===== LAN POOL ====="; /ip pool print detail where name="lan-pool"; :put "===== ENGENIUS DHCP ====="; /ip dhcp-server lease print detail where mac-address~"88:DC:96"; :put "===== ENGENIUS ARP ====="; /ip arp print detail where mac-address~"88:DC:96"; :put "===== LEGACY INDICATORS ====="; /ip address print detail where address="192.168.0.0/24"; /ip dhcp-server network print detail where address="192.168.0.0/24"; /ip dhcp-server network print detail where address="192.168.10.0/24"'
}

backup() {
  # ขั้นตอน backup แบบ idempotent: staging ส่วนตัว + ตรวจสอบ + เผยแพร่แบบ atomic
  # ไม่รายงานความสำเร็จสำหรับ partial backup; cleanup ต้องไม่บดบัง error เดิม
  umask 077
  local stamp uniq rand_suffix name password password_file password_dir backup_dir
  local tmpdir stage_rsc stage_backup final_rsc final_backup
  local xtrace_was_on=0 rc=0 commit_sha created_at router_version
  local rsc_sha backup_sha rsc_bytes backup_bytes manifest_file
  local retention_count offhost_dir
  if [[ $- == *x* ]]; then xtrace_was_on=1; fi
  set +x
  stamp="$(date +%Y%m%d-%H%M%S)"
  # ตัวระบุที่ไม่ซ้ำ: timestamp + pid + random (กันชนกันเมื่อรันถี่/พร้อมกัน)
  rand_suffix="$(openssl rand -hex 4 2>/dev/null || printf '%s%s' "$RANDOM" "$RANDOM")"
  uniq="${stamp}-$$-${rand_suffix}"
  name="omega-policedbc-$uniq"
  backup_dir="${OMEGA_BACKUP_DIR:-$ROOT/backups}"
  password_dir="${OMEGA_BACKUP_PASSWORD_DIR:-$ROOT/state/backup-secrets}"
  mkdir -p "$backup_dir" "$password_dir"
  chmod 700 "$backup_dir" "$password_dir"
  password="${OMEGA_BACKUP_PASSWORD:-}"
  if [[ -z "$password" ]]; then
    command -v openssl >/dev/null 2>&1 || { echo 'openssl is required to generate an encrypted backup password' >&2; return 1; }
    password="$(openssl rand -hex 32)"
  fi
  [[ "$password" =~ ^[A-Za-z0-9_-]{24,}$ ]] || {
    echo 'OMEGA_BACKUP_PASSWORD must contain only letters, digits, _ or - and be at least 24 characters' >&2
    unset password
    return 2
  }
  password_file="$password_dir/$name.backup.password"
  printf '%s\n' "$password" > "$password_file"
  chmod 600 "$password_file"

  # staging ส่วนตัวสำหรับ download (กัน partial file ปรากฏที่ปลายทาง)
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/omega-backup-XXXXXX")"
  chmod 700 "$tmpdir"
  stage_rsc="$tmpdir/$name.rsc.part"
  stage_backup="$tmpdir/$name.backup.part"
  final_rsc="$backup_dir/$name.rsc"
  final_backup="$backup_dir/$name.backup"
  manifest_file="$backup_dir/$name.manifest.json"

  # cleanup router temp files แบบ best-effort (ไม่ทำให้ error เดิมหาย)
  backup_cleanup_router() {
    ssh_mt ":foreach f in=[/file find where name=\"$name.rsc\"] do={ /file remove \$f }; :foreach f in=[/file find where name=\"$name.backup\"] do={ /file remove \$f }" >/dev/null 2>&1 || true
  }
  # trap ภายใน backup: เก็บ rc เดิมแล้วค่อย cleanup (ไม่บดบัง original error)
  trap 'rc=$?; rm -rf "${tmpdir:-}"; trap - RETURN' RETURN

  # สร้าง export + encrypted binary backup บน router โดยส่ง password ทาง stdin
  # (ไม่ใส่ password ใน ssh argv เพื่อไม่ให้ปรากฏใน ps/process output)
  # หมายเหตุ: ใช้ || block แทน if ! เพื่อให้ rc=$? เก็บ exit code จริง (if ! จะได้ 0)
  # RouterOS commands via stdin pipe are intentional; no client-side expansion.
  {
    printf '/export terse file=%s\n' "$name"
    printf '/system backup save name=%s encryption=aes-sha256 password=%s\n' "$name" "$password"
  } | ssh_stdin || {
    rc=$?
    (( rc != 0 )) || rc=1
    echo 'ERROR: failed to create router backup artifacts (no partial success reported)' >&2
    rm -rf "$tmpdir"
    backup_cleanup_router
    unset password
    trap - RETURN
    if (( xtrace_was_on )); then set -x; fi
    return "$rc"
  }
  unset password

  # download ไปยัง staging ก่อน (ยังไม่ถือว่าสำเร็จถ้าได้ไม่ครบทั้งสองไฟล์)
  scp "${SSH_OPTS[@]}" "$TARGET:$name.rsc" "$stage_rsc" || {
    rc=$?
    (( rc != 0 )) || rc=1
    echo 'ERROR: incomplete backup: export download failed (partial backup is not success)' >&2
    rm -rf "$tmpdir"
    backup_cleanup_router
    trap - RETURN
    if (( xtrace_was_on )); then set -x; fi
    return "$rc"
  }
  scp "${SSH_OPTS[@]}" "$TARGET:$name.backup" "$stage_backup" || {
    rc=$?
    (( rc != 0 )) || rc=1
    echo 'ERROR: incomplete backup: binary backup download failed (partial backup is not success)' >&2
    rm -rf "$tmpdir"
    backup_cleanup_router
    trap - RETURN
    if (( xtrace_was_on )); then set -x; fi
    return "$rc"
  }

  # ตรวจสอบว่าได้ครบทั้งสองไฟล์และไม่ว่าง (กัน success ปลอมจาก partial/empty)
  [[ -s "$stage_rsc" ]] || {
    echo 'ERROR: incomplete backup: export artifact is missing or empty; both artifacts are required' >&2
    rm -rf "$tmpdir"
    backup_cleanup_router
    trap - RETURN
    if (( xtrace_was_on )); then set -x; fi
    return 1
  }
  [[ -s "$stage_backup" ]] || {
    echo 'ERROR: incomplete backup: binary artifact is missing or empty; both artifacts are required' >&2
    rm -rf "$tmpdir"
    backup_cleanup_router
    trap - RETURN
    if (( xtrace_was_on )); then set -x; fi
    return 1
  }

  # คำนวณ checksum ก่อนเผยแพร่
  rsc_sha="$(sha256sum "$stage_rsc" | awk '{print $1}')"
  backup_sha="$(sha256sum "$stage_backup" | awk '{print $1}')"
  rsc_bytes="$(wc -c < "$stage_rsc" | tr -d ' ')"
  backup_bytes="$(wc -c < "$stage_backup" | tr -d ' ')"
  chmod 600 "$stage_rsc" "$stage_backup"

  # เผยแพร่แบบ atomic: mv validated .part staging to final atomically
  mv -- "$stage_rsc" "$final_rsc" # mv .part staging to final atomic publish
  mv -- "$stage_backup" "$final_backup" # mv .part staging to final atomic publish
  chmod 600 "$final_rsc" "$final_backup"
  printf '%s  %s\n' "$rsc_sha" "$(basename "$final_rsc")" > "$final_rsc.sha256"
  printf '%s  %s\n' "$backup_sha" "$(basename "$final_backup")" > "$final_backup.sha256"
  chmod 600 "$final_rsc.sha256" "$final_backup.sha256"

  # เก็บ manifest ที่ผูก commit/timestamp/artifact (ไม่รวม password/secret)
  commit_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  router_version="$(ssh_mt '/system resource get version' 2>/dev/null | tr -d '\r\n' || printf 'unknown')"
  {
    printf '{\n'
    printf '  "backup_id": "%s",\n' "$name"
    printf '  "commit_sha": "%s",\n' "$commit_sha"
    printf '  "created_at": "%s",\n' "$created_at"
    printf '  "router_host": "%s",\n' "$ROUTER_HOST"
    printf '  "router_user": "%s",\n' "$ROUTER_SSH_USER"
    printf '  "router_version": "%s",\n' "$router_version"
    printf '  "artifacts": [\n'
    printf '    {"name": "%s", "sha256": "%s", "bytes": %s},\n' "$(basename "$final_rsc")" "$rsc_sha" "$rsc_bytes"
    printf '    {"name": "%s", "sha256": "%s", "bytes": %s}\n' "$(basename "$final_backup")" "$backup_sha" "$backup_bytes"
    printf '  ],\n'
    printf '  "password_file": "%s"\n' "$(basename "$password_file")"
    printf '}\n'
  } > "$manifest_file"
  chmod 600 "$manifest_file"

  # ลบ router temp เฉพาะเมื่อ local verified copy ครบแล้ว (ไม่ลบ copy เดียวที่ verify แล้ว)
  backup_cleanup_router
  rm -rf "$tmpdir"
  trap - RETURN

  # retention: เก็บเฉพาะ N ชุดล่าสุด ไม่ลบ copy เดียวที่เหลือ (OMEGA_BACKUP_RETENTION_COUNT)
  retention_count="${OMEGA_BACKUP_RETENTION_COUNT:-30}"
  if [[ "$retention_count" =~ ^[0-9]+$ ]]; then
    if (( retention_count > 0 )); then
      # คงไฟล์ชุดปัจจุบันไว้เสมอ แล้วลบเฉพาะส่วนเกินจากเก่าไปใหม่
      mapfile -t _old_backups < <(ls -1t "$backup_dir"/omega-policedbc-*.rsc 2>/dev/null || true)
      if (( ${#_old_backups[@]} > retention_count )); then
        for ((_i=retention_count; _i<${#_old_backups[@]}; _i++)); do
          _base="${_old_backups[$_i]%.rsc}"
          # กันลบชุดที่เพิ่งสร้าง
          if [[ "$_base" == "$backup_dir/$name" ]]; then continue; fi
          rm -f "$_base.rsc" "$_base.rsc.sha256" "$_base.backup" "$_base.backup.sha256" "$_base.manifest.json" || true
        done
      fi
    fi
  fi

  # optional off-host copy (ไม่ทำให้ backup หลักล้มเหลวถ้าปลายทางมีปัญหา)
  offhost_dir="${OMEGA_BACKUP_OFFHOST_DIR:-}"
  if [[ -n "$offhost_dir" ]]; then
    mkdir -p "$offhost_dir" 2>/dev/null || echo "WARN: off-host backup retention directory unavailable: $offhost_dir" >&2
    if [[ -d "$offhost_dir" ]]; then
      cp -p "$final_rsc" "$final_rsc.sha256" "$final_backup" "$final_backup.sha256" "$manifest_file" "$offhost_dir/" 2>/dev/null \
        || echo "WARN: off-host backup copy incomplete (primary verified copy retained locally)" >&2
    fi
  fi

  if (( xtrace_was_on )); then set -x; fi
  echo "Saved $final_rsc"
  echo "Saved encrypted binary backup $final_backup"
  echo "Saved manifest $manifest_file"
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
  echo 'Unsafe direct apply is disabled. Use audited backup, dry-run and a CHR-verified interactive Safe Mode driver.' >&2
  return 4
}

apply_safe() {
  [[ "${OMEGA_ALLOW_LIVE_APPLY:-0}" == "1" ]] || { echo 'Live apply blocked: OMEGA_ALLOW_LIVE_APPLY=1 is required' >&2; exit 3; }
  local file remote output session_rc output_file command_file apply_state_dir lock_file lock_fd evidence_dir stamp
  local driver_args
  (( $# > 0 )) || { echo 'apply-safe requires at least one .rsc file' >&2; exit 2; }

  apply_state_dir="${OMEGA_STATE_DIR:-$ROOT/state/deploy}"
  mkdir -p "$apply_state_dir"
  lock_file="$apply_state_dir/apply-safe.lock"
  command -v flock >/dev/null 2>&1 || { echo 'flock is required for apply-safe concurrency protection' >&2; exit 2; }
  command -v python3 >/dev/null 2>&1 || { echo 'python3 is required for the Safe Mode session driver' >&2; exit 2; }
  exec {lock_fd}>"$lock_file"
  flock -n "$lock_fd" || {
    echo 'Another apply-safe session is already active on this controller; refusing concurrent RouterOS Safe Mode apply.' >&2
    exit 4
  }

  # One RouterOS :do transaction. /quit exists only on the success path.
  # Sentinels are concatenated so terminal input echo cannot be mistaken for
  # an executed PASS/FAIL result. Each phase filename is echoed first so a
  # failure inside Safe Mode identifies which phase did not complete.
  # RouterOS 7.25beta4 does not support :local/:global/:set in /import stdin
  # context; embedding RSC content directly as an SSH argument works around it.
  output_file="$(mktemp)"
  command_file="$(mktemp)"
  trap 'rm -f "${output_file:-}" "${command_file:-}"' RETURN
  {
    printf ':do {\n'
    for file in "$@"; do
      [[ -f "$file" && "$file" == *.rsc ]] || { echo "Invalid RSC file: $file" >&2; exit 2; }
      remote="$(basename "$file")"
      printf ':put ("OMEGA_PHASE_" . "FILE:%s");\n' "$remote"
      cat "$file"
    done
    printf ':put ("OMEGA_APPLY_" . "PASS") } on-error={ :put ("OMEGA_PHASE_" . "FAIL"); :error "OMEGA transactional apply failed" }\n'
  } > "$command_file"

  driver_args=(
    "$ROOT/tools/routeros-safe-session.py"
    --target "$TARGET"
    --command-file "$command_file"
    --output-file "$output_file"
    --safe-timeout 60
    --transaction-timeout 600
  )
  if [[ -n "${ROUTER_SSH_KEY:-}" ]]; then
    driver_args+=(--identity "$ROUTER_SSH_KEY")
  fi

  set +e
  python3 "${driver_args[@]}"
  session_rc=$?
  set -e
  output="$(cat "$output_file")"

  for file in "$@"; do
    remote="$(basename "$file")"
    ssh_mt ":foreach f in=[/file find where name=\"$remote\"] do={ /file remove \$f }" >/dev/null 2>&1 || true
  done

  (( session_rc == 0 )) || { echo 'Safe Mode apply session failed' >&2; exit 4; }
  grep -Fq 'OMEGA_SAFE_MODE_CONFIRMED' <<<"$output" && {
    echo 'Internal error: local Safe Mode confirmation leaked into RouterOS evidence stream' >&2
    exit 4
  }
  grep -Fq 'OMEGA_PHASE_FILE:' <<<"$output" || {
    echo 'RouterOS did not process any production phases' >&2
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
      ssh_mt ":foreach f in=[/file find where name=\"$remote\"] do={ /file remove \$f }" >/dev/null 2>&1 || true
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
  legacy-dhcp-status) legacy_dhcp_status ;;
  wifi-single-network-status) wifi_single_network_status ;;
  fetch-export) [[ $# -eq 2 ]] || { usage; exit 2; }; mkdir -p "$ROOT/backups"; scp "${SSH_OPTS[@]}" "$TARGET:$2.rsc" "$ROOT/backups/$2.rsc" ;;
  *) usage; exit 2 ;;
esac
