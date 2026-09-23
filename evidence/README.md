# zOS Evidence Corpus

`evidence/` contains deterministic, sanitized repository fixtures. It is not a storage location for raw production logs or credentials.

## Layout

- `corpus/analyzer/golden.jsonl` — analyzer regression cases;
- `corpus/rag/ranking.jsonl` — retrieval/ranking expectations;
- `corpus/pr-salvage/cases.jsonl` — PR salvage/cleanup cases;
- `corpus/discussions/triage.jsonl` — discussion triage cases;
- `harness/compatibility.json` — agent-adapter compatibility expectations;
- `ci/failure-modes.jsonl` — sanitized failure signatures and expected diagnosis;
- `security/README.md` — generated security-evidence contract.

## Commands

~~~bash
make evidence
make security-evidence
~~~

## Boundary

Repository evidence proves only the checks and fixtures represented here. Live CORE/router acceptance requires the runtime evidence defined in `docs/PRODUCTION-READINESS.md` and `docs/EVIDENCE-MATRIX.md`.

Fixtures must never contain real credentials, private keys, runner tokens, sensitive exports, binary backups, or raw private incident data.

## Validator output contract

`make evidence` and `python3 tools/validate-evidence.py` print a per-check text report for analyzer, RAG, PR salvage, discussions, CI failure modes, and harness compatibility. The previous one-line PASS output is replaced by a multi-line report; consumers must not parse the old string. Use `python3 tools/validate-evidence.py --format json` for automation. JSON schema version 1 includes `status`, `total_rows`, `checks_passed`, `checks_failed`, `duration_ms`, and `checks` (name, status, rows, duration_ms, error). Exit code 0 means all checks pass; 1 means at least one fails. All checks run independently so errors are reported together. This validates repository fixtures only, not live CHR or production recovery.
