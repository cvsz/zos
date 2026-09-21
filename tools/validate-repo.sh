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
  docs/TESTING.md docs/RELEASES.md docs/ROADMAP.md docs/LICENSING.md docs/LEGACY-DHCP-MIGRATION.md
  cloudflare/README.md cloudflare/config.env.example
  .github/PULL_REQUEST_TEMPLATE.md .github/CODEOWNERS
  .env.example core/.env.example zOS/.env.example runner/.env.example prod/.env.example config/topology.env.example
  runner/README.md prod/README.md tools/validate-docs.py tools/omega-router.sh tools/deploy-phases.sh tools/routeros-safe-session.py tools/test-routeros-safe-session.py
  tools/migrate-legacy-dhcp.sh migrations/20260921-legacy-dhcp-quarantine.rsc
  tools/core-network-repair.sh tools/routeros-auto-update.sh tools/e2e-check.sh
  tools/install-controller.sh tools/install-update-monitor.sh core/install.sh core/install-ssh-key.sh core/README.md
  zOS/README.md zOS/VERSION zOS/Dockerfile zOS/bin/zos zOS/install.sh .dockerignore
  .github/workflows/validate.yml .github/workflows/zos-build.yml
  .github/workflows/evidence-validation.yml .github/workflows/routeros-skills.yml
  .github/workflows/security-scan.yml .github/dependabot.yml
)
for f in "${required[@]}"; do [[ -f "$f" ]] || err "missing required file: $f"; done
python3 -m py_compile tools/routeros-safe-session.py tools/test-routeros-safe-session.py || err 'RouterOS Safe Mode session driver failed Python syntax validation'
python3 tools/test-routeros-safe-session.py || err 'RouterOS Safe Mode session regression tests failed'

grep -q '^CF_CONNECTOR_HOST=core\.zeaz\.dev$' cloudflare/config.env.example || err 'Cloudflare connector template is missing the approved CORE host'
grep -q 'Cloudflare' cloudflare/README.md || err 'Cloudflare integration documentation is missing'
if grep -Eiq '(^|_)(TOKEN|SECRET|PASSWORD|PRIVATE_KEY)=.+' cloudflare/config.env.example; then err 'Cloudflare template contains a populated credential'; fi
grep -Fq 'cloudflare/config.env' .gitignore || err 'populated Cloudflare config is not ignored'

executables=(core/install.sh tools/validate-repo.sh tools/omega-router.sh tools/deploy-phases.sh tools/migrate-legacy-dhcp.sh tools/core-network-repair.sh tools/routeros-auto-update.sh tools/e2e-check.sh tools/install-controller.sh tools/install-update-monitor.sh zOS/bin/zos zOS/install.sh)
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
grep -Fq 'enabled DHCP server exists on WAN ether1' 00-PRECHECK.rsc || err 'precheck must reject WAN-side DHCP servers'
grep -Fq 'legacy 192.168.0.0/24 address remains on DBC-Bridge-Local' 00-PRECHECK.rsc || err 'precheck must reject legacy LAN subnet drift'
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
grep -Eq 'remove \[find where chain="ZEAZ-PoliceDBC-(INPUT|FORWARD|SRCNAT)" and comment~"\^PoliceDBC:"\]' 50-FIREWALL-NAT.rsc || err 'firewall cleanup must be restricted to zOS-owned comments'
if grep -Eq 'core\.zeaz\.internal.*192\.168\.1\.128|192\.168\.1\.128.*core\.zeaz\.internal' 30-DHCP-DNS-NTP.rsc; then err 'DHCP/DNS phase hard-codes obsolete CORE address'; fi

# Backup/apply/update safety.
grep -Fq 'controller backup completed before import phases' 10-BACKUP-SNAPSHOT.rsc || err 'backup phase must defer backup creation to controller'
if grep -Eiq 'dont-encrypt=yes|system backup save' 10-BACKUP-SNAPSHOT.rsc; then err 'import phase must not create an unmanaged RouterOS binary backup'; fi
grep -q '^OMEGA_REQUIRE_DRY_RUN=1$' config/topology.env.example || err 'dry-run gate must be enabled by default'
grep -q '^OMEGA_REQUIRE_SAFE_MODE=1$' config/topology.env.example || err 'Safe Mode gate must be enabled by default'
grep -q 'OMEGA_REQUIRE_DRY_RUN' tools/deploy-phases.sh || err 'deploy script does not enforce dry-run gate'
grep -q 'OMEGA_REQUIRE_SAFE_MODE' tools/deploy-phases.sh || err 'deploy script does not enforce Safe Mode gate'
grep -Fq 'Safe Mode taken' tools/omega-router.sh || err 'RouterOS apply helper must accept documented Safe Mode confirmation'
grep -Fq 'Taking Safe Mode session' tools/omega-router.sh || err 'RouterOS apply helper must accept RouterOS 7.25 Safe Mode confirmation'
grep -Fq 'OMEGA_APPLY_PASS' tools/omega-router.sh || err 'RouterOS apply helper does not require phase success confirmation'
grep -Fq 'flock -n' tools/omega-router.sh || err 'Safe Mode apply must reject concurrent controller-side runs'
grep -Fq 'tools/routeros-safe-session.py' tools/omega-router.sh || err 'Safe Mode apply must use the dedicated session driver'
grep -Fq 'b"] >"' tools/routeros-safe-session.py || err 'Safe Mode driver must wait for the RouterOS CLI prompt before Ctrl-X'
grep -Fq 'b"Taking Safe Mode session... Success!"' tools/routeros-safe-session.py || err 'Safe Mode driver must accept RouterOS 7.25 Safe Mode confirmation'
grep -Fq 'receive_buffer = bytearray()' tools/routeros-safe-session.py || err 'Safe Mode driver must preserve one receive buffer across handshake stages'
grep -Fq 'read_until(proc, evidence, receive_buffer, (b"<SAFE>",)' tools/routeros-safe-session.py || err 'Safe Mode driver must reuse the receive buffer for the SAFE prompt'
grep -Fq 'test_preloaded_safe_prompt_survives_previous_match' tools/test-routeros-safe-session.py || err 'Safe Mode same-chunk regression test missing'
grep -Fq 'b"Hijacking Safe Mode from someone"' tools/routeros-safe-session.py || err 'Safe Mode driver must fail closed on hijack prompts'
grep -Fq 'def rollback(' tools/routeros-safe-session.py || err 'Safe Mode driver rollback routine missing'
grep -Fq 'b"\x04"' tools/routeros-safe-session.py || err 'Safe Mode driver must request Ctrl-D rollback on failure'
grep -Fq ':put ("OMEGA_APPLY_" . "PASS")' tools/omega-router.sh || err 'Safe Mode success sentinel must not appear literally in echoed RouterOS input'
grep -Fq "cmd=':do {'" tools/omega-router.sh || err 'Safe Mode apply must wrap all imports in one RouterOS transaction'
grep -Fq '/quit' tools/omega-router.sh || err 'Safe Mode apply success path must explicitly release the session'
grep -Fq 'fingerprint) fingerprint' tools/omega-router.sh || err 'dry-run binding requires router fingerprint support'
grep -Fq 'target_manifest' tools/deploy-phases.sh || err 'dry-run marker must bind to the live target fingerprint'
grep -Fq 'OMEGA_DRY_RUN_MAX_AGE_SECONDS' tools/deploy-phases.sh || err 'dry-run marker must enforce freshness'
grep -Fq 'production Safe Mode enforcement cannot be disabled' tools/deploy-phases.sh || err 'production apply must not expose a Safe Mode bypass'
grep -Fq 'OMEGA VERIFY PASS' 99-VERIFY-HEALTH.rsc || err 'health phase must provide an assertion success sentinel'
grep -Fq 'lan-pool ranges do not match production contract' 99-VERIFY-HEALTH.rsc || err 'health phase must assert the DHCP pool contract'
grep -Fq 'lan-pool has unverified next-pool=' 30-DHCP-DNS-NTP.rsc || err 'DHCP phase must fail closed on unverified next-pool drift'
grep -Fq 'lan-pool range migration failed:' 30-DHCP-DNS-NTP.rsc || err 'DHCP phase must surface RouterOS pool migration errors'
grep -Fq 'lan-pool has unexpected next-pool=' 99-VERIFY-HEALTH.rsc || err 'health phase must assert no fallback DHCP pool'

# Guarded one-shot legacy DHCP quarantine migration.
grep -Fq 'migrate-legacy-dhcp:' Makefile || err 'Makefile must expose the guarded legacy DHCP migration target'
grep -Fq 'OMEGA_ALLOW_LEGACY_DHCP_MIGRATION' tools/migrate-legacy-dhcp.sh || err 'legacy DHCP migration must require a dedicated explicit opt-in'
grep -Fq 'OMEGA_ALLOW_LIVE_APPLY' tools/migrate-legacy-dhcp.sh || err 'legacy DHCP migration must also require live-apply opt-in'
grep -Fq "\"\$CTL\" backup" tools/migrate-legacy-dhcp.sh || err 'legacy DHCP migration must create a backup before mutation'
grep -Fq "\"\$CTL\" dry-run \"\$MIGRATION\"" tools/migrate-legacy-dhcp.sh || err 'legacy DHCP migration must syntax dry-run before mutation'
grep -Fq "\"\$CTL\" apply-safe \"\$MIGRATION\"" tools/migrate-legacy-dhcp.sh || err 'legacy DHCP migration must execute in RouterOS Safe Mode'
grep -Fq 'legacy-dhcp-status' tools/migrate-legacy-dhcp.sh || err 'legacy DHCP migration must perform post-change read-only status'
grep -Fq 'wifi-pool has active usage' migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration must reject active wifi-pool usage'
grep -Fq 'zeaz-pool has active usage' migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration must reject active zeaz-pool usage'
grep -Fq 'DHCP server still exists on WAN ether1' migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration must reject WAN DHCP service'
grep -Fq 'legacy 192.168.0.x DHCP lease is still present' migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration must reject 192.168.0.x leases'
grep -Fq 'legacy 192.168.10.x DHCP lease is still present' migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration must reject 192.168.10.x leases'
grep -Fq "/ip pool set \$lanPool next-pool=none" migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration must disconnect lan-pool fallback'
grep -Fq "/ip dhcp-server network set \$net1 dns-server=192.168.1.1" migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration must converge LAN DHCP DNS to RouterOS'
grep -Fq 'LEGACY DHCP QUARANTINE PASS' migrations/20260921-legacy-dhcp-quarantine.rsc || err 'legacy migration success assertion missing'
if grep -Eq '/ip pool remove|remove \[find\]' migrations/20260921-legacy-dhcp-quarantine.rsc; then err 'legacy DHCP migration must not delete pool objects or use broad remove expressions'; fi
grep -Fq 'https://manual.mikrotik.com/llms.txt' docs/LEGACY-DHCP-MIGRATION.md || err 'legacy DHCP runbook must cite the official MikroTik manual index'
grep -Fq 'https://manual.mikrotik.com/docs/management-tools/console/' docs/LEGACY-DHCP-MIGRATION.md || err 'legacy DHCP runbook must cite official Safe Mode documentation'
grep -Fq 'https://manual.mikrotik.com/docs/network-management/dhcp/' docs/LEGACY-DHCP-MIGRATION.md || err 'legacy DHCP runbook must cite official DHCP documentation'
grep -Fq '88:DC:96:55:58:E7=192.168.1.52=RITRUECHAI-AP02' 99-VERIFY-HEALTH.rsc || err 'health phase must assert EnGenius reservations'
grep -Fq 'unowned rule found in ZEAZ-PoliceDBC-INPUT' 50-FIREWALL-NAT.rsc || err 'firewall phase must reject foreign rules in owned chains'
grep -Fq 'CORE WireGuard peer public key differs from verified contract' 40-WIREGUARD-SERVICES.rsc || err 'WireGuard phase must validate peer identity'
grep -Fq 'git archive --format=tar HEAD' Makefile || err 'release packaging must include tracked files only'
grep -Fq 'Release blocked: project-wide LICENSE is not declared.' Makefile || err 'release must fail closed until a project license is declared'
grep -Fq 'config/topology.env' .dockerignore || err 'Docker build context must exclude populated topology'
grep -Fq 'backups' .dockerignore || err 'Docker build context must exclude backups'
grep -Fq 'state' .dockerignore || err 'Docker build context must exclude runtime state'
grep -Fq 'expected advertised version' tools/routeros-auto-update.sh || err 'auto-update must verify the advertised target version'
grep -Fq 'OMEGA_BACKUP_PASSWORD_DIR' tools/omega-router.sh || err 'backup password storage must be separable from backup artifacts'
if grep -Fq "\"\$CORE\" check || true" zOS/bin/zos; then err 'zOS doctor must propagate CORE structural failures'; fi
grep -Fq 'dont-encrypt=yes' tools/omega-router.sh && err 'router backup must not disable encryption'
grep -Fq 'encryption=aes-sha256' tools/omega-router.sh || err 'router backup must explicitly request AES-SHA256 encryption'
grep -Fq '/system package update set channel=' tools/routeros-auto-update.sh && err 'update-check must not persistently set RouterOS update channel'
grep -Fq 'RouterOS update did not change the running version' tools/routeros-auto-update.sh || err 'auto-update lacks post-reboot version-change verification'

# Supply-chain and clean-rebuild safety.
if grep -RInE "uses:[[:space:]]*[^@[:space:]]+@(v[0-9]+|main|master|latest)([[:space:]]|$)" .github/workflows; then
  err 'GitHub Actions must be pinned to immutable commit SHAs'
fi
grep -Eq '^FROM .+@sha256:[0-9a-f]{64}$' zOS/Dockerfile || err 'controller base image must be pinned by digest'
grep -Fq 'aquasecurity/trivy-action@' .github/workflows/security-scan.yml || err 'Trivy security scan workflow missing'
grep -Fq 'severity: HIGH,CRITICAL' .github/workflows/security-scan.yml || err 'Trivy HIGH/CRITICAL gate missing'
grep -Fq 'format: cyclonedx' .github/workflows/security-scan.yml || err 'package-aware CycloneDX SBOM generation missing'
grep -Fq 'controller-image.cdx.json' .github/workflows/security-scan.yml || err 'controller image SBOM artifact path missing'
grep -Fq 'trivy-filesystem.sarif' .github/workflows/security-scan.yml || err 'filesystem vulnerability SARIF artifact missing'
grep -Fq 'trivy-controller-image.sarif' .github/workflows/security-scan.yml || err 'controller image vulnerability SARIF artifact missing'
grep -Fq 'retention-days: 30' .github/workflows/security-scan.yml || err 'security evidence retention policy missing'
grep -Fq 'package-ecosystem: github-actions' .github/dependabot.yml || err 'Dependabot GitHub Actions updates missing'
grep -Fq 'package-ecosystem: docker' .github/dependabot.yml || err 'Dependabot Docker updates missing'
grep -Fq 'GOLDEN REINSTALL REFUSED: lan-pool already exists' reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc || err 'golden reinstall must refuse configured DHCP targets'
grep -Fq '/interface wireguard add name=wg-remote' reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc || err 'golden reinstall must converge WireGuard baseline'
grep -Fq 'ZEAZ-PoliceDBC-INPUT' reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc || err 'golden reinstall must converge managed firewall baseline'
grep -Fq 'OMEGA_BACKUP_PASSWORD_DIR=/var/lib/zeaz-mikrotik/secrets' systemd/omega-routeros-update.service || err 'update service must isolate backup secret storage'
grep -Fq 'SECRET_DIR=/var/lib/zeaz-mikrotik/secrets' tools/install-update-monitor.sh || err 'update monitor installer must provision isolated secret storage'

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
grep -q '^OMEGA_ALLOW_ROUTER_REBOOT=0$' config/topology.env.example || err 'safe reboot default missing'

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