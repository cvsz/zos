# Documentation Index

This file defines the documentation map and ownership model for `cvsz/zos`.

## Canonical project documents

| Document | Purpose |
|---|---|
| `README.md` | project entry point and quick start |
| `AGENTS.md` | canonical automated-agent / production-safety contract |
| `ENVIRONMENTS.md` | environment and topology certainty model |
| `SECURITY.md` | security controls and vulnerability reporting |
| `CONTRIBUTING.md` | contribution workflow |
| `GOVERNANCE.md` | decision and exception model |
| `MAINTAINERS.md` | maintainership and review responsibilities |
| `SUPPORT.md` | support/issue hygiene |
| `CHANGELOG.md` | notable repository/operational changes |
| `CHECKLIST.md` | merge and production acceptance checklist |

## Architecture and operations

| Document | Purpose |
|---|---|
| `docs/ARCHITECTURE.md` | layers, trust boundaries, data flows |
| `docs/INSTALLATION.md` | controller/bootstrap installation |
| `docs/RUNBOOK.md` | end-to-end operator sequence |
| `docs/NETWORK-RECOVERY.md` | CORE route/WireGuard recovery |
| `docs/SSH-HARDENING.md` | SSH key-only baseline |
| `docs/DISASTER-RECOVERY.md` | rollback and service restoration |
| `docs/PRODUCTION-READINESS.md` | repository vs runtime acceptance |
| `docs/PRODUCTION-MIGRATION.md` | legacy-to-current topology guidance |
| `docs/LEGACY-DHCP-MIGRATION.md` | runbook สำหรับ quarantine legacy DHCP pools/networks แบบ one-shot และ fail-closed |
| `docs/WIFI-SINGLE-NETWORK.md` | EWS1200D + EWS310AP profile แบบ 1 SSID / 1 subnet / untagged พร้อม roaming baseline |
| `docs/ROUTEROS-LAB-TEST-PLAN.md` | isolated RouterOS safety test matrix and exit criteria |
| `docs/SELF_HOSTED_RUNNER.md` | Windows runner lifecycle and security |
| `runner/README.md` | Windows runner VM local environment reference |
| `docs/zOS.md` | CLI/control-plane operations |
| `prod/README.md` | production host inventory and discovery procedure |
| `cloudflare/README.md` | optional Cloudflare publication/access boundary and safety gates |

## GitHub, test, release, and lifecycle

| Document | Purpose |
|---|---|
| `docs/GITHUB-OPERATIONS.md` | PR/CI/runner/GHCR operations |
| `docs/GITHUB-SETTINGS.md` | recommended repository settings/rules |
| `docs/TESTING.md` | validation matrix and evidence boundaries |
| `docs/RELEASES.md` | tags, artifacts, packages, rollback |
| `docs/ROADMAP.md` | current planned work without claiming deployment |
| `docs/LICENSING.md` | project-license status and third-party boundary |
| `docs/CI-TROUBLESHOOTING.md` | common failure signatures |
| `docs/EVIDENCE-MATRIX.md` | committed/generated evidence model |

## Environment templates

| Template | Purpose |
|---|---|
| `.env.example` | operator/developer override reference |
| `config/topology.env.example` | canonical topology/runtime template |
| `config/wifi-single-network.env.example` | secret-free single-network Wi-Fi controller policy |
| `core/.env.example` | CORE bootstrap/recovery options |
| `zOS/.env.example` | zOS runtime/update-policy options |
| `prod/.env.example` | PROD host identity/bootstrap reference |
| `runner/.env.example` | Windows `zeaz` / `zOS-Runner` identity and trust posture |
| `cloudflare/config.env.example` | secret-free Cloudflare connector/origin template |

Templates must remain secret-free and fail-closed. Real `.env` files are local-only.

## Agent adapter files

`CODEX.md`, `CLAUDE.md`, `GEMINI.md`, `OPENCODE.md`, `ZED.md`, and `DMUX.md` point back to `AGENTS.md` and add only surface-specific notes.

## Vendored documentation boundary

`skills/routeros-*/` is upstream-derived RouterOS skill documentation. Do not blanket-rewrite those Markdown files as project documentation. Preserve provenance and upstream meaning; make only deliberate sync or safety adaptations and document them in `skills/README.md` / `THIRD_PARTY_NOTICES.md`.

## Documentation validation

`make docs` checks required project documents, repository-name drift, and relative local Markdown links. It does not prove external URLs are available or validate semantic correctness of vendored upstream content.
