# Release Process

## Version source

`zOS/VERSION` is the controller package version. The project currently uses a lightweight pre-1.0 lifecycle; compatibility is not yet guaranteed as a stable public API.

## Release checklist

1. update `CHANGELOG.md` and any behavior/operations docs;
2. set `zOS/VERSION` intentionally;
3. declare/review the project-wide `LICENSE`, then run `make validate`, `make docs`, `make evidence`, and the applicable security/build checks;
4. merge through the protected `main` branch;
5. tag using `zos-v<version>`;
6. verify the GitHub build artifact and GHCR image;
7. record release notes and known limitations;
8. keep live RouterOS deployment separate from the release build.

The complete local gate is `make all`. `make release-package` additionally requires a project-wide `LICENSE`, a clean tracked working tree, local `main` exactly matching `origin/main`, and builds from `git archive HEAD` so ignored/untracked secrets and runtime artifacts cannot enter the release tarball. To publish the signed release tag and GitHub release for the version in `zOS/VERSION`, use `RELEASE_CONFIRM=1 make release` from the reviewed `main` commit. This requires authenticated `git push` and `gh`; it does not perform RouterOS or Cloudflare changes.

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
