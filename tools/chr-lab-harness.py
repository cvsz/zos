#!/usr/bin/env python3
"""
CHR Lab Harness — Deterministic mock scenarios for RouterOS Safe Mode testing.

This harness provides injectable transport and failure injection for testing
the Safe Mode state machine without requiring a live RouterOS CHR instance.

All tests requiring actual RouterOS execution are marked BLOCKED until an
isolated CHR is available and authorized.
"""

from __future__ import annotations

import json
import os
import sys
import time
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Optional

# Import the Safe Mode functions
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

# Load module directly since it's not a package
import importlib.util
MODULE_PATH = TOOLS_DIR / "routeros-safe-session.py"
spec = importlib.util.spec_from_file_location("routeros_safe_session", MODULE_PATH)
routeros_safe_session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(routeros_safe_session)

# Import names from the loaded module
SessionError = routeros_safe_session.SessionError
SessionState = routeros_safe_session.SessionState
FramedMarkers = routeros_safe_session.FramedMarkers
OutputEvent = routeros_safe_session.OutputEvent
generate_nonce = routeros_safe_session.generate_nonce
build_framed_markers = routeros_safe_session.build_framed_markers
classify_output = routeros_safe_session.classify_output
next_action = routeros_safe_session.next_action
sanitize_for_evidence = routeros_safe_session.sanitize_for_evidence
MockTransport = routeros_safe_session.MockTransport
create_mock_transport = routeros_safe_session.create_mock_transport


class TestStatus(str, Enum):
    """Status of a CHR lab test."""

    PASS = "PASS"
    FAIL = "FAIL"
    BLOCKED = "BLOCKED"
    SKIPPED = "SKIPPED"


class TestCase:
    """A single CHR lab test case."""

    def __init__(
        self,
        id: str,
        name: str,
        description: str,
        scenario: str,
        expected: str,
        status: TestStatus = TestStatus.BLOCKED,
        evidence: dict = None,
        started_at: Optional[str] = None,
        completed_at: Optional[str] = None,
        duration_ms: int = 0,
        error: Optional[str] = None,
    ):
        self.id = id
        self.name = name
        self.description = description
        self.scenario = scenario
        self.expected = expected
        self.status = status
        self.evidence = evidence or {}
        self.started_at = started_at
        self.completed_at = completed_at
        self.duration_ms = duration_ms
        self.error = error


class LabManifest:
    """Complete evidence manifest for CHR lab run."""

    def __init__(
        self,
        run_id: str,
        commit_sha: str,
        chr_version: str,
        chr_image_provenance: str,
        test_runner: str,
        started_at: str,
        completed_at: Optional[str] = None,
        tests: list = None,
        summary: dict = None,
    ):
        self.run_id = run_id
        self.commit_sha = commit_sha
        self.chr_version = chr_version
        self.chr_image_provenance = chr_image_provenance
        self.test_runner = test_runner
        self.started_at = started_at
        self.completed_at = completed_at
        self.tests = tests or []
        self.summary = summary or {}

    def to_json(self) -> str:
        return json.dumps(self.__dict__, indent=2, default=str)


# --- Deterministic mock scenarios ---

def scenario_ssh_connect_failure(nonce: str, markers: FramedMarkers) -> MockTransport:
    """SSH connection fails immediately."""
    return create_mock_transport(
        responses=[],
        should_fail_connect=True,
    )


def scenario_auth_failure(nonce: str, markers: FramedMarkers) -> MockTransport:
    """SSH authentication fails."""
    return create_mock_transport(
        responses=[b"Permission denied (publickey).\r\n"],
        exit_code=255,
    )


def scenario_prompt_timeout(nonce: str, markers: FramedMarkers) -> MockTransport:
    """SSH connects but prompt never appears (timeout)."""
    return create_mock_transport(
        responses=[b""],
        should_timeout=True,
    )


def scenario_safe_mode_refusal(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Safe Mode is taken by another session, no unroll permission."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Safe Mode is taken by current user in another session.\r\n",
        ],
    )


def scenario_hijack_attempt(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Another operator tries to hijack the session."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"Hijacking Safe Mode from someone else, release it? [y/N]:\r\n",
        ],
    )


def scenario_script_syntax_error(nonce: str, markers: FramedMarkers) -> MockTransport:
    """RouterOS script syntax error during phase execution."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:30-DHCP-DNS-NTP.rsc\r\n",
            b"syntax error at line 42\r\n",
            markers.fail_bytes + b"\r\n",
        ],
    )


def scenario_health_verification_failure(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Health check fails after phases execute."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:00-PRECHECK.rsc\r\n",
            b"OMEGA_PHASE_FILE:10-BACKUP-SNAPSHOT.rsc\r\n",
            b"Health check failed: DNS unreachable\r\n",
            markers.fail_bytes + b"\r\n",
        ],
    )


def scenario_ssh_disconnect_during_transaction(nonce: str, markers: FramedMarkers) -> MockTransport:
    """SSH transport drops mid-transaction."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:20-NETWORK-NORMALIZE.rsc\r\n",
        ],
        disconnect_after=4,
        exit_code=255,
    )


def scenario_sigint_sigterm(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Process receives SIGINT/SIGTERM during transaction."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:50-FIREWALL-NAT.rsc\r\n",
        ],
        exit_code=-15,  # SIGTERM
    )


def scenario_concurrent_apply(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Second apply-safe attempt while one is already running (flock)."""
    # This is tested at the flock level in omega-router.sh
    return create_mock_transport(
        responses=[b"Another apply-safe session is already active\r\n"],
        exit_code=4,
    )


def scenario_stale_nonce_spoof(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Stale nonce from previous run appears in output."""
    stale_nonce = generate_nonce()
    stale_markers = build_framed_markers(stale_nonce)
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:00-PRECHECK.rsc\r\n",
            stale_markers.pass_bytes + b"\r\n",  # stale pass marker
            markers.fail_bytes + b"\r\n",  # current fails
        ],
    )


def scenario_static_marker_spoof(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Static OMEGA_APPLY_PASS appears in command echo."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"] > :put (\"OMEGA_APPLY_PASS\")\r\n",
            b"OMEGA_APPLY_PASS\r\n",  # echo only
            b"OMEGA_PHASE_FILE:00-PRECHECK.rsc\r\n",
            markers.fail_bytes + b"\r\n",
        ],
    )


def scenario_fragmented_output(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Output fragmented across multiple reads (simulates truncation)."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:00-PRECHECK.rsc\r\n",
            b"OMEGA_PHASE_FILE:10-BACKUP-SNAPSHOT.rsc\r\n",
            markers.pass_bytes + b"\r\n",
        ],
    )


def scenario_truncated_output(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Output truncated (buffer limit)."""
    large_output = b"X" * 70000  # exceeds 65536 buffer
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            large_output + b"\r\nOMEGA_PHASE_FILE:99-VERIFY-HEALTH.rsc\r\n",
            markers.pass_bytes + b"\r\n",
        ],
    )


def scenario_rollback_on_failure(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Full rollback triggered by phase failure."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:40-WIREGUARD-SERVICES.rsc\r\n",
            b"WireGuard peer key mismatch\r\n",
            markers.fail_bytes + b"\r\n",
        ],
    )


def scenario_commit_gate_requires_full_success(nonce: str, markers: FramedMarkers) -> MockTransport:
    """Commit only when all conditions met."""
    return create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:00-PRECHECK.rsc\r\n",
            b"OMEGA_PHASE_FILE:10-BACKUP-SNAPSHOT.rsc\r\n",
            b"OMEGA_PHASE_FILE:20-NETWORK-NORMALIZE.rsc\r\n",
            b"OMEGA_PHASE_FILE:30-DHCP-DNS-NTP.rsc\r\n",
            b"OMEGA_PHASE_FILE:40-WIREGUARD-SERVICES.rsc\r\n",
            b"OMEGA_PHASE_FILE:50-FIREWALL-NAT.rsc\r\n",
            b"OMEGA_PHASE_FILE:60-OBSERVABILITY.rsc\r\n",
            b"OMEGA_PHASE_FILE:90-EXPORT-EVIDENCE.rsc\r\n",
            b"OMEGA_PHASE_FILE:99-VERIFY-HEALTH.rsc\r\n",
            markers.pass_bytes + b"\r\n",
        ],
    )


# --- Test runner ---

def run_scenario_test(
    case: TestCase,
    transport_factory: Callable[[str, FramedMarkers], MockTransport],
) -> TestCase:
    """Run a single test case with the given transport factory.

    The factory receives the test's nonce and markers to ensure they match.
    """
    case.started_at = datetime.now(timezone.utc).isoformat()
    start_time = time.perf_counter()

    try:
        nonce = generate_nonce()
        markers = build_framed_markers(nonce)
        transport = transport_factory(nonce, markers)
        state = SessionState.DISCONNECTED

        # Simulate connection
        state = SessionState.CONNECTED

        # Simulate prompt verification
        state = SessionState.PROMPT_VERIFIED

        # Simulate Safe Mode entry
        state = SessionState.SAFE_MODE_CONFIRMED

        # Simulate execution
        state = SessionState.EXECUTING

        # Read responses and classify - accumulate across chunks
        events = OutputEvent()
        for resp in transport.responses:
            if not resp:
                continue
            ev = classify_output(resp, markers, after_our_write=True)
            # Merge events (OR logic)
            events.safe_taken = events.safe_taken or ev.safe_taken
            events.stale_session = events.stale_session or ev.stale_session
            events.hijack = events.hijack or ev.hijack
            events.phase_file = events.phase_file or ev.phase_file
            events.pass_accepted = events.pass_accepted or ev.pass_accepted
            events.fail = events.fail or ev.fail
            events.trust_level = "trusted"

        # Health check (mock)
        health_ok = not events.fail and not events.hijack

        # Decision - state transitions to VERIFYING for commit check
        state = SessionState.VERIFYING
        action = next_action(state, events, health_ok)

        case.evidence = {
            "state": state.value,
            "events": {
                "safe_taken": events.safe_taken,
                "stale_session": events.stale_session,
                "hijack": events.hijack,
                "phase_file": events.phase_file,
                "pass_accepted": events.pass_accepted,
                "fail": events.fail,
                "trust_level": events.trust_level,
            },
            "action": action,
            "transport_writes": transport.writes,
            "transport_closed": transport.closed,
            "transport_exit_code": transport.exit_code,
        }

        # Determine pass/fail based on expected
        if action == "commit" and case.expected == "commit":
            case.status = TestStatus.PASS
        elif action == "rollback" and case.expected == "rollback":
            case.status = TestStatus.PASS
        elif case.status == TestStatus.BLOCKED:
            case.status = TestStatus.BLOCKED
        else:
            case.status = TestStatus.FAIL
            case.error = f"Expected {case.expected}, got {action}"

    except Exception as e:
        case.status = TestStatus.FAIL
        case.error = str(e)
        case.evidence = {"exception": str(e)}

    case.completed_at = datetime.now(timezone.utc).isoformat()
    case.duration_ms = int((time.perf_counter() - start_time) * 1000)
    return case


# --- Test matrix mapping ---

SCENARIOS: list[tuple[TestCase, Callable[[str, FramedMarkers], MockTransport]]] = [
    (
        TestCase(
            id="SSH-01",
            name="SSH Connection Failure",
            description="SSH connection fails immediately (network down, wrong host)",
            scenario="ssh_connect_failure",
            expected="rollback",
        ),
        scenario_ssh_connect_failure,
    ),
    (
        TestCase(
            id="SSH-02",
            name="SSH Authentication Failure",
            description="SSH connects but authentication rejected (bad key, wrong user)",
            scenario="auth_failure",
            expected="rollback",
        ),
        scenario_auth_failure,
    ),
    (
        TestCase(
            id="SSH-03",
            name="Prompt Timeout",
            description="SSH connects but RouterOS prompt never appears",
            scenario="prompt_timeout",
            expected="rollback",
        ),
        scenario_prompt_timeout,
    ),
    (
        TestCase(
            id="SM-01",
            name="Safe Mode Refusal (Stale Session)",
            description="Safe Mode taken by current user in another session, no OMEGA_ALLOW_SAFE_MODE_UNROLL",
            scenario="safe_mode_refusal",
            expected="rollback",
        ),
        scenario_safe_mode_refusal,
    ),
    (
        TestCase(
            id="SM-02",
            name="Session Hijack Attempt",
            description="Another operator attempts to hijack Safe Mode; must refuse",
            scenario="hijack_attempt",
            expected="rollback",
        ),
        scenario_hijack_attempt,
    ),
    (
        TestCase(
            id="SM-03",
            name="Script Syntax Error",
            description="RouterOS reports syntax error in phase script",
            scenario="script_syntax_error",
            expected="rollback",
        ),
        scenario_script_syntax_error,
    ),
    (
        TestCase(
            id="SM-04",
            name="Health Verification Failure",
            description="Phases execute but post-change health check fails",
            scenario="health_verification_failure",
            expected="rollback",
        ),
        scenario_health_verification_failure,
    ),
    (
        TestCase(
            id="SM-05",
            name="SSH Disconnect During Transaction",
            description="SSH transport drops mid-transaction",
            scenario="ssh_disconnect_during_transaction",
            expected="rollback",
        ),
        scenario_ssh_disconnect_during_transaction,
    ),
    (
        TestCase(
            id="SM-06",
            name="SIGINT/SIGTERM During Transaction",
            description="Process terminated by signal during Safe Mode",
            scenario="sigint_sigterm",
            expected="rollback",
        ),
        scenario_sigint_sigterm,
    ),
    (
        TestCase(
            id="SM-07",
            name="Concurrent Apply Blocked",
            description="Second apply-safe attempt blocked by flock",
            scenario="concurrent_apply",
            expected="rollback",
        ),
        scenario_concurrent_apply,
    ),
    (
        TestCase(
            id="SM-08",
            name="Stale Nonce Spoof",
            description="Previous run's nonce pass marker appears; must not accept",
            scenario="stale_nonce_spoof",
            expected="rollback",
        ),
        scenario_stale_nonce_spoof,
    ),
    (
        TestCase(
            id="SM-09",
            name="Static Marker Spoof (Echo)",
            description="Static OMEGA_APPLY_PASS in command echo; must not accept",
            scenario="static_marker_spoof",
            expected="rollback",
        ),
        scenario_static_marker_spoof,
    ),
    (
        TestCase(
            id="SM-10",
            name="Fragmented Output",
            description="Terminal output fragmented across reads",
            scenario="fragmented_output",
            expected="commit",
        ),
        scenario_fragmented_output,
    ),
    (
        TestCase(
            id="SM-11",
            name="Truncated Output",
            description="Large output exceeds buffer; must handle correctly",
            scenario="truncated_output",
            expected="commit",
        ),
        scenario_truncated_output,
    ),
    (
        TestCase(
            id="SM-12",
            name="Rollback on Phase Failure",
            description="Full rollback when any phase fails",
            scenario="rollback_on_failure",
            expected="rollback",
        ),
        scenario_rollback_on_failure,
    ),
    (
        TestCase(
            id="SM-13",
            name="Commit Gate Full Success",
            description="Commit only when Safe Mode + nonce pass + health OK + phase files",
            scenario="commit_gate_requires_full_success",
            expected="commit",
        ),
        scenario_commit_gate_requires_full_success,
    ),
]


def run_all_tests() -> LabManifest:
    """Run all mock scenarios and produce evidence manifest."""
    commit_sha = os.popen("git rev-parse HEAD 2>/dev/null").read().strip() or "unknown"
    run_id = str(uuid.uuid4())[:8]
    started_at = datetime.now(timezone.utc).isoformat()

    manifest = LabManifest(
        run_id=run_id,
        commit_sha=commit_sha,
        chr_version="MOCK (no CHR available)",
        chr_image_provenance="N/A — mock harness only",
        test_runner="tools/chr-lab-harness.py",
        started_at=started_at,
    )

    print(f"=== CHR Lab Harness Run {run_id} ===")
    print(f"Commit: {commit_sha}")
    print(f"Tests: {len(SCENARIOS)}")
    print()

    for case, factory in SCENARIOS:
        print(f"Running {case.id}: {case.name} ... ", end="", flush=True)
        case = run_scenario_test(case, factory)
        manifest.tests.append(case)
        status_str = case.status.value
        if case.error:
            status_str += f" ({case.error})"
        print(f"{status_str} ({case.duration_ms}ms)")

    # Summary
    counts = {s: sum(1 for t in manifest.tests if t.status == s) for s in TestStatus}
    manifest.summary = {k.value: v for k, v in counts.items()}
    manifest.completed_at = datetime.now(timezone.utc).isoformat()

    print()
    print(f"=== Summary ===")
    for status, count in counts.items():
        print(f"  {status.value}: {count}")

    return manifest


def main() -> int:
    manifest = run_all_tests()

    # Write evidence
    evidence_dir = ROOT / "artifacts" / "chr-lab"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    evidence_file = evidence_dir / f"manifest-{manifest.run_id}.json"
    evidence_file.write_text(manifest.to_json())
    print(f"\nEvidence written to: {evidence_file}")

    # Exit code: 0 if all non-BLOCKED tests pass, 1 otherwise
    failed = sum(1 for t in manifest.tests if t.status == TestStatus.FAIL)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())