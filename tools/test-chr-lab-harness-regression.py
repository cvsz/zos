#!/usr/bin/env python3
"""Regression tests for the event-driven CHR lab harness.

Each test exercises a real failure-injection path through the transport
interface (``transport.read()``/``transport.write()``) and asserts that the
intended failure condition was actually detected — not merely that the final
action matched. Uses the current event-driven API
(``run_event_driven_test`` + ``expected_action``/``expected_conditions``).

Loader note: dynamically loaded modules are registered in ``sys.modules``
before execution, as required for ``@dataclass`` on Python 3.14.
"""

from __future__ import annotations

import importlib.util
import sys
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = ROOT / "tools"


def _load(name: str, filename: str):
    path = TOOLS_DIR / filename
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    # Python 3.14 dataclass processing needs the module in sys.modules.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


harness = _load("chr_lab_harness", "chr-lab-harness.py")
safe_module = _load("routeros_safe_session", "routeros-safe-session.py")

TestCase = harness.TestCase
TestStatus = harness.TestStatus
run_event_driven_test = harness.run_event_driven_test


def fresh_case(cid, name, desc, scenario, expected_action, expected_conditions):
    """สร้าง test case ใหม่ทุกครั้ง (ไม่ใช้ SCENARIOS ร่วมกันเพราะ runner จะ mutate case)."""
    return TestCase(
        id=cid,
        name=name,
        description=desc,
        scenario=scenario,
        expected_action=expected_action,
        expected_conditions=dict(expected_conditions),
    )


def counting_factory(factory, calls):
    """ห่อ factory เพื่อนับว่า transport.read() ถูกเรียกจริง."""

    def wrap(nonce, markers):
        transport = factory(nonce, markers)
        orig_read = transport.read

        def read(n):
            calls.append(n)
            return orig_read(n)

        transport.read = read
        return transport

    return wrap


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def test_connection_failure_exercised_through_transport_read():
    """SSH-01: read() ต้องถูกเรียกและ raise ConnectionError (ไม่ใช่แค่ iterate responses)."""
    calls = []
    case = fresh_case(
        "SSH-01", "SSH Connection Failure",
        "SSH connection fails immediately", "ssh_connect_failure",
        "rollback", {"connection_failed": True},
    )
    result = run_event_driven_test(
        case, counting_factory(harness.scenario_ssh_connect_failure, calls)
    )
    check(calls, "transport.read() was never called; connection failure not exercised")
    check(result.conditions_met.get("connection_failed") is True,
          f"connection_failed not detected: {result.conditions_met}")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")
    check(result.transport.writes == [], "no Safe Mode write must occur without a connection")


def test_auth_failure_detected_from_transport():
    """SSH-02: Permission denied จาก transport ต้องกลายเป็น auth_failed + rollback."""
    case = fresh_case(
        "SSH-02", "SSH Authentication Failure",
        "SSH connects but authentication rejected", "auth_failure",
        "rollback", {"connection_attempted": True, "auth_failed": True},
    )
    result = run_event_driven_test(case, harness.scenario_auth_failure)
    check(result.transport._response_index > 0,
          "transport.read() never consumed the Permission denied response")
    check(result.conditions_met.get("auth_failed") is True,
          f"auth_failed not detected: {result.conditions_met}")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")


def test_prompt_timeout_detected():
    """SSH-03: prompt ไม่ปรากฏต้องกลายเป็น prompt_timeout + rollback (ผ่าน TimeoutError จริง)."""
    calls = []
    case = fresh_case(
        "SSH-03", "Prompt Timeout",
        "SSH connects but RouterOS prompt never appears", "prompt_timeout",
        "rollback", {"prompt_timeout": True},
    )
    result = run_event_driven_test(
        case, counting_factory(harness.scenario_prompt_timeout, calls)
    )
    check(calls, "transport.read() was never called; prompt timeout not exercised")
    check(result.conditions_met.get("prompt_timeout") is True,
          f"prompt_timeout not detected: {result.conditions_met}")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")


def test_safe_mode_refusal_without_unroll():
    """SM-01 (refusal): stale session ต้องถูกปฏิเสธโดยไม่ unroll session ของผู้อื่น."""
    case = fresh_case(
        "SM-01", "Safe Mode Refusal (Stale Session)",
        "Safe Mode taken by current user in another session", "safe_mode_refusal",
        "rollback", {"safe_mode_refused": True},
    )
    result = run_event_driven_test(case, harness.scenario_safe_mode_refusal)
    check(len(result.transport.writes) == 1,
          f"Safe Mode entry must be attempted once via transport, got {len(result.transport.writes)} writes")
    check(result.conditions_met.get("safe_mode_refused") is True,
          f"safe_mode_refused not detected: {result.conditions_met}")
    check(result.events.safe_taken is False, "Safe Mode must not be marked taken on refusal")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")


def test_hijack_attempt_refused():
    """SM-02: ความพยายาม hijack ต้องถูกตรวจจับและ rollback (ห้ามยึด session ผู้อื่น)."""
    case = fresh_case(
        "SM-02", "Session Hijack Attempt",
        "Another operator attempts to hijack Safe Mode", "hijack_attempt",
        "rollback", {"hijack_detected": True},
    )
    result = run_event_driven_test(case, harness.scenario_hijack_attempt)
    check(result.conditions_met.get("hijack_detected") is True,
          f"hijack_detected not detected: {result.conditions_met}")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")


def test_static_marker_spoof_rejected():
    """SM-09: static OMEGA_APPLY_PASS ใน echo ต้องไม่ถูกนับเป็น execution proof."""
    case = fresh_case(
        "SM-09", "Static Marker Spoof (Echo)",
        "Static OMEGA_APPLY_PASS in command echo", "static_marker_spoof",
        "rollback", {"static_spoof_detected": True, "rollback_triggered": True},
    )
    result = run_event_driven_test(case, harness.scenario_static_marker_spoof)
    check(result.conditions_met.get("static_spoof_detected") is True,
          f"static_spoof_detected not detected: {result.conditions_met}")
    check(result.events.pass_accepted is False,
          "echoed static PASS marker must never be accepted as commit proof")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")


def test_stale_nonce_spoof_rejected():
    """SM-08: pass marker ของ nonce เก่าต้องถูกปฏิเสธ (ผูก nonce รอบปัจจุบันเท่านั้น)."""
    case = fresh_case(
        "SM-08", "Stale Nonce Spoof",
        "Previous run nonce pass marker appears", "stale_nonce_spoof",
        "rollback", {"stale_nonce_detected": True, "rollback_triggered": True},
    )
    result = run_event_driven_test(case, harness.scenario_stale_nonce_spoof)
    check(result.conditions_met.get("stale_nonce_detected") is True,
          f"stale_nonce_detected not detected: {result.conditions_met}")
    check(result.events.pass_accepted is False,
          "stale nonce PASS marker must never satisfy the commit gate")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")


def test_disconnect_mid_transaction_rollback():
    """SM-05: transport ขาดกลาง transaction ต้องตรวจจับและ rollback."""
    case = fresh_case(
        "SM-05", "SSH Disconnect During Transaction",
        "SSH transport drops mid-transaction", "ssh_disconnect_during_transaction",
        "rollback", {"disconnect_detected": True, "rollback_triggered": True},
    )
    result = run_event_driven_test(
        case, harness.scenario_ssh_disconnect_during_transaction
    )
    check(result.transport.closed is True, "transport must report closed after disconnect")
    check(result.conditions_met.get("disconnect_detected") is True,
          f"disconnect_detected not detected: {result.conditions_met}")
    check(result.conditions_met.get("rollback_triggered") is True,
          "disconnect during execution must trigger rollback")
    check(result.action == "rollback", f"expected rollback, got {result.action}")
    check(case.status == TestStatus.PASS, f"case status {case.status}: {case.error}")


def test_commit_gate_and_rollback_conditions():
    """SM-13 commit เฉพาะเมื่อครบทุกเงื่อนไข; SM-12 rollback เมื่อ phase ล้มเหลว."""
    ok_case = fresh_case(
        "SM-13", "Commit Gate Full Success",
        "Commit only when all conditions met", "commit_gate_requires_full_success",
        "commit", {"all_phases_completed": True, "commit_gate_satisfied": True},
    )
    ok_result = run_event_driven_test(
        ok_case, harness.scenario_commit_gate_requires_full_success
    )
    check(ok_result.action == "commit", f"expected commit, got {ok_result.action}")
    check(ok_result.conditions_met.get("commit_gate_satisfied") is True,
          "commit gate must be satisfied on full success")
    check(ok_case.status == TestStatus.PASS, f"case status {ok_case.status}: {ok_case.error}")

    fail_case = fresh_case(
        "SM-12", "Rollback on Phase Failure",
        "Full rollback when any phase fails", "rollback_on_failure",
        "rollback", {"rollback_triggered": True},
    )
    fail_result = run_event_driven_test(
        fail_case, harness.scenario_rollback_on_failure
    )
    check(fail_result.conditions_met.get("rollback_triggered") is True,
          "phase failure must trigger rollback")
    check(fail_result.action == "rollback", f"expected rollback, got {fail_result.action}")
    check(fail_case.status == TestStatus.PASS,
          f"case status {fail_case.status}: {fail_case.error}")


TESTS = [
    test_connection_failure_exercised_through_transport_read,
    test_auth_failure_detected_from_transport,
    test_prompt_timeout_detected,
    test_safe_mode_refusal_without_unroll,
    test_hijack_attempt_refused,
    test_static_marker_spoof_rejected,
    test_stale_nonce_spoof_rejected,
    test_disconnect_mid_transaction_rollback,
    test_commit_gate_and_rollback_conditions,
]


def main() -> int:
    print("=" * 70)
    print("CHR lab harness regression: event-driven failure-injection verification")
    print("=" * 70)
    passed = 0
    failed = 0
    for test in TESTS:
        try:
            test()
            print(f"PASS: {test.__name__}")
            passed += 1
        except Exception as exc:  # noqa: BLE001 — report every failure explicitly
            print(f"FAIL: {test.__name__}: {exc}")
            traceback.print_exc()
            failed += 1
    print("=" * 70)
    print(f"regression: PASS={passed} FAIL={failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
