# Security Policy

## Security model

zOS is privileged infrastructure automation. Its primary security objectives are to preserve management access, prevent accidental destructive RouterOS changes, keep credentials out of source control, fail closed when trust cannot be verified, and separate repository validation from live-production authority.

## Supported repository state

Security fixes target the current `main` branch unless a specific release branch is explicitly maintained. No long-term support matrix is currently declared.

## Mandatory controls

- never commit passwords, tokens, SSH/WireGuard private keys, runner credentials, RouterOS binary backups, sensitive exports, or populated secret-bearing environment files;
- production mutation requires audit, backup, target-bound fresh dry-run evidence, recovery access, explicit operator opt-in, sequential Safe Mode phase confirmation, assertive pre-commit verification, and post-change verification;
- CORE SSH defaults to public-key authentication with password authentication disabled;
- root SSH login remains disabled;
- APT signature verification may not be bypassed;
- HashiCorp signing-key recovery must match the fingerprint pinned in reviewed source;
- normal GitHub-hosted and self-hosted validation workflows must not silently become production apply channels;
- untrusted fork pull requests must not execute on the privileged self-hosted runner;
- validation/secret-scanning rules must not be weakened merely to make CI green;
- encrypted RouterOS backups and their decryption secrets must be stored in separate protected paths;
- release archives must contain tracked reviewed Git content only, never controller-local ignored state;
- third-party GitHub Actions and controller base images must use reviewed immutable references.

## Trust boundaries

`core.zeaz.dev`, the RouterOS device, GitHub Actions, the self-hosted Windows runner, GHCR, and operator workstations are distinct trust surfaces. See `docs/ARCHITECTURE.md` and `docs/GITHUB-OPERATIONS.md`.

## SSH recovery safety

If public-key authentication is not proven, keep the existing recovery terminal/session open. Do not disable the last working authentication path. `core/install.sh` prevents the normal key-only path when the selected user lacks a non-empty `authorized_keys` file.

## Reporting vulnerabilities

Do not publish exploitable details, credentials, topology dumps, or secrets in a public issue. Prefer GitHub Private Vulnerability Reporting when enabled. Otherwise contact the repository owner privately through a trusted channel and provide only the minimum reproducible information.

Include affected commit/version, impact, reproduction conditions, and whether credentials might have been exposed. If a secret was exposed, rotate/revoke it before discussing remediation publicly.

## Operational incidents

Availability incidents without a security defect belong in normal support/operations tracking. See `SUPPORT.md`. Security incidents involving possible credential exposure, unauthorized access, or bypass of safety gates should use the private reporting path.


## Vulnerability scanning boundary

`tools/generate-security-evidence.py` produces a tracked-file inventory and literal-secret audit; it is not a CVE scanner. GitHub workflow `.github/workflows/security-scan.yml` separately runs Trivy against the repository filesystem and built controller image for HIGH/CRITICAL vulnerability findings. Live RouterOS and host vulnerability posture still requires runtime-specific review and vendor advisories.
