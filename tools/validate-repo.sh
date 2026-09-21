#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
err(){ echo "ERROR: $*" >&2; fail=1; }

required=(
  00-PRECHECK.rsc 10-BACKUP-SNAPSHOT.rsc 20-NETWORK-NORMALIZE.rsc
  30-DHCP-DNS-NTP.rsc 40-WIREGUARD-SERVICES.rsc 50-FIREWALL-NAT.rsc
  60-OBSERVABILITY.rsc 90-EXPORT-EVIDENCE.rsc 99-VERIFY-HEALTH.rsc
  reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc
  AGENTS.md README.md CHANGELOG.md CHECKLIST.md CONTRIBUTING.md SECURITY.md
  CODE_OF_CONDUCT.md GOVERNANCE.md MAINTAINERS.md SUPPORT.md ENVIRONMENTS.md
  docs/INDEX.md docs/ARCHITECTURE.md docs/INSTALLATION.md docs/RUNBOOK.md
  docs/NETWORK-RECOVERY.md docs/SSH-HARDENING.md docs/DISASTER-RECOVERY.md
  docs/PRODUCTION-READINESS.md docs/GITHUB-OPERATIONS.md docs/GITHUB-SETTINGS.md
  docs/TESTING.md docs/RELEASES.md docs/ROADMAP.md docs/LICENSING.md
  cloudflare/README.md cloudflare/config.env.example
  .github/PULL_REQUEST_TEMPLATE.md .github/CODEOWNERS
  .env.example core/.env.example zOS/.env.example runner/.env.example prod/.env.example config/topology.env.example
  runner/README.md prod/README.md tools/validate-docs.py tools/omega-router.sh tools/deploy-phases.sh
  tools/core-network-repair.sh tools/routeros-auto-update.sh tools/e2e-check.sh
  tools/install-controller.sh tools/install-update-monitor.sh core/install.sh core/install-ssh-key.sh core/README.md
  zOS/README.md zOS/VERSION zOS/Dockerfile zOS/bin/zos zOS/install.sh
  .github/workflows/validate.yml .github/workflows/zos-build.yml .github/workflows/security-scan.yml
  .github/dependabot.yml .dockerignore
)
for f in "${required[@]}"; do [[ -f "$f" ]] || err "missing required file: $f"; done

grep -q '^CF_CONNECTOR_HOST=core\.zeaz\.dev$' cloudflare/config.env.example || err 'Cloudflare connector template is missing the approved CORE host'
grep -q 'Cloudflare' cloudflare/README.md || err 'Cloudflare integration documentation is missing'
if grep -Eiq '(^|_)(TOKEN|SECRET|PASSWORD|PRIVATE_KEY)=.+' cloudflare/config.env.example; then err 'Cloudflare template contains a populated credential'; fi
grep -Fq 'cloudflare/config.env' .gitignore || err 'populated Cloudflare config is not ignored'

executables=(core/install.sh tools/validate-repo.sh tools/omega-router.sh tools/deploy-phases.sh tools/core-network-repair.sh tools/routeros-auto-update.sh tools/e2e-check.sh tools/install-controller.sh tools/install-update-monitor.sh zOS/bin/zos zOS/install.sh)
for f in "${executables[@]}"; do [[ ! -f "$f" || -x "$f" ]] || err "operational entry point is not executable: $f"; done

active=(00-PRECHECK.rsc 10-BACKUP-SNAPSHOT.rsc 20-NETWORK-NORMALIZE.rsc 30-DHCP-DNS-NTP.rsc 40-WIREGUARD-SERVICES.rsc 50-FIREWALL-NAT.rsc 60-OBSERVABILITY.rsc 90-EXPORT-EVIDENCE.rsc 99-VERIFY-HEALTH.rsc)
for f in "${active[@]}"; do
  if grep -Eiq 'reset-configuration|/ip firewall (filter|nat) remove \[find\]( |$)|/ip address remove \[find\]( |$)|private-key=' "$f"; then
    err "$f contains an unfiltered destructive/key pattern"
  fi
done

# Verified production topology.
grep -q 'DBC-Bridge-Local' 00-PRECHECK.rsc || err 'precheck missing verified LAN bridge'
grep -q 'interface="ether1" and status="bound"' 00-PRECHECK.rsc || err 'precheck missing DHCP WAN bound check'
grep -q '192.168.1.1/24' 00-PRECHECK.rsc || err 'precheck missing LAN gateway'
grep -q '192.168.200.1' 00-PRECHECK.rsc || err 'precheck missing upstream gateway'
grep -q '^ROUTER_WAN_MODE=dhcp$' config/topology.env.example || err 'topology must declare DHCP WAN'
grep -q '^ROUTER_WAN_INTERFACE=ether1$' config/topology.env.example || err 'topology must declare ether1 WAN'
grep -q '^ROUTER_LAN_BRIDGE=DBC-Bridge-Local$' config/topology.env.example || err 'topology must declare DBC-Bridge-Local LAN'
grep -q '^DEV_LAN_IP=192\.168\.1\.123$' config/topology.env.example || err 'CORE target address missing'
grep -q '^DEV_LAN_MAC=00:0C:29:75:A6:D4$' config/topology.env.example || err 'CORE MAC missing'
grep -q '^PROD_LAN_IP=192\.168\.1\.122$' config/topology.env.example || err 'PROD target address missing'
grep -q '^PROD_LAN_MAC=00:0C:29:B5:F4:09$' config/topology.env.example || err 'PROD MAC missing'
grep -q '^PROD_LAN_STATUS=VERIFIED_REPOSITORY_BASELINE$' config/topology.env.example || err 'PROD baseline marker missing'

# Fixed host inventory and local DNS.
grep -q '48:4D:7E:D4:3A:C6=192.168.1.100=PoliceDBC-SEA' 30-DHCP-DNS-NTP.rsc || err 'PoliceDBC reservation missing'
grep -q '00:0C:29:75:A6:D4=192.168.1.123=core.zeaz.dev' 30-DHCP-DNS-NTP.rsc || err 'CORE reservation missing'
grep -q '00:0C:29:B5:F4:09=192.168.1.122=prod.zeaz.dev' 30-DHCP-DNS-NTP.rsc || err 'PROD reservation missing'
grep -q '00:0C:29:B7:22:AF=192.168.1.119=ha-a.zeaz.dev' 30-DHCP-DNS-NTP.rsc || err 'HA-A reservation missing'
grep -q '00:0C:29:72:EF:42=192.168.1.120=ha-b.zeaz.dev' 30-DHCP-DNS-NTP.rsc || err 'HA-B reservation missing'
grep -q '88:DC:96:53:0F:55=192.168.1.50=EWS1200D-10T' 30-DHCP-DNS-NTP.rsc || err 'EWS1200D reservation missing'
grep -q '88:DC:96:55:58:E4=192.168.1.51=RITRUECHAI-AP01' 30-DHCP-DNS-NTP.rsc || err 'RITRUECHAI-AP01 reservation missing'
grep -q '88:DC:96:55:58:E7=192.168.1.52=RITRUECHAI-AP02' 30-DHCP-DNS-NTP.rsc || err 'RITRUECHAI-AP02 reservation missing'
grep -q '88:DC:96:55:58:F0=192.168.1.53=BOONNAK-AP01' 30-DHCP-DNS-NTP.rsc || err 'BOONNAK-AP01 reservation missing'
grep -q '88:DC:96:55:58:DE=192.168.1.54=BOONNAK-AP02' 30-DHCP-DNS-NTP.rsc || err 'BOONNAK-AP02 reservation missing'
grep -q '88:DC:96:55:58:ED=192.168.1.55=SARASIN-AP02' 30-DHCP-DNS-NTP.rsc || err 'SARASIN-AP02 reservation missing'
grep -q '88:DC:96:55:58:EA=192.168.1.56=SARASIN-AP01' 30-DHCP-DNS-NTP.rsc || err 'SARASIN-AP01 reservation missing'
grep -q '88:DC:96:55:58:F3=192.168.1.57=PANKHONGCHUEN-AP01' 30-DHCP-DNS-NTP.rsc || err 'PANKHONGCHUEN-AP01 reservation missing'
grep -q '88:DC:96:55:58:E1=192.168.1.58=PANKHONGCHUEN-AP02' 30-DHCP-DNS-NTP.rsc || err 'PANKHONGCHUEN-AP02 reservation missing'
grep -q 'E4:90:2A:40:61:21=192.168.1.238=ZEAZ Wifi Repeater' 30-DHCP-DNS-NTP.rsc || err 'WiFi repeater reservation missing'
grep -Fq ':local desiredRanges "192.168.1.59-192.168.1.99,192.168.1.101-192.168.1.118,192.168.1.121-192.168.1.121,192.168.1.124-192.168.1.237,192.168.1.239-192.168.1.254"' 30-DHCP-DNS-NTP.rsc || err 'DHCP pool does not exclude all fixed infrastructure'
if grep -Eq '/ip dhcp-server lease set .*server=lan-dhcp' 30-DHCP-DNS-NTP.rsc; then err 'existing DHCP leases must not set textual server=lan-dhcp (RouterOS ambiguity risk)'; fi
grep -q 'wifi\.zeaz\.dev' 30-DHCP-DNS-NTP.rsc || err 'WiFi DNS record missing'
grep -q 'core\.zeaz\.dev' 30-DHCP-DNS-NTP.rsc || err 'CORE DNS record missing'
grep -q 'prod\.zeaz\.dev' 30-DHCP-DNS-NTP.rsc || err 'PROD DNS record missing'
grep -q 'ha-a\.zeaz\.dev' 30-DHCP-DNS-NTP.rsc || err 'HA-A DNS record missing'
grep -q 'ha-b\.zeaz\.dev' 30-DHCP-DNS-NTP.rsc || err 'HA-B DNS record missing'

# Ownership boundaries: active phases must preserve unrelated live state.
grep -Fq 'refusing implicit WAN/LAN topology takeover' 20-NETWORK-NORMALIZE.rsc || err 'network phase must fail closed on ether1 bridge conflicts'
grep -Fq 'already belongs to another bridge; refusing takeover' 20-NETWORK-NORMALIZE.rsc || err 'network phase must fail closed on bridge ownership conflicts'
grep -Fq 'list="WAN" and interface="DBC-Bridge-Local" and dynamic=no' 20-NETWORK-NORMALIZE.rsc || err 'network phase must ignore dynamic WAN-list detection entries'
grep -Fq 'list="LAN" and interface="ether1" and dynamic=no' 20-NETWORK-NORMALIZE.rsc || err 'network phase must ignore dynamic LAN-list detection entries'
grep -Fq 'Do not delete unrelated DHCP servers' 30-DHCP-DNS-NTP.rsc || err 'DHCP phase must document preservation of unowned DHCP servers'
grep -Fq 'global upstream DNS' 30-DHCP-DNS-NTP.rsc || err 'DNS phase must preserve upstream resolver state'
grep -Fq 'public key differs from verified contract' 40-WIREGUARD-SERVICES.rsc || err 'WireGuard phase must fail closed on peer identity drift'
grep -Fq 'listen-port differs from verified contract' 40-WIREGUARD-SERVICES.rsc || err 'WireGuard phase must fail closed on interface drift'
grep -Fq 'foreign rule exists in ZEAZ-PoliceDBC-INPUT' 50-FIREWALL-NAT.rsc || err 'managed firewall chains must reject foreign rules'
grep -Fq 'foreign rule exists in ZEAZ-PoliceDBC-SRCNAT' 50-FIREWALL-NAT.rsc || err 'managed NAT chain must reject foreign rules'
grep -Eq '/ip firewall (filter|nat) remove \[find where .*comment~|/ip firewall (filter|nat) remove \[find where .*comment=' 50-FIREWALL-NAT.rsc || err 'firewall cleanup must be restricted to zOS-owned comments'
if grep -Eq 'core\.zeaz\.internal.*192\.168\.1\.128|192\.168\.1\.128.*core\.zeaz\.internal' 30-DHCP-DNS-NTP.rsc; then err 'DHCP/DNS phase hard-codes obsolete CORE address'; fi

# Backup/apply/update safety.
grep -Fq 'controller backup completed before import phases' 10-BACKUP-SNAPSHOT.rsc || err 'backup phase must defer backup creation to controller'
grep -Fq 'OMEGA VERIFY PASS' 99-VERIFY-HEALTH.rsc || err 'verify phase must expose an explicit success sentinel'
grep -Fq 'desiredRanges' 99-VERIFY-HEALTH.rsc || err 'verify phase must assert the exact DHCP pool contract'
grep -Fq '88:DC:96:55:58:E7=192.168.1.52' 99-VERIFY-HEALTH.rsc || err 'verify phase must assert EnGenius fixed reservations'
grep -Fq 'upstream gateway unreachable' 99-VERIFY-HEALTH.rsc || err 'verify phase must fail when upstream reachability is lost'
grep -Fq 'internet IP unreachable' 99-VERIFY-HEALTH.rsc || err 'verify phase must fail when Internet reachability is lost'
grep -Fq 'public key mismatch' 99-VERIFY-HEALTH.rsc || err 'verify phase must assert WireGuard peer identity'
if grep -Eiq 'dont-encrypt=yes|system backup save' 10-BACKUP-SNAPSHOT.rsc; then err 'import phase must not create an unmanaged RouterOS binary backup'; fi
grep -q '^OMEGA_REQUIRE_DRY_RUN=1$' config/topology.env.example || err 'dry-run gate must be enabled by default'
grep -q '^OMEGA_REQUIRE_SAFE_MODE=1$' config/topology.env.example || err 'Safe Mode gate must be enabled by default'
grep -q 'OMEGA_REQUIRE_DRY_RUN' tools/deploy-phases.sh || err 'deploy script does not enforce dry-run gate'
grep -q 'OMEGA_REQUIRE_SAFE_MODE' tools/deploy-phases.sh || err 'deploy script does not enforce Safe Mode gate'
grep -Fq '[Safe Mode taken]' tools/omega-router.sh || err 'RouterOS apply helper does not require Safe Mode confirmation'
grep -Fq 'OMEGA_APPLY_PASS' tools/omega-router.sh || err 'RouterOS apply helper does not require phase success confirmation'
grep -Fq 'flock -n' tools/omega-router.sh || err 'Safe Mode apply must reject concurrent controller-side runs'
grep -Fq "| tee \"\$output_file\"" tools/omega-router.sh || err 'Safe Mode apply output must stream in real time'
grep -Fq 'Hijacking Safe Mode from someone' tools/omega-router.sh || err 'Safe Mode apply must surface stale/external Safe Mode ownership'
grep -Fq "printf '\\004'" tools/omega-router.sh || err 'Safe Mode failure path must explicitly send Ctrl-D rollback'
grep -Fq 'OMEGA_PHASE_PASS' tools/omega-router.sh || err 'Safe Mode apply must wait for per-phase success sentinels'
grep -Fq 'wait_for_marker' tools/omega-router.sh || err 'Safe Mode apply must wait for RouterOS responses before sending subsequent phases'
grep -Fq 'floating-undo=yes' tools/omega-router.sh || err 'Safe Mode apply must enforce a floating-undo history budget'
grep -Fq 'OMEGA_SAFE_BUDGET_FAIL' tools/omega-router.sh || err 'Safe Mode apply must fail before RouterOS history capacity is exhausted'
grep -Fq 'fingerprint)' tools/omega-router.sh || err 'router helper must expose deterministic target fingerprinting'
grep -Fq 'OMEGA_DRY_RUN_MAX_AGE_SECONDS' tools/deploy-phases.sh || err 'dry-run evidence must have a freshness limit'
grep -Fq 'target_fingerprint' tools/deploy-phases.sh || err 'dry-run evidence must be bound to the target router/runtime'
grep -Fq 'topology_sha256' tools/deploy-phases.sh || err 'dry-run evidence must be bound to topology configuration'
grep -Fq 'git_commit=' tools/deploy-phases.sh || err 'dry-run evidence must be bound to the reviewed git commit'
if grep -Fq 'if [[ "${OMEGA_REQUIRE_SAFE_MODE:-1}" == "1" ]]' tools/deploy-phases.sh; then err 'production apply must not retain a Safe Mode bypass branch'; fi
grep -Fq 'dont-encrypt=yes' tools/omega-router.sh && err 'router backup must not disable encryption'
grep -Fq 'encryption=aes-sha256' tools/omega-router.sh || err 'router backup must explicitly request AES-SHA256 encryption'
grep -Fq '/system package update set channel=' tools/routeros-auto-update.sh && err 'update-check must not persistently set RouterOS update channel'
grep -Fq 'RouterOS update did not change the running version' tools/routeros-auto-update.sh || err 'auto-update lacks post-reboot version-change verification'

# Fail-closed environment defaults.
grep -q '^PROD_ALLOW_PASSWORD=no$' prod/.env.example || err 'PROD SSH password authentication must fail closed in template'
grep -q '^PROD_ALLOW_DEPLOY=0$' prod/.env.example || err 'PROD live deploy must fail closed in template'
grep -q '^OMEGA_ALLOW_LIVE_APPLY=0$' .env.example || err 'root .env.example must fail closed for live apply'
grep -q '^OMEGA_AUTO_ROUTEROS_UPDATE=0$' .env.example || err 'root .env.example must fail closed for auto update'
grep -q '^OMEGA_ALLOW_ROUTER_REBOOT=0$' .env.example || err 'root .env.example must fail closed for router reboot'
grep -q '^SSH_ALLOW_PASSWORD=no$' core/.env.example || err 'core/.env.example must disable SSH password authentication by default'
grep -q '^OMEGA_ALLOW_LIVE_APPLY=0$' zOS/.env.example || err 'zOS/.env.example must fail closed for live apply'
grep -q '^RUNNER_VM_HOSTNAME=zeaz$' runner/.env.example || err 'runner VM hostname contract missing'
grep -q '^RUNNER_NAME=zOS-Runner$' runner/.env.example || err 'runner name contract missing'
grep -q '^RUNNER_ALLOW_UNTRUSTED_FORKS=0$' runner/.env.example || err 'runner env must reject untrusted forks by default'
grep -q '^RUNNER_ALLOW_LIVE_ROUTEROS_APPLY=0$' runner/.env.example || err 'runner env must block live RouterOS apply by default'
grep -q '^ROUTEROS_UPDATE_CHANNEL=stable$' config/topology.env.example || err 'stable RouterOS update channel missing'
grep -q '^OMEGA_AUTO_ROUTEROS_UPDATE=0$' config/topology.env.example || err 'safe auto-update default missing'
grep -q '^OMEGA_ALLOW_ROUTER_REBOOT=0

if grep -Eiq '192\.168\.205\.251|bridge-lan|core\.zeaz\.internal|192\.168\.1\.128' 00-PRECHECK.rsc 20-NETWORK-NORMALIZE.rsc 30-DHCP-DNS-NTP.rsc config/topology.env.example README.md ENVIRONMENTS.md; then
  err 'active production sources still contain legacy topology values'
fi

if [[ -f core/install-ssh-key.sh ]]; then
  grep -Fq 'ssh-keygen -y' core/install-ssh-key.sh || err 'SSH installer must validate private key material with ssh-keygen -y'
  grep -Fq 'ssh-keygen -lf' core/install-ssh-key.sh || err 'SSH installer must validate public key fingerprint'
  ! grep -Eq 'cvsz@192\.168\.1\.100|cvsz@192\.168\.1\.123' core/install-ssh-key.sh || err 'SSH installer contains a hard-coded target address'
fi

if grep -Eiq 'allow-unauthenticated|trusted[[:space:]]*=[[:space:]]*yes|Acquire::AllowInsecureRepositories[[:space:]]*=[[:space:]]*true' core/install.sh; then err 'core/install.sh contains an APT signature-bypass pattern'; fi
grep -Fq "SSH_ALLOW_PASSWORD=\"\${SSH_ALLOW_PASSWORD:-no}\"" core/install.sh || err 'CORE SSH password authentication is not fail-closed by default'
grep -Fq 'D55C0D1AC78A8D8126CB631CFC9CA96ACA026560' core/install.sh || err 'HashiCorp APT signing-key fingerprint is not pinned'
grep -Fq 'Password authentication is disabled by default' core/install.sh || err 'CORE installer lacks authorized_keys lockout prevention'
grep -Fq 'trap - RETURN' core/install.sh || err 'HashiCorp temp cleanup trap is not self-clearing'

# Third-party GitHub Actions must be immutable commit pins, not floating major tags.
if grep -RInE --include='*.yml' --include='*.yaml' 'uses:[[:space:]]+[^[:space:]#]+@v[0-9]+' .github/workflows; then
  err 'GitHub Actions workflows contain floating major-version action references'
fi

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t shells < <(find tools zOS core -type f \( -name '*.sh' -o -path 'zOS/bin/zos' \) -print)
  (("${#shells[@]}" == 0)) || shellcheck "${shells[@]}"
else
  echo 'WARN: shellcheck not installed; shell validation skipped'
fi

(( fail == 0 )) || exit 1
echo 'Repository safety validation PASS'
 config/topology.env.example || err 'safe reboot default missing'
grep -q '^OMEGA_DRY_RUN_MAX_AGE_SECONDS=3600

if grep -Eiq '192\.168\.205\.251|bridge-lan|core\.zeaz\.internal|192\.168\.1\.128' 00-PRECHECK.rsc 20-NETWORK-NORMALIZE.rsc 30-DHCP-DNS-NTP.rsc config/topology.env.example README.md ENVIRONMENTS.md; then
  err 'active production sources still contain legacy topology values'
fi

if [[ -f core/install-ssh-key.sh ]]; then
  grep -Fq 'ssh-keygen -y' core/install-ssh-key.sh || err 'SSH installer must validate private key material with ssh-keygen -y'
  grep -Fq 'ssh-keygen -lf' core/install-ssh-key.sh || err 'SSH installer must validate public key fingerprint'
  ! grep -Eq 'cvsz@192\.168\.1\.100|cvsz@192\.168\.1\.123' core/install-ssh-key.sh || err 'SSH installer contains a hard-coded target address'
fi

if grep -Eiq 'allow-unauthenticated|trusted[[:space:]]*=[[:space:]]*yes|Acquire::AllowInsecureRepositories[[:space:]]*=[[:space:]]*true' core/install.sh; then err 'core/install.sh contains an APT signature-bypass pattern'; fi
grep -Fq "SSH_ALLOW_PASSWORD=\"\${SSH_ALLOW_PASSWORD:-no}\"" core/install.sh || err 'CORE SSH password authentication is not fail-closed by default'
grep -Fq 'D55C0D1AC78A8D8126CB631CFC9CA96ACA026560' core/install.sh || err 'HashiCorp APT signing-key fingerprint is not pinned'
grep -Fq 'Password authentication is disabled by default' core/install.sh || err 'CORE installer lacks authorized_keys lockout prevention'
grep -Fq 'trap - RETURN' core/install.sh || err 'HashiCorp temp cleanup trap is not self-clearing'

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t shells < <(find tools zOS core -type f \( -name '*.sh' -o -path 'zOS/bin/zos' \) -print)
  (("${#shells[@]}" == 0)) || shellcheck "${shells[@]}"
else
  echo 'WARN: shellcheck not installed; shell validation skipped'
fi

(( fail == 0 )) || exit 1
echo 'Repository safety validation PASS'
 config/topology.env.example || err 'dry-run freshness default missing'
grep -Fq 'config/topology.env' .dockerignore || err '.dockerignore must exclude populated topology config'
grep -Fq 'backups' .dockerignore || err '.dockerignore must exclude local backups'
grep -Fq 'state' .dockerignore || err '.dockerignore must exclude runtime state'
grep -Fq 'git archive --format=tar HEAD' Makefile || err 'release packaging must use tracked git content only'
grep -Fq 'FROM alpine:3.22.6@sha256:abd29214470819ed7667c87c1ceebc89aae766453a5b3cc09e8a52b9f796fd5a' zOS/Dockerfile || err 'controller base image must be pinned to the reviewed Alpine index digest'
grep -Fq 'OMEGA_BACKUP_SECRET_DIR' tools/omega-router.sh || err 'backup decryption secrets must be stored separately from backup artifacts'
grep -Fq 'exists more than once; refusing ambiguous management' 30-DHCP-DNS-NTP.rsc || err 'DHCP phase must reject duplicate managed objects'
if grep -Fq "tar --exclude='./.git'" Makefile; then err 'release packaging must not archive the working tree'; fi
grep -Fq 'project-wide LICENSE is not declared' Makefile || err 'release must fail closed while project license is undeclared'
grep -Fq 'aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25' .github/workflows/security-scan.yml || err 'Trivy action must be pinned to reviewed commit'
grep -Fq 'package-ecosystem: github-actions' .github/dependabot.yml || err 'Dependabot must track GitHub Actions'
grep -Fq 'package-ecosystem: docker' .github/dependabot.yml || err 'Dependabot must track Docker base images'

if grep -Eiq '192\.168\.205\.251|bridge-lan|core\.zeaz\.internal|192\.168\.1\.128' 00-PRECHECK.rsc 20-NETWORK-NORMALIZE.rsc 30-DHCP-DNS-NTP.rsc config/topology.env.example README.md ENVIRONMENTS.md; then
  err 'active production sources still contain legacy topology values'
fi

if [[ -f core/install-ssh-key.sh ]]; then
  grep -Fq 'ssh-keygen -y' core/install-ssh-key.sh || err 'SSH installer must validate private key material with ssh-keygen -y'
  grep -Fq 'ssh-keygen -lf' core/install-ssh-key.sh || err 'SSH installer must validate public key fingerprint'
  ! grep -Eq 'cvsz@192\.168\.1\.100|cvsz@192\.168\.1\.123' core/install-ssh-key.sh || err 'SSH installer contains a hard-coded target address'
fi

if grep -Eiq 'allow-unauthenticated|trusted[[:space:]]*=[[:space:]]*yes|Acquire::AllowInsecureRepositories[[:space:]]*=[[:space:]]*true' core/install.sh; then err 'core/install.sh contains an APT signature-bypass pattern'; fi
grep -Fq "SSH_ALLOW_PASSWORD=\"\${SSH_ALLOW_PASSWORD:-no}\"" core/install.sh || err 'CORE SSH password authentication is not fail-closed by default'
grep -Fq 'D55C0D1AC78A8D8126CB631CFC9CA96ACA026560' core/install.sh || err 'HashiCorp APT signing-key fingerprint is not pinned'
grep -Fq 'Password authentication is disabled by default' core/install.sh || err 'CORE installer lacks authorized_keys lockout prevention'
grep -Fq 'trap - RETURN' core/install.sh || err 'HashiCorp temp cleanup trap is not self-clearing'

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t shells < <(find tools zOS core -type f \( -name '*.sh' -o -path 'zOS/bin/zos' \) -print)
  (("${#shells[@]}" == 0)) || shellcheck "${shells[@]}"
else
  echo 'WARN: shellcheck not installed; shell validation skipped'
fi

(( fail == 0 )) || exit 1
echo 'Repository safety validation PASS'
