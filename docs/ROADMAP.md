# Roadmap

This roadmap describes intended work. It must not be read as evidence that an item is deployed or production-ready.

## Now

- keep CORE SSH/network recovery deterministic and reboot-verifiable;
- keep documentation and GitHub community health complete and validated;
- maintain RouterOS production-safety gates and evidence checks;
- maintain trusted self-hosted runner isolation.

## Next

- formalize release/version policy before 1.0;
- add stronger documentation/static link validation where useful;
- maintain Dependabot coverage and immutable GitHub Action pins;
- expand sanitized failure-mode evidence for CORE/GitHub incidents;
- verify and document actual PROD host addressing before enabling cross-environment automation.

## Later

- evaluate multi-controller/HA and reserved overlay design after route-conflict review;
- expand observability and independent restore/DR exercises;
- add release provenance/attestation and distribute SBOM/security scan artifacts with external releases.

## Open project decisions

- choose and declare the zOS project license;
- decide long-term support/versioning guarantees;
- define additional maintainer/reviewer roles as the contributor base grows.
