# Licensing

## Project code

The repository contains a project-wide MIT License in the root `LICENSE` file.

- SPDX identifier: `MIT`
- Copyright notice: `Copyright (c) 2026 zOS Contributors`
- GitHub repository metadata currently reports `mit`.

The root license is the repository's explicit license grant for the project code and documentation it covers. Review file-level notices and third-party materials separately; a repository-wide license does not erase third-party license obligations or relicense material whose terms are stated separately.

## Vendored RouterOS skills

Material under `skills/routeros-*` is derived from `tikoci/routeros-skills`. Its upstream MIT terms and provenance are recorded in `THIRD_PARTY_NOTICES.md`.

Preserve upstream notices and attribution when modifying or redistributing vendored material. Check each upstream component's license and notice before changing its contents.

## Release and distribution

Before each release:

1. verify that the root `LICENSE` remains present and matches the declared SPDX identifier;
2. retain `THIRD_PARTY_NOTICES.md` and applicable file-level notices in release archives;
3. ensure dependency and vendored-license inventories are current;
4. do not describe third-party materials as original zOS work; and
5. record any license exception or additional attribution requirement in the release notes.

This document describes the repository state inspected on 2026-11-09. Recheck the actual license files and metadata before relying on it for a later release.
