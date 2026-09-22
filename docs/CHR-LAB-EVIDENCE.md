# CHR Lab Evidence Manifest

This document defines the reproducible evidence template for RouterOS CHR lab testing.
All tests requiring actual RouterOS execution are **BLOCKED** until an isolated CHR
instance is available and authorized.

## Evidence Model

Each lab run produces a JSON manifest with the following structure:

```json
{
  "run_id": "uuid prefix",
  "commit_sha": "git commit SHA",
  "chr_version": "RouterOS version (e.g., 7.25beta4)",
  "chr_image_provenance": "MikroTik CHR image source + checksum",
  "test_runner": "tools/chr-lab-harness.py",
  "started_at": "ISO8601 timestamp",
  "completed_at": "ISO8601 timestamp",
  "tests": [
    {
      "id": "SM-01",
      "name": "Safe Mode apply",
      "description": "Controller reports [Safe Mode taken] and OMEGA_APPLY_PASS",
      "scenario": "safe_mode_apply",
      "expected": "commit",
      "status": "BLOCKED",
      "evidence": {},
      "started_at": null,
      "completed_at": null,
      "duration_ms": 0,
      "error": null
    }
  ],
  "summary": {
    "PASS": 0,
    "FAIL": 0,
    "BLOCKED": 15,
    "SKIPPED": 0
  }
}
```

## Test Matrix (from docs/ROUTEROS-LAB-TEST-PLAN.md)

| ID | Test | Description | Expected | Status |
|----|------|-------------|----------|--------|
| SM-01 | Safe Mode apply | Controller reports `[Safe Mode taken]` and `OMEGA_APPLY_PASS` | commit | BLOCKED |
| SM-02 | Safe Mode rollback | Abnormal session termination rolls back changes | rollback | BLOCKED |
| DR-01 | Required dry-run | Successful dry-run records exact active-phase SHA-256 manifest | commit | BLOCKED |
| DR-02 | Stale manifest | Changing an active phase after dry-run blocks apply | rollback | BLOCKED |
| DR-03 | Live-apply gate | `OMEGA_ALLOW_LIVE_APPLY=0` blocks mutation | rollback | BLOCKED |
| UP-01 | Update check | Does not persistently change RouterOS update channel | commit | BLOCKED |
| UP-02 | Update verification | Success requires the running RouterOS version to change | commit | BLOCKED |
| BK-01 | Encrypted backup | AES-SHA256 binary backup and text export are downloaded | commit | BLOCKED |
| BK-02 | Backup cleanup | Controller-created temporary router files are removed | commit | BLOCKED |
| GR-01 | Golden clean-target refusal | Existing pool/DHCP/WireGuard/firewall state is rejected | rollback | BLOCKED |
| GR-02 | Golden rebuild convergence | Clean target reaches contract and emits `OMEGA GOLDEN REINSTALL VERIFY PASS` | commit | BLOCKED |
| GR-03 | Golden WireGuard key handoff | Rebuild prints new router WireGuard public key | commit | BLOCKED |
| OWN-01 | Preserve unowned DHCP/DNS | Unrelated objects remain unchanged | commit | BLOCKED |
| OWN-02 | Preserve unowned firewall/NAT | Unrelated rules remain unchanged | commit | BLOCKED |
| OWN-03 | Ownership conflict | Conflict fails closed instead of takeover | rollback | BLOCKED |

## Mock Harness Test Matrix (tools/chr-lab-harness.py)

These tests run without CHR using deterministic mock transport:

| ID | Test | Description | Expected | Status |
|----|------|-------------|----------|--------|
| SSH-01 | SSH Connection Failure | Network down, wrong host | rollback | **PASS (mock)** |
| SSH-02 | SSH Authentication Failure | Bad key, wrong user | rollback | **PASS (mock)** |
| SSH-03 | Prompt Timeout | Prompt never appears | rollback | **PASS (mock)** |
| SM-01 | Safe Mode Refusal | Stale session, no unroll permission | rollback | **PASS (mock)** |
| SM-02 | Session Hijack Attempt | Another operator hijacks | rollback | **PASS (mock)** |
| SM-03 | Script Syntax Error | RouterOS syntax error in phase | rollback | **PASS (mock)** |
| SM-04 | Health Verification Failure | Post-change health check fails | rollback | **PASS (mock)** |
| SM-05 | SSH Disconnect Mid-Transaction | Transport drops during execution | rollback | **PASS (mock)** |
| SM-06 | SIGINT/SIGTERM | Process terminated by signal | rollback | **PASS (mock)** |
| SM-07 | Concurrent Apply Blocked | flock prevents second apply-safe | rollback | **PASS (mock)** |
| SM-08 | Stale Nonce Spoof | Previous nonce pass marker appears | rollback | **PASS (mock)** |
| SM-09 | Static Marker Spoof (Echo) | Static PASS in command echo | rollback | **PASS (mock)** |
| SM-10 | Fragmented Output | Output split across reads | commit | **PASS (mock)** |
| SM-11 | Truncated Output | Buffer limit exceeded | commit | **PASS (mock)** |
| SM-12 | Rollback on Phase Failure | Any phase failure triggers rollback | rollback | **PASS (mock)** |
| SM-13 | Commit Gate Full Success | All conditions met for commit | commit | **PASS (mock)** |

## Running the Mock Harness

```bash
# From repository root
python3 tools/chr-lab-harness.py
```

Output: `artifacts/chr-lab/manifest-<run_id>.json`

Current mock coverage: 16 deterministic scenarios (SSH-01..03, SM-01..13), all `PASS (mock)` via event-driven transport. Live matrix above holds 15 tests (`SM-01/02`, `DR-01..03`, `UP-01/02`, `BK-01/02`, `GR-01..03`, `OWN-01..03`), all `BLOCKED`.

## Machine-readable evidence manifests (P0-5)

Every lab/backup/restore run emits a JSON manifest with exact `commit_sha`, artifact `SHA-256` checksums, RouterOS version where known, CHR image provenance where applicable, test IDs, observed outcomes and ISO-8601 timestamps. Counts are derived from actual test records (never hand-written):

- `artifacts/chr-lab/manifest-*.json` from `tools/chr-lab-harness.py` (16 mock `PASS`, 0 `FAIL`, 0 `BLOCKED` in mock mode; live matrix tracked separately as 15 `BLOCKED`);
- `backups/omega-policedbc-*.manifest.json` from `tools/omega-router.sh backup` (`backup_id/commit_sha/created_at/artifact sha256/bytes`, no secrets);
- `artifacts/restore-drill/manifest-*.json` from `tools/restore-drill.sh` (`MOCK PASS` with `elapsed_ms`, or `FAIL`/`BLOCKED`, sanitized).

Status vocabulary is shared: `MOCK PASS` (deterministic mock), `CHR PASS`/`PASS (live)` (isolated CHR with sanitized evidence), `FAIL`, `BLOCKED`, `SKIPPED` (with reason). Never publish backup contents, credentials, complete sensitive exports or private keys.

## Safe CHR Provisioning Instructions (Future)

When a CHR instance becomes available:

1. **Isolation Requirements**
   - Dedicated VLAN or VRF with no route to production networks
   - No access to production DNS, DHCP, or management interfaces
   - Disposable admin key (not production keys)
   - Second management session for rollback verification

2. **Provisioning Steps**
   ```bash
   # 1. Deploy CHR VM/container on isolated hypervisor
   # 2. Configure management interface on lab VLAN only
   # 3. Generate disposable SSH key pair
   # 4. Import key to CHR /user admin ssh-keys
   # 5. Verify SSH access from controller only
   # 6. Record CHR version, image SHA256, and network config
   ```

3. **Evidence Collection**
   - Sanitized transcripts (no keys, passwords, production IPs)
   - RouterOS version, architecture, board name
   - Exact commit SHA tested
   - Test ID, expected/observed outcome, timestamps
   - Before/after configuration diffs (sanitized)

4. **Teardown**
   - Destroy CHR instance after tests
   - Archive evidence manifest
   - No persistent lab state

## Provenance Requirements

For each CHR integration test, record:
- CHR image: URL, SHA256, MikroTik download date
- Hypervisor: type, version, network isolation method
- Test runner: OS, Python version, zOS commit SHA
- Network diagram: lab VLAN, controller IP, CHR management IP
- Credentials: key fingerprint only (no private material)

## Status Definitions

- **BLOCKED**: Requires CHR infrastructure not currently available
- **PASS (mock)**: Verified via deterministic mock harness
- **PASS (live)**: Verified on isolated CHR with sanitized evidence
- **FAIL**: Test executed but outcome did not match expected
- **SKIPPED**: Deliberately not run (document reason)

## Transitioning from BLOCKED to PASS (live)

When CHR becomes available:
1. Update `chr_version` and `chr_image_provenance` in manifest
2. Replace mock scenarios with live SSH transport
3. Run full test matrix
4. Archive sanitized evidence
5. Update this document with live results
6. Submit PR with evidence for review

## Current Blocker

> **No isolated CHR instance available.** All live RouterOS execution tests remain BLOCKED.
> Mock harness provides 100% coverage of failure-injection scenarios without CHR.
> Integration tests (SM-01, SM-02, DR-01..03, UP-01..02, BK-01..02, GR-01..03, OWN-01..03)
> cannot proceed until CHR infrastructure is provisioned and authorized.

## Related Documents

- `docs/ROUTEROS-LAB-TEST-PLAN.md` — Original test plan
- `docs/PRODUCTION-READINESS.md` — Production gates
- `tools/routeros-safe-session.py` — Safe Mode driver (fail-closed)
- `tools/chr-lab-harness.py` — This mock harness