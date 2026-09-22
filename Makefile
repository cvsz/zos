SHELL := /usr/bin/env bash

.PHONY: all validate docs evidence security-evidence release-check release-package release status audit backup dry-run apply verify e2e migrate-legacy-dhcp wifi-status core-status core-check core-repair core-find-conflict zos zos-doctor zos-install update-check update-notify update-auto update-monitor-install

all: validate docs evidence security-evidence zos

release-check: all
	@test -s zOS/VERSION
	@grep -Fq '## Unreleased' CHANGELOG.md
	@test -f LICENSE || { echo "Release blocked: project-wide LICENSE is not declared." >&2; exit 2; }
	@git diff --quiet && git diff --cached --quiet || { echo "Release blocked: tracked working tree is dirty." >&2; exit 2; }
	@test "$$(git branch --show-current)" = main || { echo "Release blocked: releases must be created from main." >&2; exit 2; }
	@git fetch --quiet origin main
	@test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || { echo "Release blocked: local HEAD does not match origin/main." >&2; exit 2; }
	@echo "Release checks passed for zOS $$(tr -d '[:space:]' < zOS/VERSION)"

release-package: release-check
	@set -euo pipefail; version="$(tr -d '[:space:]' < zOS/VERSION)"; stage="dist/zos-mikrotik-$version"; rm -rf "$stage"; mkdir -p "$stage"; git archive --format=tar HEAD | tar -C "$stage" -xf -; tar -C dist -czf "dist/zos-mikrotik-$version.tar.gz" "zos-mikrotik-$version"; sha256sum "dist/zos-mikrotik-$version.tar.gz" > "dist/zos-mikrotik-$version.tar.gz.sha256"; echo "Built tracked-only dist/zos-mikrotik-$version.tar.gz"

release: release-package
	@set -euo pipefail; version="$$(tr -d '[:space:]' < zOS/VERSION)"; tag="zos-v$$version"; test "$${RELEASE_CONFIRM:-0}" = 1 || { echo "Refusing release: rerun with RELEASE_CONFIRM=1" >&2; exit 2; }; git rev-parse "$$tag" >/dev/null 2>&1 || git tag -s "$$tag" -m "zOS $$version"; git push origin "$$tag"; gh release create "$$tag" "dist/zos-mikrotik-$$version.tar.gz" "dist/zos-mikrotik-$$version.tar.gz.sha256" --title "zOS $$version" --generate-notes

validate:
	./tools/validate-repo.sh
	python3 tools/validate-docs.py

docs:
	python3 tools/validate-docs.py

evidence:
	python3 tools/validate-evidence.py

security-evidence:
	python3 tools/generate-security-evidence.py --out artifacts/security

status:
	./tools/omega-router.sh status

audit:
	./tools/omega-router.sh audit

backup:
	./tools/omega-router.sh backup

dry-run:
	./tools/deploy-phases.sh dry-run

apply:
	@echo "Apply requires RouterOS Safe Mode and OMEGA_ALLOW_LIVE_APPLY=1"
	./tools/deploy-phases.sh apply

verify:
	./tools/deploy-phases.sh verify

migrate-legacy-dhcp:
	@echo "Legacy DHCP quarantine requires OMEGA_ALLOW_LEGACY_DHCP_MIGRATION=1 and OMEGA_ALLOW_LIVE_APPLY=1"
	./tools/migrate-legacy-dhcp.sh

wifi-status:
	./tools/omega-router.sh wifi-single-network-status

e2e:
	./tools/e2e-check.sh

core-status:
	./tools/core-network-repair.sh status

core-check:
	./tools/core-network-repair.sh check

core-repair:
	./tools/core-network-repair.sh repair-runtime

core-find-conflict:
	./tools/core-network-repair.sh find-conflict

zos:
	./zOS/bin/zos help

zos-doctor:
	./zOS/bin/zos doctor

zos-install:
	./zOS/install.sh

update-check:
	./tools/routeros-auto-update.sh check

update-notify:
	./tools/routeros-auto-update.sh notify

update-auto:
	@echo "Automatic RouterOS install requires OMEGA_AUTO_ROUTEROS_UPDATE=1 and OMEGA_ALLOW_ROUTER_REBOOT=1"
	./tools/routeros-auto-update.sh check-and-update

update-monitor-install:
	./tools/install-update-monitor.sh
