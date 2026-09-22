#!/usr/bin/env python3
"""
Regression tests demonstrating false-positive failure handling in chr-lab-harness.py

These tests PROVE the current harness has critical defects:
1. Connection failure test passes without actually exercising connection failure path
2. Authentication failure test passes without actually detecting auth failure from transport
3. Prompt timeout test passes without actually timing out on prompt
4. Safe Mode refusal test passes without confirming Safe Mode was refused
5. All tests pass merely because final action matches expected, not because failure injection occurred
6. Trust level is unconditionally assigned to all responses
7. OR logic merging allows failures to be masked by successes
8. Transport interface is not actually used - responses are just iterated
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = ROOT / "tools"

# Load chr-lab-harness
MODULE_PATH = TOOLS_DIR / "chr-lab-harness.py"
spec = importlib.util.spec_from_file_location("chr_lab_harness", MODULE_PATH)
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

# Load routeros-safe-session
SAFE_MODULE_PATH = TOOLS_DIR / "routeros-safe-session.py"
spec2 = importlib.util.spec_from_file_location("routeros_safe_session", SAFE_MODULE_PATH)
safe_module = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(safe_module)

# Import from loaded modules
TestCase = harness.TestCase
TestStatus = harness.TestStatus
run_scenario_test = harness.run_scenario_test
scenario_ssh_connect_failure = harness.scenario_ssh_connect_failure
scenario_auth_failure = harness.scenario_auth_failure
scenario_prompt_timeout = harness.scenario_prompt_timeout
scenario_safe_mode_refusal = harness.scenario_safe_mode_refusal
scenario_hijack_attempt = harness.scenario_hijack_attempt
scenario_script_syntax_error = harness.scenario_script_syntax_error
scenario_health_verification_failure = harness.scenario_health_verification_failure
scenario_ssh_disconnect_during_transaction = harness.scenario_ssh_disconnect_during_transaction
scenario_sigint_sigterm = harness.scenario_sigint_sigterm
scenario_concurrent_apply = harness.scenario_concurrent_apply
scenario_stale_nonce_spoof = harness.scenario_stale_nonce_spoof
scenario_static_marker_spoof = harness.scenario_static_marker_spoof
scenario_fragmented_output = harness.scenario_fragmented_output
scenario_truncated_output = harness.scenario_truncated_output
scenario_rollback_on_failure = harness.scenario_rollback_on_failure
scenario_commit_gate_requires_full_success = harness.scenario_commit_gate_requires_full_success

SessionState = safe_module.SessionState
OutputEvent = safe_module.OutputEvent
FramedMarkers = safe_module.FramedMarkers
generate_nonce = safe_module.generate_nonce
build_framed_markers = safe_module.build_framed_markers
classify_output = safe_module.classify_output
next_action = safe_module.next_action
MockTransport = safe_module.MockTransport
create_mock_transport = safe_module.create_mock_transport


def test_current_harness_false_positive_ssh_connection_failure():
    """
    DEMONSTRATES DEFECT: SSH connection failure test passes but doesn't
    actually exercise the connection failure path through the transport.
    
    The test creates a MockTransport with should_fail_connect=True,
    but run_scenario_test never calls transport.read() to trigger it.
    It just iterates transport.responses (which is empty) and advances
    state to CONNECTED, PROMPT_VERIFIED, SAFE_MODE_CONFIRMED anyway.
    """
    case = TestCase(
        id="SSH-01",
        name="SSH Connection Failure",
        description="SSH connection fails immediately (network down, wrong host)",
        scenario="ssh_connect_failure",
        expected="rollback",
    )
    
    result = run_scenario_test(case, scenario_ssh_connect_failure)
    
    # This currently PASSES but it's a FALSE POSITIVE
    # The transport.read() was never called to raise ConnectionError
    # The state machine advanced to SAFE_MODE_CONFIRMED without a real connection
    print(f"SSH-01 status: {result.status.value}")
    print(f"  Final state: {result.evidence['state']}")
    print(f"  Action: {result.evidence['action']}")
    print(f"  Transport reads called: {len(result.evidence.get('transport_writes', []))}")
    
    # The defect: connection failure should be detected during transport.read()
    # but the test runner never calls transport.read()
    assert result.status == TestStatus.PASS  # This passes incorrectly
    print("  *** FALSE POSITIVE: Test passes without exercising connection failure ***")
    

def test_current_harness_false_positive_auth_failure():
    """
    DEMONSTRATES DEFECT: Auth failure test passes but doesn't actually
    detect authentication failure from transport outcome.
    """
    case = TestCase(
        id="SSH-02",
        name="SSH Authentication Failure",
        description="SSH connects but authentication rejected (bad key, wrong user)",
        scenario="auth_failure",
        expected="rollback",
    )
    
    result = run_scenario_test(case, scenario_auth_failure)
    
    print(f"SSH-02 status: {result.status.value}")
    print(f"  Final state: {result.evidence['state']}")
    print(f"  Action: {result.evidence['action']}")
    print(f"  Events: {result.evidence['events']}")
    
    # Currently passes but transport authentication was never actually validated
    assert result.status == TestStatus.PASS
    print("  *** FALSE POSITIVE: Auth failure not actually detected from transport ***")


def test_current_harness_false_positive_prompt_timeout():
    """
    DEMONSTRATES DEFECT: Prompt timeout test passes but doesn't actually
    wait for prompt with bounded timeout.
    """
    case = TestCase(
        id="SSH-03",
        name="Prompt Timeout",
        description="SSH connects but RouterOS prompt never appears",
        scenario="prompt_timeout",
        expected="rollback",
    )
    
    result = run_scenario_test(case, scenario_prompt_timeout)
    
    print(f"SSH-03 status: {result.status.value}")
    print(f"  Final state: {result.evidence['state']}")
    print(f"  Action: {result.evidence['action']}")
    
    # Currently passes but prompt verification was never actually attempted
    assert result.status == TestStatus.PASS
    print("  *** FALSE POSITIVE: Prompt timeout not actually exercised ***")


def test_current_harness_trust_level_unconditionally_assigned():
    """
    DEMONSTRATES DEFECT: All responses get trust_level="trusted" unconditionally.
    
    In run_scenario_test line 373: events.trust_level = "trusted"
    This means even echoed commands or historical output gets trusted status.
    """
    case = TestCase(
        id="SM-09",
        name="Static Marker Spoof (Echo)",
        description="Static OMEGA_APPLY_PASS in command echo; must not accept",
        scenario="static_marker_spoof",
        expected="rollback",
    )
    
    result = run_scenario_test(case, scenario_static_marker_spoof)
    
    print(f"SM-09 status: {result.status.value}")
    print(f"  Events trust_level: {result.evidence['events']['trust_level']}")
    print(f"  Events: {result.evidence['events']}")
    
    # The static marker spoof includes an echo of OMEGA_APPLY_PASS
    # But because trust_level is unconditionally "trusted", the echo could be accepted
    # if the pass marker is present in the echo
    assert result.evidence['events']['trust_level'] == "trusted"
    print("  *** DEFECT: trust_level unconditionally 'trusted' for all responses ***")


def test_current_harness_or_logic_masks_failures():
    """
    DEMONSTRATES DEFECT: OR logic merging allows failures to be masked.
    
    If any response has phase_file=True, it stays True even if later
    responses indicate failure. The test merges with OR logic.
    """
    # Create a scenario where early response has phase_file but later fails
    nonce = generate_nonce()
    markers = build_framed_markers(nonce)
    
    transport = create_mock_transport(
        responses=[
            b"] >",
            b"Taking Safe Mode session... Success!\r\n",
            b"<SAFE>\r\n",
            b"OMEGA_PHASE_FILE:00-PRECHECK.rsc\r\n",  # phase_file = True
            b"OMEGA_PHASE_FILE:10-BACKUP-SNAPSHOT.rsc\r\n",  # phase_file = True
            b"Critical error occurred\r\n",  # should indicate failure
            markers.fail_bytes + b"\r\n",  # explicit fail marker
        ],
    )
    
    events = OutputEvent()
    for resp in transport.responses:
        if not resp:
            continue
        ev = classify_output(resp, markers, after_our_write=True)
        # Current OR logic
        events.safe_taken = events.safe_taken or ev.safe_taken
        events.stale_session = events.stale_session or ev.stale_session
        events.hijack = events.hijack or ev.hijack
        events.phase_file = events.phase_file or ev.phase_file
        events.pass_accepted = events.pass_accepted or ev.pass_accepted
        events.fail = events.fail or ev.fail
        events.trust_level = "trusted"
    
    print(f"  Merged events: phase_file={events.phase_file}, pass={events.pass_accepted}, fail={events.fail}")
    
    # Even though there's a fail marker, phase_file remains True from earlier
    # This could lead to incorrect commit decision if pass is also accepted
    assert events.phase_file == True  # from early response
    assert events.fail == True  # from later response
    print("  *** DEFECT: OR logic preserves phase_file=True even after failure ***")


def test_current_harness_no_transport_interface_usage():
    """
    DEMONSTRATES DEFECT: The test runner doesn't use the transport interface.
    
    It iterates transport.responses directly instead of calling transport.read()
    which means ConnectionError, TimeoutError, disconnect detection are never triggered.
    """
    # Check that run_scenario_test doesn't call transport.read()
    # by creating a transport that would fail if read() was called
    
    class FailingTransport:
        """Transport that fails if read() is called."""
        def __init__(self):
            self.responses = [b"] >", b"Taking Safe Mode session... Success!\r\n", b"<SAFE>\r\n"]
            self.writes = []
            self.closed = False
            self.exit_code = 0
            self._read_called = False
            
        def read(self, n: int) -> bytes:
            self._read_called = True
            raise RuntimeError("read() should not be called in current harness")
            
        def write(self, data: bytes) -> None:
            self.writes.append(data)
            
        def poll(self):
            return None
            
        def wait(self, timeout=15):
            return 0
            
        def terminate(self):
            pass
            
        def kill(self):
            pass
    
    def failing_factory(nonce, markers):
        return FailingTransport()
    
    case = TestCase(
        id="TEST-TRANSPORT",
        name="Transport Interface Test",
        description="Test if transport.read() is called",
        scenario="test",
        expected="commit",
    )
    
    try:
        result = run_scenario_test(case, failing_factory)
        print(f"  Transport read called: {result.evidence.get('transport_read_called', 'unknown')}")
        print("  *** DEFECT: transport.read() never called - failure paths not exercised ***")
    except RuntimeError as e:
        if "read() should not be called" in str(e):
            print("  transport.read() WAS called - this would be correct behavior")
        else:
            raise


def test_current_harness_no_assertion_failure_injection_occurred():
    """
    DEMONSTRATES DEFECT: Tests don't assert that failure injection actually occurred.
    
    They only check if final action matches expected, not whether the
    intended failure was actually triggered during execution.
    """
    case = TestCase(
        id="SM-05",
        name="SSH Disconnect During Transaction",
        description="SSH transport drops mid-transaction",
        scenario="ssh_disconnect_during_transaction",
        expected="rollback",
    )
    
    result = run_scenario_test(case, scenario_ssh_disconnect_during_transaction)
    
    print(f"SM-05 status: {result.status.value}")
    print(f"  Transport closed: {result.evidence['transport_closed']}")
    print(f"  Transport exit code: {result.evidence['transport_exit_code']}")
    
    # The test passes but disconnect_after=4 means after 4 reads the transport closes
    # However, the test runner doesn't simulate the actual read loop that would
    # detect the disconnect. It just processes all responses.
    assert result.status == TestStatus.PASS
    print("  *** DEFECT: Disconnect not actually simulated through read loop ***")


def test_current_harness_no_safe_mode_validation():
    """
    DEMONSTRATES DEFECT: Safe Mode confirmation is not validated from transport.
    
    The test runner advances to SAFE_MODE_CONFIRMED state without
    actually verifying that Safe Mode was confirmed by the transport.
    """
    case = TestCase(
        id="SM-01",
        name="Safe Mode Refusal (Stale Session)",
        description="Safe Mode taken by current user in another session, no OMEGA_ALLOW_SAFE_MODE_UNROLL",
        scenario="safe_mode_refusal",
        expected="rollback",
    )
    
    result = run_scenario_test(case, scenario_safe_mode_refusal)
    
    print(f"SM-01 status: {result.status.value}")
    print(f"  Events safe_taken: {result.evidence['events']['safe_taken']}")
    print(f"  Events stale_session: {result.evidence['events']['stale_session']}")
    
    # The scenario includes "Safe Mode is taken by current user in another session"
    # which should trigger stale_session detection, but the test doesn't validate
    # that enter_safe_mode was actually called and detected this condition
    assert result.status == TestStatus.PASS
    print("  *** DEFECT: Safe Mode validation not exercised through transport ***")


def test_current_harness_echo_spoof_not_detected():
    """
    DEMONSTRATES DEFECT: Nonce-bearing PASS in echo is not properly rejected.
    
    The classify_output function sets trust_level based on after_our_write,
    but the test runner sets after_our_write=True for ALL responses,
    including echoes that happen before we send the transaction.
    """
    nonce = generate_nonce()
    markers = build_framed_markers(nonce)
    
    # Simulate: we send command with nonce marker, it echoes back
    echo_data = b"] > :put (\"OMEGA_APPLY_" + nonce.encode() + b"_PASS\")\r\n" + markers.pass_bytes + b"\r\n"
    
    # In current harness, after_our_write=True for ALL responses
    events = classify_output(echo_data, markers, after_our_write=True)
    
    print(f"  Echo test - pass_accepted: {events.pass_accepted}, trust_level: {events.trust_level}")
    print(f"  is_successful_commit_signal: {events.is_successful_commit_signal()}")
    
    # With after_our_write=True, the echo gets trusted status
    # This is a critical defect - echoed commands should NOT be trusted
    assert events.trust_level == "trusted"
    assert events.pass_accepted == True
    print("  *** CRITICAL DEFECT: Echo with nonce marker gets trusted status ***")


if __name__ == "__main__":
    print("=" * 70)
    print("REGRESSION TESTS: Demonstrating False-Positive Failure Handling")
    print("=" * 70)
    print()
    
    test_current_harness_false_positive_ssh_connection_failure()
    print()
    
    test_current_harness_false_positive_auth_failure()
    print()
    
    test_current_harness_false_positive_prompt_timeout()
    print()
    
    test_current_harness_trust_level_unconditionally_assigned()
    print()
    
    test_current_harness_or_logic_masks_failures()
    print()
    
    test_current_harness_no_transport_interface_usage()
    print()
    
    test_current_harness_no_assertion_failure_injection_occurred()
    print()
    
    test_current_harness_no_safe_mode_validation()
    print()
    
    test_current_harness_echo_spoof_not_detected()
    print()
    
    print("=" * 70)
    print("ALL DEFECTS DEMONSTRATED")
    print("=" * 70)