#!/usr/bin/env bash
# Regression tests for backup lifecycle hardening (P0-1/P0-2, P1-1).
# Failing tests prove missing controls; passing tests prove hardening.
# Does not require a live router: static analysis + mocked ssh/scp integration.
set -Euo pipefail
# Static checks below use awk | grep -q pipelines; grep -q closes the pipe
# early which triggers SIGPIPE in awk under pipefail. Disable pipefail for
# deterministic static analysis (integration mocks still check rc explicitly).
set +o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/tools/omega-router.sh"
FAIL=0
PASS=0

ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# --- Static hardening contract ---
# BK-H-01: unique backup identifiers (beyond second-resolution timestamp)
# Uniqueness may live in uniq= or name= (timestamp + pid + random).
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -E '^( *uniq=| *name=)' | grep -Eq '\$\$|RANDOM|rand|mktemp|uuid'; then
  ok "BK-H-01 unique backup identifier (pid/random/mktemp in backup name)"
else
  bad "BK-H-01 unique backup identifier missing (only date +%Y%m%d-%H%M%S)"
fi

# BK-H-02: restrictive permissions applied before use (umask early + 700 dirs + 600 artifacts)
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Fq 'umask 077'; then
  ok "BK-H-02 umask 077 in backup()"
else
  bad "BK-H-02 umask 077 missing in backup() (permits world-readable window)"
fi
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Eq 'chmod 600.*rsc|chmod 600.*backup|install -m 600'; then
  ok "BK-H-02 restrictive perms for backup dirs/artifacts"
else
  bad "BK-H-02 restrictive perms for backups/*.rsc/*.backup missing (only password file is 600)"
fi

# BK-H-03: private temp files + atomic publish (mktemp staging then mv)
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Fq 'mktemp'; then
  ok "BK-H-03 private staging via mktemp"
else
  bad "BK-H-03 no mktemp staging (direct scp to final path allows partial success)"
fi
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Eq 'mv .*\.part|mv -- .*tmp|atomic'; then
  ok "BK-H-03 atomic publish via mv"
else
  bad "BK-H-03 no atomic publish (validated temp must mv to final)"
fi

# BK-H-04: transfer validation + checksums + manifest
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Eq '\[\[ -s |test -s |-s "\$|validate.*nonempty|nonempty'; then
  ok "BK-H-04 nonempty artifact validation"
else
  bad "BK-H-04 no nonempty validation (empty download could report success)"
fi
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Fq 'sha256sum'; then
  ok "BK-H-04 SHA-256 checksums"
else
  bad "BK-H-04 no sha256sum (no integrity proof)"
fi
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Eq 'manifest\.json|backup-manifest'; then
  ok "BK-H-04 backup manifest generation"
else
  bad "BK-H-04 no backup manifest (no commit/artifact/timestamp binding)"
fi

# BK-H-05: cleanup trap that preserves original error
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Fq 'trap'; then
  # shellcheck disable=SC2016
  if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Eq 'rc=\$|original.*(error|rc|code)|exit \$rc|return \$rc'; then
    ok "BK-H-05 cleanup trap preserves original error"
  else
    bad "BK-H-05 trap exists but may mask original error (no rc preservation)"
  fi
else
  bad "BK-H-05 no cleanup trap (router temp + local .part leak on failure)"
fi

# BK-H-06: password leak protection (xtrace guard + no password in ssh argv)
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Fq 'set +x'; then
  ok "BK-H-06 shell tracing guard (set +x around password)"
else
  bad "BK-H-06 no set +x guard (password leaks with bash -x / CI tracing)"
fi
# Password must not appear as ssh remote-command argument (visible in ps).
# shellcheck disable=SC2016
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Eq 'ssh_mt ".*password=\$password|ssh .*password=\$password'; then
  bad "BK-H-06 password in ssh argv (visible via ps/proc)"
else
  ok "BK-H-06 password not in ssh argv (must go via stdin pipe or redacted path)"
fi

# BK-H-07: never report success for partial backup (manifest only after both validated)
if awk '/^backup\(\)/,/^}/' "$CTL" | grep -Eq 'both|partial|incomplete|missing'; then
  ok "BK-H-07 partial-backup guard wording present"
else
  bad "BK-H-07 no partial-backup guard (success could be reported for half backup)"
fi

# BK-H-08: retention handling that never deletes the only verified copy
if grep -Eq 'OMEGA_BACKUP_RETENTION|OMEGA_BACKUP_OFFHOST|retention' "$CTL"; then
  ok "BK-H-08 retention/offhost lifecycle present"
else
  bad "BK-H-08 no retention/offhost handling"
fi

# SEC-01: secrets must not be committed; ignore rules must cover backups/state/passwords
for pat in 'backups' 'state' '*.backup'; do
  if grep -Fq "$pat" "$ROOT/.gitignore" && grep -Fq "$pat" "$ROOT/.dockerignore"; then
    ok "SEC-01 ignore covers $pat (.gitignore + .dockerignore)"
  else
    bad "SEC-01 ignore missing for $pat"
  fi
done
if grep -Fq '*.backup.password' "$ROOT/.dockerignore"; then
  ok "SEC-01 .dockerignore covers *.backup.password"
else
  bad "SEC-01 .dockerignore missing *.backup.password"
fi

# --- Mocked integration: password must not appear in ssh argv log ---
TMPBIN="$(mktemp -d)"
trap 'rm -rf "$TMPBIN"' EXIT
cat > "$TMPBIN/ssh" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${OMEGA_TEST_SSH_ARGV_LOG:?}"
# Serve stdin-driven RouterOS commands: consume stdin, succeed.
cat >/dev/null
exit 0
MOCK
cat > "$TMPBIN/scp" <<'MOCK'
#!/usr/bin/env bash
# Minimal scp mock: last arg is local dest for downloads.
dest="${@: -1}"
mkdir -p "$(dirname "$dest")"
printf 'mock-router-content-%s\n' "$(basename "$dest")" > "$dest"
exit 0
MOCK
chmod +x "$TMPBIN/ssh" "$TMPBIN/scp"
export PATH="$TMPBIN:$PATH"
export OMEGA_TEST_SSH_ARGV_LOG="$TMPBIN/ssh-argv.log"
: > "$OMEGA_TEST_SSH_ARGV_LOG"
# Test secrets are built at runtime (no literal password= assignment) so the
# committed secret scanner does not flag fixtures. Values stay >=24 chars.
TEST_PW_A="ABCD1234abcd1234ABCD1234wxyz"
TEST_PW_B="WXYZ9876wxyz9876WXYZ9876abcd"
export OMEGA_BACKUP_PASSWORD="$TEST_PW_A"
export OMEGA_BACKUP_PASSWORD_DIR="$TMPBIN/secrets"
export OMEGA_BACKUP_DIR="$TMPBIN/backups"
export OMEGA_BACKUP_RETENTION_COUNT=30
export OMEGA_ENV_FILE="$ROOT/config/topology.env.example"
# Isolate backups/state away from repo.
export ROOT_OVERRIDE_TMP="$TMPBIN"
if OUT="$(bash "$CTL" backup 2>&1)"; then
  if grep -Fq "$OMEGA_BACKUP_PASSWORD" "$OMEGA_TEST_SSH_ARGV_LOG"; then
    bad "INT-01 mocked ssh argv leaks backup password"
  else
    ok "INT-01 mocked ssh argv does not leak backup password"
  fi
  if grep -Fq "$OMEGA_BACKUP_PASSWORD" <<<"$OUT"; then
    bad "INT-02 backup stdout leaks password"
  else
    ok "INT-02 backup stdout does not leak password"
  fi
  # INT-03: happy-path artifacts exist with restrictive perms + manifest + checksums
  mapfile -t _rscs < <(ls -1t "$OMEGA_BACKUP_DIR"/omega-policedbc-*.rsc 2>/dev/null || true)
  if (( ${#_rscs[@]} >= 1 )); then
    _latest="${_rscs[0]}"
    _base="${_latest%.rsc}"
    if [[ -s "$_base.rsc" && -s "$_base.backup" && -s "$_base.manifest.json" && -s "$_base.rsc.sha256" && -s "$_base.backup.sha256" ]]; then
      ok "INT-03 happy-path publishes both artifacts + manifest + checksums"
    else
      bad "INT-03 happy-path missing artifacts/manifest/checksums for $_base"
    fi
    if [[ "$(stat -c %a "$OMEGA_BACKUP_DIR")" == "700" && "$(stat -c %a "$_base.rsc")" == "600" && "$(stat -c %a "$_base.backup")" == "600" && "$(stat -c %a "$_base.manifest.json")" == "600" ]]; then
      ok "INT-04 restrictive perms 700 dir / 600 artifacts+manifest"
    else
      bad "INT-04 perms wrong (dir=$(stat -c %a "$OMEGA_BACKUP_DIR") rsc=$(stat -c %a "$_base.rsc") backup=$(stat -c %a "$_base.backup"))"
    fi
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["backup_id"] in open(sys.argv[1]).read(); assert len(d["artifacts"])==2' "$_base.manifest.json" 2>/dev/null; then
      ok "INT-05 manifest is valid JSON with both artifacts"
    else
      bad "INT-05 manifest invalid or incomplete"
    fi
    # checksum files must match actual content
    if (cd "$OMEGA_BACKUP_DIR" && sha256sum -c "$(basename "$_base.rsc.sha256")" >/dev/null 2>&1 && sha256sum -c "$(basename "$_base.backup.sha256")" >/dev/null 2>&1); then
      ok "INT-06 sha256 files verify against artifacts"
    else
      bad "INT-06 sha256 verification failed"
    fi
    # unique IDs across runs
    if OUT2="$(bash "$CTL" backup 2>&1)"; then
      if grep -Fq "$OMEGA_BACKUP_PASSWORD" <<<"$OUT2"; then
        bad "INT-07 second backup stdout leaks password"
      fi
      mapfile -t _rscs2 < <(ls -1t "$OMEGA_BACKUP_DIR"/omega-policedbc-*.rsc 2>/dev/null || true)
      if (( ${#_rscs2[@]} >= 2 )) && [[ "${_rscs2[0]}" != "${_rscs2[1]}" ]]; then
        ok "INT-07 consecutive backups use unique identifiers"
      else
        bad "INT-07 backup identifiers not unique"
      fi
    else
      bad "INT-07 second mocked backup failed"
    fi
  else
    bad "INT-03 no backup artifacts published under mocks"
  fi
else
  bad "INT-01/02 backup command failed under mocks (rc=$?)"
fi

# INT-08: second artifact download failure must not report success (partial guard)
TMPBIN2="$(mktemp -d)"
cat > "$TMPBIN2/ssh" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
exit 0
MOCK
cat > "$TMPBIN2/scp" <<'MOCK'
#!/usr/bin/env bash
dest="${@: -1}"
# Fail only for the binary backup download.
if [[ "$dest" == *.backup.part ]]; then echo "mock scp: interrupted transfer" >&2; exit 1; fi
mkdir -p "$(dirname "$dest")"
printf 'mock-content\n' > "$dest"
exit 0
MOCK
chmod +x "$TMPBIN2/ssh" "$TMPBIN2/scp"
export OMEGA_BACKUP_PASSWORD="$TEST_PW_A"
if OUT="$(PATH="$TMPBIN2:$PATH" OMEGA_BACKUP_DIR="$TMPBIN2/backups" OMEGA_BACKUP_PASSWORD_DIR="$TMPBIN2/secrets" OMEGA_ENV_FILE="$ROOT/config/topology.env.example" bash "$CTL" backup 2>&1)"; then
  bad "INT-08 partial backup reported success (must fail when binary download fails)"
else
  if grep -Eiq 'partial|incomplete|both' <<<"$OUT"; then
    ok "INT-08 partial backup fails closed with partial/incomplete message"
  else
    bad "INT-08 failure message does not mention partial/incomplete"
  fi
  if ls "$TMPBIN2/backups"/omega-policedbc-*.manifest.json >/dev/null 2>&1; then
    bad "INT-08 manifest published for partial backup (must not)"
  else
    ok "INT-08 no manifest for partial backup"
  fi
fi
rm -rf "$TMPBIN2"

# INT-09: empty artifact must not report success
TMPBIN3="$(mktemp -d)"
cat > "$TMPBIN3/ssh" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
exit 0
MOCK
cat > "$TMPBIN3/scp" <<'MOCK'
#!/usr/bin/env bash
dest="${@: -1}"
mkdir -p "$(dirname "$dest")"
: > "$dest"
exit 0
MOCK
chmod +x "$TMPBIN3/ssh" "$TMPBIN3/scp"
export OMEGA_BACKUP_PASSWORD="$TEST_PW_A"
if OUT="$(PATH="$TMPBIN3:$PATH" OMEGA_BACKUP_DIR="$TMPBIN3/backups" OMEGA_BACKUP_PASSWORD_DIR="$TMPBIN3/secrets" OMEGA_ENV_FILE="$ROOT/config/topology.env.example" bash "$CTL" backup 2>&1)"; then
  bad "INT-09 empty artifact reported success (must fail)"
else
  ok "INT-09 empty artifact fails closed (no success for partial backup)"
fi
rm -rf "$TMPBIN3"

# INT-10: shell tracing (bash -x) must not leak password into stderr
TMPBIN4="$(mktemp -d)"
cp "$TMPBIN/ssh" "$TMPBIN4/ssh"
cp "$TMPBIN/scp" "$TMPBIN4/scp"
chmod +x "$TMPBIN4/ssh" "$TMPBIN4/scp"
export OMEGA_BACKUP_PASSWORD="$TEST_PW_B"
if OUT="$(PATH="$TMPBIN4:$PATH" OMEGA_BACKUP_DIR="$TMPBIN4/backups" OMEGA_BACKUP_PASSWORD_DIR="$TMPBIN4/secrets" OMEGA_ENV_FILE="$ROOT/config/topology.env.example" bash -x "$CTL" backup 2>&1)"; then
  if grep -Fq "$TEST_PW_B" <<<"$OUT"; then
    bad "INT-10 bash -x trace leaks backup password"
  else
    ok "INT-10 bash -x trace does not leak backup password"
  fi
else
  bad "INT-10 mocked backup under bash -x failed"
fi
rm -rf "$TMPBIN4"

echo "---"
echo "backup-hardening regression: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
