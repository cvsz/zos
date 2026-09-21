# Evidence Matrix

zOS distinguishes deterministic repository evidence from live production evidence.

| Area | Evidence | Validation |
|---|---|---|
| Repository safety | source/config/scripts | `make validate` |
| Project documentation | required docs and local links | `make docs` |
| Analyzer corpus | `evidence/corpus/analyzer/golden.jsonl` | `make evidence` |
| RAG/evaluator | `evidence/corpus/rag/ranking.jsonl` | `make evidence` |
| PR salvage | `evidence/corpus/pr-salvage/cases.jsonl` | `make evidence` |
| Discussion triage | `evidence/corpus/discussions/triage.jsonl` | `make evidence` |
| Harness compatibility | `evidence/harness/compatibility.json` + adapter docs | `make evidence` |
| Security repository evidence | tracked-file SPDX + literal-secret SARIF/audit | `make security-evidence` |
| Vulnerability evidence | Trivy filesystem + built controller image scan | `security-scan.yml` |
| Deployment preflight integrity | git/topology/target/runtime/config/phase hashes + freshness | `make dry-run` |
| Transaction rollback guard | sequential Safe Mode PASS/FAIL + floating-undo budget | `make apply` (approved live window only) |
| Vendored RouterOS skills | skill structure/relative links/secret checks | `routeros-skills.yml` |
| CORE active routing | live route/WireGuard state | `make core-check`, `make core-find-conflict` |
| Router runtime | live read-only status/verify | `make status`, `make audit`, `make verify` |
| End-to-end reachability | live smoke checks | `make e2e` |

## Interpretation

Committed fixtures are regression contracts. Generated security evidence describes checks run against the repository. Neither proves that the live network is healthy.

Production acceptance additionally requires external/live evidence such as management reachability, route persistence, SSH key login, DNS, WireGuard handshake, firewall/NAT behavior, backup/restore readiness, and intended DEV/PROD connectivity.

## Evidence hygiene

- use synthetic or sanitized fixtures;
- never commit credentials, private keys, runner tokens, sensitive exports, or raw incident payloads;
- change fixtures and expected outcomes together when behavior changes;
- do not weaken validators merely to make CI green;
- retain enough context that a reviewer can distinguish test evidence from operator-observed runtime evidence.
