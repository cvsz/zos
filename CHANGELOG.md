# Changelog

Notable repository and operational changes are recorded here. zOS has not yet declared a stable public API; version numbers below describe repository milestones.

## Unreleased

### Offline topology drift และ SSH read-only audit
- เพิ่ม JSON Drift Report, ตรวจ LAN CIDR/Gateway, ชุด Fixture Tests และ Audit Collector ที่ต้องยืนยัน SSH Host Key ผ่าน Known Hosts; Error ของ SSH ไม่ถูกนับเป็น PASS และ Production Mutation ยังคงถูกปิด

### Restore Drill — clean main integration
- เพิ่ม Restore Drill ที่ตรวจ Schema ของ Backup Pipeline จริง (`bytes`), Manifest Provenance, ชื่อ Artifact และ SHA-256 จากไฟล์โดยตรง พร้อม Regression Tests โดยยังปิด Live CHR Restore และไม่เชื่อมต่อ Production

### CHR lab harness regression suite - Python 3.14 compatibility (Phase B)
- แก้ `tools/test-chr-lab-harness-regression.py` ที่ crash ด้วย `AttributeError` บน Python 3.14: ลงทะเบียน dynamically loaded modules ใน `sys.modules` ก่อน `exec_module` (จำเป็นสำหรับ `@dataclass` processing)
- เขียนชุดทดสอบใหม่ 9 เคสให้ใช้ event-driven API ปัจจุบัน (`run_event_driven_test`, `expected_action`/`expected_conditions`) แทน `run_scenario_test`/`expected` ที่ไม่มีอยู่แล้ว; ทุกเคส assert ว่า failure condition ถูก exercise และ detect จริงผ่าน `transport.read()`/`write()` (connection/auth/prompt timeout, Safe Mode refusal, hijack, static/stale spoof rejection, disconnect, commit gate)
- ผูกชุดทดสอบเข้า `tools/validate-repo.sh` (รันใน `make validate` และ CI `validate.yml`); ผ่าน 9/9 ทั้ง direct run และ pytest บน Python 3.14.4

### Backup lifecycle hardening - atomic publish, checksums, manifest (Phase 3 P0-2)
- เขียนใหม่ `backup()` ใน `tools/omega-router.sh` แบบ idempotent: ตัวระบุไม่ซ้ำ (`timestamp-pid-random`), `umask 077` ก่อน `mkdir`, `chmod 700` dirs / `chmod 600` artifacts, staging ส่วนตัวผ่าน `mktemp -d` + ไฟล์ `.part`, ตรวจสอบ `nonempty` ทั้งสองไฟล์, คำนวณ `SHA-256`, เผยแพร่แบบ `atomic mv` แล้วจึงเขียน `.sha256` + `manifest.json` (ผูก `backup_id/commit_sha/created_at/router_host/sha256/bytes` โดยไม่รวม password/secret)
- ส่ง RouterOS backup commands ทาง `stdin pipe` (`ssh_stdin`) แทน `ssh argv` เพื่อไม่ให้ password ปรากฏใน `ps/process output`; ปิด shell tracing (`set +x`) รอบ password handling และไม่ echo password ใน stdout/logs/errors; รองรับ `OMEGA_BACKUP_DIR` override สำหรับ test isolation, `OMEGA_BACKUP_RETENTION_COUNT` (default 30, ไม่ลบ copy เดียวที่เหลือ), `OMEGA_BACKUP_OFFHOST_DIR` (optional copy, warn ไม่ fail backup หลัก)
- แก้บั๊ก `if ! scp ...; then rc=$?` ที่เก็บ exit code ผิด (ได้ 0 ทำให้ partial backup รายงาน success): เปลี่ยนเป็น `|| { rc=$?; ...; return; }` พร้อม fallback `rc=1`
- เพิ่ม `tools/test-backup-hardening.sh` 28 เคส (static 14 + mocked integration 14): unique ID, perms, mktemp/atomic, nonempty/sha256/manifest, trap ไม่บดบัง error, no password ใน ssh argv/stdout/`bash -x`, happy-path manifest/perm/checksum/unique, partial (binary fail) fail-closed ไม่มี manifest, empty fail-closed
- ล็อก contract ใหม่ใน `tools/validate-repo.sh` และบังคับรัน backup regression ใน `make validate`
- Live CHR restore verification ยัง **BLOCKED** (ไม่มี isolated CHR); backup file ที่มีอยู่ไม่ใช่ proof of recoverability จนกว่าจะมี restore drill สำเร็จ

### CHR Lab Mock Harness - Event-Driven Rewrite & Regression Tests (Phase 2)
- เขียนใหม่ `tools/chr-lab-harness.py` แบบ event-driven: ใช้ transport interface จริง (`transport.read()`, `transport.write()`) เพื่อให้ failure injection paths ถูก exercise จริง — ไม่ใช่แค่ iterate responses
- State machine transitions ขับเคลื่อนด้วย verified transport events: connection, prompt, Safe Mode entry, execution, verification
- `trust_level` ใน `OutputEvent` จัดเป็น trusted เฉพาะ RouterOS response หลัง write ของเรา (`after_our_write=True`) — ไม่มี unconditional trusted status
- เพิ่ม `tools/test-chr-lab-harness-regression.py`: regression tests 9 เคสแสดง false-positive defects ของ harness เก่า (connection/auth/prompt timeout ไม่ได้ exercise จริง, trust_level unconditional, OR logic masks failures, transport.read() ไม่ถูกเรียก, echo spoof ไม่ถูก detect)
- Mock scenarios 16 เคส PASS ทั้งหมด: SSH connect/auth/timeout, Safe Mode refusal/hijack, script error, health failure, SSH disconnect, SIGINT/SIGTERM, concurrent apply, stale nonce/static marker spoof, fragmented/truncated output, rollback, commit gate
- Live CHR integration tests (SM-01, SM-02, DR-01..03, UP-01..02, BK-01..02, GR-01..03, OWN-01..03) mark **BLOCKED** ตาม AGENTS.md — ห้าม fabricate
- `main()` ใน `routeros-safe-session.py` ยังคง return 4 (live apply disabled)

### CHR Lab Mock Harness & Failure Injection (Phase 2)
- เพิ่ม `tools/chr-lab-harness.py`: deterministic mock SSH transport + 15 failure-injection scenarios (SSH connect/auth failure, prompt timeout, Safe Mode refusal/hijack, script error, health failure, SSH disconnect, SIGINT/SIGTERM, concurrent apply, stale nonce/static marker spoof, fragmented/truncated output, rollback, commit gate)
- เพิ่ม `docs/CHR-LAB-EVIDENCE.md`: reproducible evidence manifest template, test matrix (29 tests: 15 mock PASS + 14 live BLOCKED), safe CHR provisioning guidance, provenance requirements
- `classify_output` แก้ weakness: nonce-bearing PASS ใน command echo ไม่นับเป็น execution proof — ต้องมี `after_our_write=True` (trusted response) เท่านั้นจึง `pass_accepted` และ `is_successful_commit_signal()`
- เพิ่ม `OutputEvent` dataclass กับ `trust_level` (trusted/untrusted), `FramedMarkers` class, `MockTransport` สำหรับ unit tests
- Live CHR integration tests ทั้งหมด mark **BLOCKED** จนกว่าจะมี isolated CHR instance + authorization
- อัปเดต `docs/TESTING.md`, `docs/ROADMAP.md`, `docs/EVIDENCE-MATRIX.md`, `docs/PRODUCTION-READINESS.md`
- `main()` ยังคง return 4 (live apply disabled)

### Safe Mode nonce-framed state machine (testable, still fail-closed)
- เพิ่ม `SessionState` (DISCONNECTED→UNKNOWN ครบ 11 สถานะ), `generate_nonce`, `build_framed_markers`, `classify_output`, `next_action`, `sanitize_for_evidence` ใน `tools/routeros-safe-session.py` แบบ pure function ไม่มี network และไม่มี credential ใน output.
- `classify_output` ปฏิเสธ static `OMEGA_APPLY_PASS` echo โดยเด็ดขาด ยอมรับเฉพาะ pass marker ที่ผูก nonce ตรงรอบ transaction; `next_action` สั่ง commit ได้เฉพาะ Safe Mode ยืนยัน + nonce pass + health OK + ไม่มี fail/hijack นอกนั้น rollback และไม่มีวัน hijack session ของ operator อื่น.
- เพิ่ม regression tests 9 เคส (รวมเป็น 28 tests) ครอบคลุม states, nonce, framing, echo-spoof, fail/hijack, commit-gate และ evidence redaction.
- ล็อก contract ใหม่ใน `tools/validate-repo.sh` (fail-closed checks).
- `main()` ยังคง return 4 (live apply disabled) จนกว่า CHR integration และ rollback tests จะมี verified evidence แยกต่างหาก.

### Local Wi-Fi profile hygiene and build-context exclusion
- เพิ่ม `config/wifi-single-network.env` ใน `.gitignore` และ `.dockerignore` เพื่อกัน operator SSID/site-specific values หลุดเข้า Git หรือ controller image build context.
- เพิ่ม validation ใน `tools/validate-repo.sh` ให้ fail-closed ถ้า populated Wi-Fi profile ไม่อยู่ใน ignore ทั้งสองไฟล์ (กัน regression ตาม AGENTS.md container build context contract).
- Live RouterOS apply paths ยังคง disabled (fail-closed) จนกว่า CHR-backed interactive Safe Mode และ rollback จะมี verified evidence.

### Golden RB4011 rebuild synchronized with current production contract
- Refresh `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` for the current single-LAN `192.168.1.0/24` production baseline and RouterOS 7.25beta4 live behavior.
- Fail fast on non-clean IP pool, DHCP, WireGuard, firewall/NAT, legacy `.0/.10`, or conflicting LAN-gateway state before the first mutation.
- Converge the current DHCP pool, fixed infrastructure including EWS1200D/EWS310AP `.50-.58`, local DNS, Bangkok timezone/NTP, WireGuard, firewall/NAT, management-service hardening, and observability baseline.
- Print the regenerated router WireGuard public key for CORE reconciliation without storing private key material in Git.
- Add fail-closed post-rebuild assertions and `OMEGA GOLDEN REINSTALL VERIFY PASS`, plus repository/lab/DR validation for the new contract.

### DHCP pool normalization and phase diagnostics
- Normalize RouterOS `/ip pool get ... ranges` values with `:tostr` before comparing them with the verified legacy/desired contracts (`:tostr` joins with semicolons on RouterOS 7.25beta4, verified live).
- Represent the single dynamic address `192.168.1.121` canonically instead of as a degenerate start/end range.
- Echo each phase filename (`OMEGA_PHASE FILE:<name>`) before import so a Safe Mode failure identifies which phase did not complete.
- Include `/ip pool print detail` and `/ip pool used print detail` in read-only audits so fallback pools such as `next-pool` can be reviewed before mutation.

### Safe Mode commit via Ctrl-X release
- Commit Safe Mode transactions with a second Ctrl-X (`Releasing Safe Mode... Success!`); `/quit` inside Safe Mode unrolls on RouterOS 7.25beta4, so prior `OMEGA_APPLY_PASS` runs were silently discarded.
- Driver answers stale `Safe Mode is taken by current user in another session` with unroll before retrying, and confirms console `/quit` only after release.
- One-shot legacy migration avoids `find` in `/import` (empty results) via index-anchored checks inside `:do {}`, removes DHCP networks high-index-first, and verifies post-remove DNS with `count-only where`.

### Single-network Wi-Fi profile
- เพิ่ม secret-free profile สำหรับ EWS1200D-10T + EWS310AP แบบ 1 SSID / 1 subnet `192.168.1.0/24` / untagged โดยไม่สร้าง Wi-Fi VLAN เพิ่ม
- กำหนด controller `.50` และ AP reservations `.51-.58` ให้สอดคล้องกับ production DHCP contract
- เพิ่ม baseline สำหรับ Band Steering, Fast Roaming, Auto Channel/Tx Power และ channel width โดยให้ PSK อยู่ใน EWS controller เท่านั้น
- เพิ่ม read-only `make wifi-status` เพื่อดู RouterOS-side LAN/DHCP/pool/EnGenius/legacy indicators โดยไม่แก้ live config
- เพิ่ม runbook อ้างอิง EnGenius official product documentation และ MikroTik manual


### RouterOS object-count guard correction
- เปลี่ยน one-shot legacy DHCP migration จากการใช้ `:len` กับ internal IDs ที่ได้จาก `find` มาใช้ `print count-only where ...` สำหรับ uniqueness/existence checks ตาม RouterOS CLI semantics
- ใช้ `find` เฉพาะหลัง count ผ่านแล้ว เพื่อรับ object ID สำหรับ `get/set/remove`
- ป้องกัน false refusal ที่พบจริงบน RouterOS 7.25beta4 เมื่อ `lan-pool` มีเพียงหนึ่งรายการแต่ guard `:len $lanPool != 1` ยัง fail


### Legacy DHCP quarantine migration
- เพิ่ม one-shot guarded migration สำหรับตัด fallback chain `lan-pool -> zeaz-pool -> wifi-pool -> lan-pool` โดยไม่ลบ legacy pool objects
- refuse migration ถ้ามี legacy pool usage, DHCP reference, ARP/lease, WAN DHCP server หรือ topology ไม่ตรงกับ inspected state
- ถอนเฉพาะ legacy DHCP networks `192.168.0.0/24`, `192.168.10.0/24` และ legacy bridge address `192.168.0.0/24`
- migrate production DHCP DNS option ไปที่ RouterOS `192.168.1.1` หลังยืนยัน `allow-remote-requests=yes`
- เพิ่ม `make migrate-legacy-dhcp` ที่บังคับ repo validation, encrypted backup, RouterOS dry-run, Safe Mode และ explicit opt-in สองชั้น
- เพิ่ม read-only `legacy-dhcp-status` และ runbook อ้างอิง MikroTik official manual


### Live topology drift precheck
- Reject any enabled DHCP server bound to WAN `ether1`.
- Reject the observed legacy `192.168.0.0/24` address on `DBC-Bridge-Local` until its ownership and migration are explicitly resolved.
- Keep these conditions fail-closed rather than deleting unknown live state automatically.


### DHCP fallback-pool drift detection
- Fail closed when production `lan-pool` points at an unverified `next-pool`.
- Surface the actual RouterOS error if the legacy-to-production pool-range migration fails.
- Verify that the converged production pool has no fallback pool configured.


### RouterOS Safe Mode persistent receive buffer
- Preserve one SSH receive buffer across prompt, Safe Mode confirmation, SAFE-prompt, and transaction-result stages.
- Prevent loss of `<SAFE>` when RouterOS emits it in the same SSH read as `Taking Safe Mode session... Success!`.
- Add a regression test for same-chunk Safe Mode confirmation and SAFE prompt delivery.


### RouterOS Safe Mode prompt synchronization
- Wait for the interactive RouterOS CLI prompt before sending Ctrl-X.
- Require both `[Safe Mode taken]` and the `<SAFE>` prompt before sending the production transaction.
- Detect Safe Mode hijack prompts during the handshake and decline ownership.
- Use split RouterOS PASS/FAIL sentinel strings so terminal input echo cannot be mistaken for executed results.
- Request Ctrl-D rollback on transactional failure or timeout.


### Retained vulnerability and package evidence
- Generate Trivy filesystem and controller-image vulnerability SARIF before enforcement gates.
- Generate a package-aware CycloneDX SBOM from the built controller image.
- Retain Trivy SARIF and CycloneDX evidence as GitHub Actions artifacts for 30 days.
- Validate the evidence/output contract in repository safety checks.


### Supply-chain and recovery follow-up
- Pin GitHub Actions to immutable commit SHAs and pin the controller Alpine base image by digest.
- Add Dependabot coverage for GitHub Actions and Docker updates.
- Add Trivy filesystem and controller-image HIGH/CRITICAL vulnerability gates.
- Harden Docker build context exclusions for local topology, backups, state, environment files, and key material.
- Make the golden reinstall refuse already-configured managed targets and converge the current WireGuard, firewall/NAT, service-hardening, and observability baseline.
- Provision a dedicated root-only secret directory for unattended RouterOS backup passwords.


### Production safety hardening
- Make Safe Mode apply transactional so `/quit` is reachable only after every phase, including assertion verification, succeeds.
- Bind dry-run evidence to the exact target router fingerprint, topology config hash, git commit, phase hashes, and a one-hour freshness window.
- Convert health verification into fail-closed assertions for WAN/LAN, DHCP pool, fixed reservations including EnGenius `.50-.58`, WireGuard, reachability, and DNS.
- Package releases from tracked Git content only, block release without a project-wide `LICENSE`, and reject non-main/dirty/out-of-sync release state.
- Add `.dockerignore` protection for local topology, backups, state, environment files, and key material.
- Fail closed on unowned WireGuard state, peer identity drift, foreign firewall rules, duplicate/disabled policy jumps, duplicate DHCP network records, and duplicate static DNS records.
- Separate encrypted-backup password storage from backup artifacts by default and retain post-apply RouterOS evidence exports locally.
- Require RouterOS auto-update to return on the exact version advertised before installation.
- Make `zos doctor` propagate CORE structural-check failures and wire the controller-generated RouterOS SSH key into local topology config.
- Expand secret evidence scanning to tracked documentation and example files.

### Safe Mode apply operator visibility
- Stream RouterOS Safe Mode output in real time instead of buffering the entire interactive SSH session until exit.
- Add a controller-side `flock` guard so a second `apply-safe` run cannot start while another is active.
- Surface RouterOS Safe Mode hijack prompts so stale/external ownership is visible instead of appearing as a silent hang.
- Keep repository validation ShellCheck-clean while asserting the realtime streaming and locking safeguards.


### RouterOS dynamic interface-list ownership guard
- Ignore RouterOS-generated dynamic interface-list memberships when checking explicit WAN/LAN ownership in `20-NETWORK-NORMALIZE.rsc`.
- Preserve fail-closed behavior for static conflicting memberships while avoiding false failures from Detect Internet state such as dynamic `LAN ether1`.
- Add repository validation and runbook coverage for this distinction.


### EnGenius DHCP reservation reconciliation
- Moved `EWS1200D-10T` to reserved `192.168.1.50` and the eight EWS310AP units to `192.168.1.51-.58` using their verified MAC mappings.
- Updated the LAN pool so `.50-.58`, `.100`, `.119`, `.120`, `.122`, `.123`, and `.238` are excluded from dynamic allocation while the former `.101-.108` and `.239` WiFi addresses return to the dynamic pool.
- Added controlled migration from the previous EnGenius reservations while unrelated fixed hosts remain fail-closed on address drift.
- Removed `server=lan-dhcp` updates from existing lease reconciliation to avoid RouterOS `ambiguous value of server` failures; new leases retain the explicit `lan-dhcp` binding without rewriting existing lease ownership.
- Synchronized the topology template, golden reinstall, validation, environment inventory, runbook, migration guide, and infrastructure reference with the new address contract.
- Documented that a changed reservation is not operationally complete until RouterOS `active-address` matches the target after a controlled DHCP renew or AP reboot.

### Router automation and live apply verification
- Quoted `WIFI_REPEATER_NAME` in `config/topology.env.example` to prevent bash word-splitting errors during environment sourcing.
- Preserved caller `OMEGA_ALLOW_LIVE_APPLY` override across topology sourcing in `tools/omega-router.sh`.
- Completed pre-change backup, dry-run manifest validation, and live configuration apply on the MikroTik RB4011 router (`192.168.1.1`) with health verification passing.

### WireGuard peer configuration
- Added idempotent creation of `wg-remote` interface, address `10.8.0.1/24`, `VPN` interface list membership, and `core.zeaz.dev` peer (`10.8.0.2/32`) in `40-WIREGUARD-SERVICES.rsc`.
- Fixed `/etc/wireguard/*.conf` file discovery in `tools/core-network-repair.sh` to work with root-protected permissions.
- Verified active bidirectional WireGuard handshake and ICMP ping reachability between CORE (`10.8.0.2`) and router (`10.8.0.1`).

### 2026-09-16 verified LAN/WiFi inventory
- Corrected `PoliceDBC-SEA` to `192.168.1.10` with MAC `48:4D:7E:D4:3A:C6`.
- Corrected `core.zeaz.dev` to `192.168.1.100` with verified VMware MAC `00:0C:29:75:A6:D4`.
- Added fixed DHCP inventory for RITRUECHAI-AP01/02, BOONNAK-AP01/02, SARASIN-AP01/02, and PANKHONGCHUEN-AP01/02 at `.101-.108` with the supplied MACs.
- Added `wifi.zeaz.dev = 192.168.1.238` for `ZEAZ Wifi Repeater` and `EWS1200D-10T = 192.168.1.239`.
- Updated the dynamic DHCP pool so fixed infrastructure addresses cannot be dynamically allocated.
- Withheld the reported `prod.zeaz.dev = 192.168.1.101` binding because `.101` is already assigned to verified `RITRUECHAI-AP01`; the active RouterOS phase fails closed on this inventory conflict.
- Removed obsolete active-contract assumptions for `prod=.122` and `core=.123` from the RouterOS topology source of truth.

### Cloudflare integration boundary
- Added a secret-free Cloudflare connector/origin template and documented the optional DNS, Access, and Tunnel trust boundary.
- Added explicit repository, runtime, rollback, and GitHub review gates; no Cloudflare provisioning or live RouterOS mutation is included.

### Verified RB4011 production topology
- Replaced the stale static-WAN assumption with the verified `ether1` DHCP WAN contract; the observed `192.168.202.91/21` lease is runtime evidence only.
- Made `DBC-Bridge-Local = 192.168.1.1/24` the canonical LAN bridge and retained `ether2`-`ether10` plus `sfp-sfpplus1` as LAN ports.
- Added `reinstall/OMEGA-RB4011-GOLDEN-REINSTALL.rsc` as the clean rebuild/recovery source of truth.
- Removed obsolete numbered legacy phases for clean-slate identity, PPPoE networking, unverified segmentation, alternate WireGuard, fixed shaping, and superseded logging.

### Production safety hardening
- Added exact SHA-256 dry-run manifests and blocks live apply when phase contents have changed since the successful dry-run.
- Added one-session RouterOS Safe Mode apply with explicit Safe Mode and all-phase success sentinels.
- Added AES-SHA256 controller-managed binary backups, local backup-password protection, download verification flow, and router-side temporary-file cleanup.
- Made dry-run uploads unique and removes temporary files after validation.
- Made RouterOS update checks read-only with respect to update-channel state and requires the running RouterOS version to change before reporting an update successful.
- Changed network, DHCP/DNS, firewall, and NAT management to preserve unowned state and fail closed on ownership conflicts.
- Added an explicit SSH public-key bootstrap helper and isolated RouterOS safety lab test plan.

### Documentation and GitHub operations
- Rebuilt the project documentation map and added architecture, installation, testing, release, network-recovery, SSH-hardening, GitHub-operations, roadmap, support, governance, maintainer, and licensing guidance.
- Added GitHub community templates and CODEOWNERS guidance.
- Added documentation validation to prevent stale repository names and broken local Markdown references.
- Clarified the difference between desired automation identity and the actual operator/recovery account on an existing CORE host.
- Added root, CORE, zOS, PROD, topology, and Windows runner VM `.env.example` templates with fail-closed defaults and documented loading/secret-handling rules.
- Added the `zeaz` Windows VM / `zOS-Runner` environment contract and runner-local documentation.

### CORE recovery/hardening
- Added fail-closed OpenSSH bootstrap/recovery for CORE.
- Defaulted SSH password authentication to disabled and added authorized-key lockout prevention.
- Added secure HashiCorp APT signing-key recovery with a reviewed pinned fingerprint.
- Fixed temporary-file cleanup under `set -u`.
- Restored executable Git modes for operational shell entry points.
- Corrected persistent WireGuard conflict reporting so active `.conf` files are evaluated separately from retained backups.

## v2.1 - Real ZeaZDev environment naming
- Canonical DEV host: `core.zeaz.dev`.
- Canonical PROD host: `prod.zeaz.dev`.
- Desired automation SSH identity: `zeazdev`.
- Removed legacy DBC naming from current automation guidance.
- Preserved the PoliceDBC RouterOS production baseline and safe-change workflow.

## v2.0 - PoliceDBC production-safe refactor
- Replaced clean-slate assumptions with the verified PoliceDBC topology.
- Added hard prechecks for WAN, LAN, default route, and WireGuard.
- Added backup, dry-run, Safe Mode, and explicit live-change gates.
- Deprecated the old PPPoE/192.168.10.0 production assumptions.

## v1.0
- Initial clean-slate PPPoE-oriented design.
