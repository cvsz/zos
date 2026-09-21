# GitHub Operations

## Repository

Canonical repository: `cvsz/zos`; default branch: `main`.

## Change flow

1. create a focused branch from current `main`;
2. implement code/evidence/docs together;
3. run local validation;
4. open a PR using the template;
5. require CI and review conversations to pass;
6. merge only after required checks/review pass; independently verify that the account-side main ruleset is enabled;
7. delete the head branch when complete.

## Workflows

| Workflow | Purpose | Privilege posture |
|---|---|---|
| `validate.yml` | repository/static/docs/safety checks | read-only source |
| `evidence-validation.yml` | deterministic corpus + generated security evidence | read-only source/artifact upload |
| `routeros-skills.yml` | vendored skill validation + optional trusted runner probe | no live apply |
| `zos-build.yml` | tarball + OCI build/publish | package write on non-PR events |

Normal workflows must not receive production router credentials or perform live production mutation.

## Pull requests

PRs must state scope, risk, validation, documentation impact, recovery/rollback, and live-system impact. Production-sensitive changes must explain how management access is preserved.

For Cloudflare changes, the PR must identify each hostname, private origin, connector host, Access requirement, and whether live DNS/Tunnel/Access state changed. A repository check does not verify those external systems.

## Self-hosted runner

`zOS-Runner` is trusted infrastructure. Use labels `[self-hosted, Windows, X64]`; never send untrusted fork code to it. Keep one listener session.

## GHCR

Controller image:

~~~text
ghcr.io/cvsz/mikrotik-zos
~~~

Release/package visibility is an owner decision. Do not equate a successful image build with live deployment.

## Releases

Use `docs/RELEASES.md`. Tagging/package publication and live RouterOS change are separate operations.

## Incidents

For CI/runtime failures, capture sanitized logs and link the exact workflow run/commit. Security-sensitive incidents use `SECURITY.md`; operational issues use `SUPPORT.md`.

## Administrative settings

See `docs/GITHUB-SETTINGS.md` for recommended rulesets, workflow permissions, security features, and community-health settings.


## Current administrative verification gap

Repository code can recommend and validate workflow behavior, but it cannot prove or enforce GitHub account-side rulesets from source alone. Before production acceptance, verify that `main` blocks force-push/delete and requires the selected validation/build/security checks. Also verify repository homepage, Wiki, and merged-branch cleanup settings against `docs/GITHUB-SETTINGS.md`.
