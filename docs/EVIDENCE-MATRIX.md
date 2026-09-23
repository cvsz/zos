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
| **CHR Lab Mock Evidence** | `artifacts/chr-lab/manifest-*.json` (failure-injection scenarios) | `python3 tools/chr-lab-harness.py` |
| Backup pipeline (mock) | backup artifact manifest and SHA-256 checksums; no production backup published | `bash tools/test-backup-hardening.sh` |
| Restore drill (mock) | sanitized evidence; actual CHR restore remains BLOCKED | `bash tools/test-restore-drill.sh` |
| Repository security | tracked-file secret scan, permissions, CI and retention guards | `bash tools/test-repo-security.sh` |
| Offline topology | canonical LAN CIDR and gateway, JSON drift fixtures | `bash tools/test-topology-reconcile.sh` |
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
