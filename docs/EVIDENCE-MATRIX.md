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
| Security repository evidence | file inventory + secret-audit SPDX/SARIF | `make security-evidence` |
| Vulnerability + package evidence | Trivy filesystem/image SARIF + controller CycloneDX SBOM retained 30 days | `security-scan.yml` |
| Vendored RouterOS skills | skill structure/relative links/secret checks | `routeros-skills.yml` |
| **CHR Lab Mock Evidence** | `artifacts/chr-lab/manifest-*.json` (16 failure-injection scenarios, all mock PASS) | `python3 tools/chr-lab-harness.py` |
| Harness Regression | 9 event-driven failure-path verifications (Python 3.14, direct + pytest) | `python3 tools/test-chr-lab-harness-regression.py` |
| Backup Evidence | `backups/omega-policedbc-*.manifest.json` + `.sha256` (commit/checksum/timestamp binding, no secrets) | `bash tools/test-backup-hardening.sh` |
| Restore Evidence | `artifacts/restore-drill/manifest-*.json` (MOCK PASS/FAIL/BLOCKED with elapsed_ms, sanitized) | `bash tools/test-restore-drill.sh` |
| Repository Security | ignore/build-context/perm/secret-scan/cleanup gates (35 checks) | `bash tools/test-repo-security.sh` |
| Topology Reconciliation | offline read-only contract agreement + JSON drift fixtures (21 checks, no production access) | `bash tools/test-topology-reconcile.sh` |
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
