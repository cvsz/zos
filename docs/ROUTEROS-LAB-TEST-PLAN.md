# Minimal RouterOS Lab Test Plan

This plan validates zOS RouterOS safety controls on a **disposable, isolated RouterOS lab device only**. It is not a production procedure.

## Safety boundary

- Never point a lab target at PROD/CORE or the production RB4011.
- Use a spare RouterBOARD/CHR/VM with no production routes, DNS, DHCP clients, WireGuard peers, or credentials.
- Use a dedicated management address and disposable admin key.
- Keep a second management session available for Safe Mode rollback testing.
- Default controller posture remains fail-closed:

~~~text
OMEGA_ALLOW_LIVE_APPLY=0
OMEGA_REQUIRE_DRY_RUN=1
OMEGA_REQUIRE_SAFE_MODE=1
~~~

RouterOS `import ... verbose=yes dry-run` is used to validate imports without committing intended changes. Safe Mode must be confirmed by the controller before a live apply is accepted.

## Production contract under test

The lab should model behavior, not reuse production identities or credentials. The production source of truth is:

~~~text
WAN        ether1 DHCP
LAN bridge DBC-Bridge-Local
LAN CIDR   192.168.1.0/24
Gateway    192.168.1.1
~~~

Do not copy production MAC addresses, WireGuard keys, or host credentials into the lab.

## Test matrix

| ID | Test | Expected result |
|---|---|---|
| SM-01 | Safe Mode apply | Controller reports `[Safe Mode taken]` and `OMEGA_APPLY_PASS` |
| SM-02 | Safe Mode rollback | Abnormal session termination rolls back changes |
| DR-01 | Required dry-run | Successful dry-run records exact active-phase SHA-256 manifest |
| DR-02 | Stale manifest | Changing an active phase after dry-run blocks apply |
| DR-03 | Live-apply gate | `OMEGA_ALLOW_LIVE_APPLY=0` blocks mutation |
| UP-01 | Update check | Does not persistently change RouterOS update channel |
| UP-02 | Update verification | Success requires the running RouterOS version to change |
| BK-01 | Encrypted backup | AES-SHA256 binary backup and text export are downloaded |
| BK-02 | Backup cleanup | Controller-created temporary router files are removed |
| OWN-01 | Preserve unowned DHCP/DNS | Unrelated objects remain unchanged |
| OWN-02 | Preserve unowned firewall/NAT | Unrelated rules remain unchanged |
| OWN-03 | Ownership conflict | Conflict fails closed instead of takeover |

## Execution order

### 1. Repository gates

~~~bash
make validate
make docs
~~~

Record the commit SHA. Stop if repository validation fails.

### 2. Baseline lab snapshot

~~~bash
make status
make audit
make backup
~~~

Confirm the binary backup is encrypted and temporary router files are cleaned up.

### 3. Dry-run gate

~~~bash
make dry-run
~~~

Confirm the dry-run succeeds and the active-phase SHA-256 manifest is recorded. Change one active phase locally and verify `make apply` is refused because the manifest is stale, then restore the file.

### 4. Safe Mode happy path

~~~bash
export OMEGA_ALLOW_LIVE_APPLY=1
make apply
~~~

Expected: Safe Mode is explicitly confirmed, all active phases run in the same Safe Mode session, and `OMEGA_APPLY_PASS` appears only after all phases succeed.

### 5. Safe Mode rollback

Repeat the lab apply but terminate the interactive session abnormally before the final clean exit. Reconnect and compare the router configuration with the baseline. Changes made inside that Safe Mode session must be rolled back.

### 6. Ownership tests

Create unrelated DHCP, DNS, firewall, NAT, bridge, or addressing objects before the relevant phase. zOS must preserve them. If they conflict with a zOS-managed contract, the phase must stop rather than silently delete or rewrite them.

### 7. Update verification

~~~bash
make update-check
~~~

Confirm the update channel is unchanged. Auto-update testing is allowed only on the disposable lab and requires the documented update/reboot gates. A router returning on the same running version when an update was expected must be treated as failure.

## Exit criteria

A lab passes only when Safe Mode apply and rollback are demonstrated, dry-run manifests are mandatory/current, live mutation gates fail closed, backups are encrypted and cleaned up, update checks are read-only, update success requires a version change, and unowned RouterOS state is preserved.

A lab pass is **not** production approval. Production still requires backup, operator review, a verified recovery path, dry-run, Safe Mode, and post-change verification.
