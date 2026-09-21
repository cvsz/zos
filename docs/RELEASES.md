# Release Process

## Version source

`zOS/VERSION` is the controller package version. The project currently uses a lightweight pre-1.0 lifecycle; compatibility is not yet guaranteed as a stable public API.

## Release checklist

1. update `CHANGELOG.md` and any behavior/operations docs;
2. set `zOS/VERSION` intentionally;
3. run `make validate`, `make docs`, `make evidence`, and the applicable security/build checks;
4. merge to `main` only after the configured repository ruleset/checks pass; verify the account-side protection is actually enabled;
5. tag using `zos-v<version>`;
6. verify the GitHub build artifact and GHCR image;
7. record release notes and known limitations;
8. keep live RouterOS deployment separate from the release build.

The complete local gate is `make all`. `make release-check` additionally requires a project-wide `LICENSE`, a clean working tree, the `main` branch, and exact synchronization with `origin/main`. Release packaging uses `git archive HEAD`, so ignored local topology files, backups, passwords, state, and other untracked controller data cannot enter the release tarball. To publish, use `RELEASE_CONFIRM=1 make release` from the reviewed `main` commit. This requires authenticated `git push` and `gh`; it does not perform RouterOS or Cloudflare changes.

## Artifacts

`build-zos` produces:

- `zos-mikrotik-<version>.tar.gz`;
- SHA-256 checksum;
- controller-side OCI image at `ghcr.io/cvsz/mikrotik-zos`.

The OCI image is not RouterOS firmware.

## Rollback

Repository/package rollback selects a previously reviewed commit/tag/image. RouterOS configuration rollback is a different operational procedure and must use the backup/Safe Mode/disaster-recovery workflow.

## Release integrity

Do not publish a release when required checks are red, version/changelog disagree, or the package contains unreviewed secrets/configuration.
