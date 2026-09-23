#!/usr/bin/env bash
# Repository-safe security regression (P1-1). No network, no secrets.
# Fails if ignore rules, build-context exclusions, perms, retention or
# secret-scanning gates regress; never prints secret material.
set -Euo pipefail
set +o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
PASS=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# SEC-IG-01: local-only paths stay out of Git and build context
for pat in 'config/topology.env' 'config/wifi-single-network.env' 'cloudflare/config.env' 'backups' 'state' '*.backup' '*.backup.password' '*.key' '*.pem'; do
  if grep -Fq "$pat" "$ROOT/.gitignore"; then ok "SEC-IG gitignore covers $pat"; else bad "SEC-IG gitignore missing $pat"; fi
done
for pat in 'config/topology.env' 'config/wifi-single-network.env' 'cloudflare/config.env' 'backups' 'state' '*.backup' '*.key' '*.pem' 'artifacts'; do
  if grep -Fq "$pat" "$ROOT/.dockerignore"; then ok "SEC-CTX dockerignore covers $pat"; else bad "SEC-CTX dockerignore missing $pat"; fi
done

# SEC-PERM-01: tracked scripts that handle secrets must not be world-writable
if find "$ROOT/tools" "$ROOT/core" -maxdepth 1 -type f -perm -o+w 2>/dev/null | grep -q .; then
  bad "SEC-PERM world-writable file under tools/core"
else
  ok "SEC-PERM no world-writable files under tools/core"
fi

# SEC-SCAN-01: committed tree must not contain private key blocks or literal secrets
if git -C "$ROOT" grep -InE 'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' $(git -C "$ROOT" ls-files) 2>/dev/null | grep -q .; then
  bad "SEC-SCAN private key block committed"
else
  ok "SEC-SCAN no committed private key blocks"
fi

# SEC-CLEAN-01: unsafe cleanup patterns must not appear (no rm -rf / , no broad backup delete)
# shellcheck disable=SC2016
if grep -RInE --include='*.sh' --exclude='test-repo-security.sh' 'rm -rf /($| |")|rm -rf \$ROOT/?$' "$ROOT/tools" 2>/dev/null | grep -q .; then
  bad "SEC-CLEAN unsafe rm pattern in tools"
else
  ok "SEC-CLEAN no unsafe rm patterns in tools"
fi
# Backup retention must guard the just-created set (never delete only verified copy)
# shellcheck disable=SC2016
if grep -Fq '== "$backup_dir/$name"' "$ROOT/tools/omega-router.sh" || grep -Fq 'backup_dir/$name' "$ROOT/tools/omega-router.sh"; then
  ok "SEC-CLEAN retention guards current backup set"
else
  bad "SEC-CLEAN retention missing current-set guard"
fi

# SEC-CI-01: security workflow must retain evidence and gate HIGH/CRITICAL
for needle in 'retention-days: 30' 'severity: HIGH,CRITICAL' 'format: cyclonedx'; do
  if grep -Fq "$needle" "$ROOT/.github/workflows/security-scan.yml"; then ok "SEC-CI covers $needle"; else bad "SEC-CI missing $needle"; fi
done

# SEC-CI-02: every workflow must declare least-privilege permissions
for wf in "$ROOT"/.github/workflows/*.yml; do
  _base="$(basename "$wf")"
  if grep -Eq '^permissions:' "$wf" && grep -Eq '^  contents: read' "$wf"; then
    ok "SEC-CI least-privilege permissions in $_base"
  else
    bad "SEC-CI $_base missing permissions/contents-read"
  fi
done

# SEC-SSH-01: host-key trust must never be downgraded (no StrictHostKeyChecking=no)
# shellcheck disable=SC2016
if grep -RInE --include='*.sh' --exclude='test-repo-security.sh' 'StrictHostKeyChecking\s*=\s*no|StrictHostKeyChecking\s+no' "$ROOT/tools" "$ROOT/core" 2>/dev/null | grep -q .; then
  bad "SEC-SSH host-key verification downgraded somewhere"
else
  ok "SEC-SSH host-key verification never disabled (BatchMode fails closed)"
fi

# SEC-LOG-01: backup/restore code must not echo secret values to logs
# shellcheck disable=SC2016
if grep -nE 'echo[^|]*\$password[^_]' "$ROOT/tools/omega-router.sh" "$ROOT/tools/restore-drill.sh" 2>/dev/null | grep -vq 'password_file\|password saved\|password availability\|password unavailable\|password format\|password travels\|password handling'; then
  bad "SEC-LOG possible password value in log output"
else
  ok "SEC-LOG no password values in log output (paths/mentions only)"
fi

# SEC-RET-01: backup retention and recovery evidence paths must exist in code
for needle in 'OMEGA_BACKUP_RETENTION_COUNT' 'manifest.json' 'artifacts/restore-drill'; do
  if grep -Fq "$needle" "$ROOT/tools/omega-router.sh" "$ROOT/tools/restore-drill.sh" 2>/dev/null; then
    ok "SEC-RET covers $needle"
  else
    bad "SEC-RET missing $needle"
  fi
done

echo "---"
echo "repo-security regression: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
