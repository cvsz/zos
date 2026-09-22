#!/usr/bin/env python3
"""Drive one RouterOS Safe Mode SSH session without Bash coprocess FDs.

This module provides pure, testable functions for Safe Mode session management.
The main() entry point remains fail-closed (exit 4) until CHR integration
and rollback tests have verified evidence.
"""

from __future__ import annotations

import argparse
import os
import re
import secrets
import selectors
import subprocess
import sys
import time
from enum import Enum
from pathlib import Path
from typing import Callable, Optional


class SessionError(RuntimeError):
    pass


class SessionState(str, Enum):
    """สถานะวงจร Safe Mode (ยังไม่ผูกกับ live transport จนกว่า CHR จะ verify)."""

    DISCONNECTED = "DISCONNECTED"
    CONNECTED = "CONNECTED"
    PROMPT_VERIFIED = "PROMPT_VERIFIED"
    SAFE_MODE_CONFIRMED = "SAFE_MODE_CONFIRMED"
    EXECUTING = "EXECUTING"
    VERIFYING = "VERIFYING"
    COMMITTING = "COMMITTING"
    COMMITTED = "COMMITTED"
    ROLLING_BACK = "ROLLING_BACK"
    ROLLED_BACK = "ROLLED_BACK"
    UNKNOWN = "UNKNOWN"


class FramedMarkers:
    """Nonce-bound markers for a single transaction."""

    def __init__(self, pass_marker: str, fail_marker: str):
        self.pass_marker = pass_marker
        self.fail_marker = fail_marker

    @property
    def pass_bytes(self) -> bytes:
        return self.pass_marker.encode()

    @property
    def fail_bytes(self) -> bytes:
        return self.fail_marker.encode()


def generate_nonce(nbytes: int = 16) -> str:
    """สร้าง transaction nonce แบบสุ่ม (hex) สำหรับผูก pass/fail กับรอบเดียว."""
    return secrets.token_hex(nbytes)


def build_framed_markers(nonce: str) -> FramedMarkers:
    """สร้าง pass/fail marker ที่ผูก nonce เพื่อกัน command echo ปลอม success."""
    return FramedMarkers(
        pass_marker=f"OMEGA_APPLY_{nonce}_PASS",
        fail_marker=f"OMEGA_PHASE_{nonce}_FAIL",
    )


class OutputEvent:
    """Classified output event with trust level."""

    def __init__(
        self,
        safe_taken: bool = False,
        stale_session: bool = False,
        hijack: bool = False,
        phase_file: bool = False,
        pass_accepted: bool = False,
        fail: bool = False,
        trust_level: str = "untrusted",
    ):
        self.safe_taken = safe_taken
        self.stale_session = stale_session
        self.hijack = hijack
        self.phase_file = phase_file
        self.pass_accepted = pass_accepted
        self.fail = fail
        self.trust_level = trust_level

    def is_successful_commit_signal(self) -> bool:
        """True only if pass_accepted came from trusted RouterOS response."""
        return (
            self.pass_accepted
            and self.trust_level == "trusted"
            and self.phase_file
            and not self.fail
            and not self.hijack
        )


def classify_output(
    data: bytes,
    nonce_or_markers: str | FramedMarkers,
    *,
    after_our_write: bool = False,
) -> OutputEvent:
    """แยกประเภท output แบบ pure function.

    Key fix: nonce-bearing PASS in echoed command is NOT trusted.
    Only PASS that appears AFTER we've sent the transaction and RouterOS
    has processed it (indicated by after_our_write=True) is trusted.

    Accepts either a nonce string (for backward compatibility) or a
    FramedMarkers object (for explicit control).
    """
    if isinstance(nonce_or_markers, str):
        markers = build_framed_markers(nonce_or_markers)
    else:
        markers = nonce_or_markers
    pass_bytes = markers.pass_bytes
    fail_bytes = markers.fail_bytes

    return OutputEvent(
        safe_taken=b"[Safe Mode taken]" in data
        or b"Taking Safe Mode session... Success!" in data,
        stale_session=b"Safe Mode is taken by current user in another session." in data,
        hijack=b"Hijacking Safe Mode from someone" in data,
        phase_file=b"OMEGA_PHASE_" in data and b"FILE:" in data,
        pass_accepted=pass_bytes in data,
        fail=fail_bytes in data or b"OMEGA_PHASE_FAIL" in data,
        trust_level="trusted" if after_our_write else "untrusted",
    )


def next_action(state: SessionState, events: OutputEvent, health_ok: bool) -> str:
    """ตัดสินใจ commit/rollback; commit ได้เฉพาะทางสำเร็จครบถ้วนเท่านั้น."""
    if (
        state in (SessionState.SAFE_MODE_CONFIRMED, SessionState.VERIFYING)
        and events.is_successful_commit_signal()
        and health_ok
    ):
        return "commit"
    return "rollback"


def sanitize_for_evidence(data: bytes) -> bytes:
    """redact key/password/token ออกจาก evidence ก่อนเขียนไฟล์หรือ log."""
    redacted = re.sub(rb"private-key=\S+", b"private-key=[REDACTED]", data)
    redacted = re.sub(rb"(?i)(password|passwd|secret)=\S+", rb"\1=[REDACTED]", redacted)
    redacted = re.sub(rb"(?i)(token|bearer)\s*[:=]\s*\S+", rb"\1=[REDACTED]", redacted)
    redacted = re.sub(
        rb"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----",
        b"[REDACTED PRIVATE KEY BLOCK]",
        redacted,
    )
    return redacted


# --- Mock transport for testing ---

class MockTransport:
    """Deterministic mock SSH transport for testing without network."""

    def __init__(
        self,
        responses: list[bytes] = None,
        should_fail_connect: bool = False,
        should_timeout: bool = False,
        disconnect_after: Optional[int] = None,
        exit_code: int = 0,
    ):
        self.responses = responses or []
        self.writes: list[bytes] = []
        self.closed = False
        self.exit_code = exit_code
        self.should_fail_connect = should_fail_connect
        self.should_timeout = should_timeout
        self.disconnect_after = disconnect_after
        self._response_index = 0
        self._write_count = 0

    def write(self, data: bytes) -> None:
        self.writes.append(data)
        self._write_count += 1

    def read(self, n: int) -> bytes:
        if self.should_fail_connect and self._response_index == 0:
            raise ConnectionError("SSH connection failed")
        if self.should_timeout:
            raise TimeoutError("SSH read timeout")
        if self._response_index < len(self.responses):
            chunk = self.responses[self._response_index]
            self._response_index += 1
            if self.disconnect_after is not None and self._response_index >= self.disconnect_after:
                self.closed = True
            return chunk
        return b""

    def poll(self) -> Optional[int]:
        if self.closed:
            return self.exit_code
        return None

    def wait(self, timeout: float = 15) -> int:
        return self.exit_code

    def terminate(self) -> None:
        self.closed = True

    def kill(self) -> None:
        self.closed = True


def create_mock_transport(responses: list[bytes], **kwargs) -> MockTransport:
    """Factory for creating mock transports with pre-programmed responses."""
    return MockTransport(responses=responses, **kwargs)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--command-file", required=True)
    parser.add_argument("--output-file", required=True)
    parser.add_argument("--identity")
    parser.add_argument("--prompt-timeout", type=float, default=20.0)
    parser.add_argument("--safe-timeout", type=float, default=15.0)
    parser.add_argument("--transaction-timeout", type=float, default=240.0)
    return parser.parse_args()


def stream_chunk(chunk: bytes, evidence) -> None:
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()
    evidence.write(chunk)
    evidence.flush()


def read_until(
    proc: subprocess.Popen[bytes],
    evidence,
    buffer: bytearray,
    wanted: tuple[bytes, ...],
    timeout: float,
    abort: tuple[bytes, ...] = (),
) -> bytes:
    selector = selectors.DefaultSelector()
    if proc.stdout is None:
        raise SessionError("SSH stdout is unavailable")
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout

    def match_buffer() -> bytes | None:
        for token in abort:
            if token in buffer:
                raise SessionError(f"abort token observed: {token.decode(errors='replace')}")
        for token in wanted:
            if token in buffer:
                return token
        return None

    try:
        matched = match_buffer()
        if matched is not None:
            return matched

        while time.monotonic() < deadline:
            events = selector.select(timeout=min(0.5, max(0.0, deadline - time.monotonic())))
            if not events:
                if proc.poll() is not None:
                    raise SessionError(f"SSH exited early with code {proc.returncode}")
                continue

            chunk = os.read(proc.stdout.fileno(), 4096)
            if not chunk:
                if proc.poll() is not None:
                    raise SessionError(f"SSH closed output with code {proc.returncode}")
                continue

            stream_chunk(chunk, evidence)
            buffer.extend(chunk)
            if len(buffer) > 65536:
                del buffer[:-32768]

            matched = match_buffer()
            if matched is not None:
                return matched

        raise SessionError(
            "timeout waiting for: " + ", ".join(t.decode(errors="replace") for t in wanted)
        )
    finally:
        selector.close()


def drain(proc: subprocess.Popen[bytes], evidence, timeout: float = 10.0) -> None:
    if proc.stdout is None:
        return
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            events = selector.select(timeout=0.25)
            if not events:
                if proc.poll() is not None:
                    break
                continue
            chunk = os.read(proc.stdout.fileno(), 4096)
            if not chunk:
                if proc.poll() is not None:
                    break
                continue
            stream_chunk(chunk, evidence)
    finally:
        selector.close()


def send(proc: subprocess.Popen[bytes], payload: bytes) -> None:
    if proc.stdin is None:
        raise SessionError("SSH stdin is unavailable")
    proc.stdin.write(payload)
    proc.stdin.flush()


def enter_safe_mode(proc, evidence, receive_buffer, safe_timeout):
    safe_token = read_until(
        proc, evidence, receive_buffer,
        (b"[Safe Mode taken]", b"Taking Safe Mode session... Success!", b"Safe Mode is taken by current user in another session."),
        safe_timeout,
    )
    if safe_token == b"Safe Mode is taken by current user in another session.":
        if os.environ.get("OMEGA_ALLOW_SAFE_MODE_UNROLL") != "1":
            raise SessionError(
                "Safe Mode is taken by current user in another session; "
                "refusing to unroll without OMEGA_ALLOW_SAFE_MODE_UNROLL=1"
            )
        send(proc, b"u\n")
        drain(proc, evidence, timeout=3.0)
        safe_token = read_until(
            proc, evidence, receive_buffer,
            (b"[Safe Mode taken]", b"Taking Safe Mode session... Success!"),
            safe_timeout,
            abort=(b"Hijacking Safe Mode from someone",),
        )
    return safe_token


def release_safe_mode(proc, evidence, receive_buffer, safe_timeout):
    drain(proc, evidence, timeout=15.0)
    del receive_buffer[:]
    send(proc, b"\x18")
    read_until(proc, evidence, receive_buffer, (b"Releasing Safe Mode... Success!",), safe_timeout)
    read_until(proc, evidence, receive_buffer, (b"] >",), safe_timeout)
    send(proc, b"/quit\n")
    try:
        rc = proc.wait(timeout=15)
    except subprocess.TimeoutExpired as exc:
        raise SessionError("SSH did not exit after Safe Mode release and /quit") from exc
    if rc != 0:
        raise SessionError(f"SSH exited with code {rc} after OMEGA_APPLY_PASS")
    return rc


def rollback(proc: subprocess.Popen[bytes], evidence) -> None:
    if proc.poll() is not None:
        return
    try:
        send(proc, b"\x03")
        time.sleep(0.15)
        send(proc, b"\x04")
        drain(proc, evidence, timeout=5.0)
    except (BrokenPipeError, OSError, SessionError):
        pass
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def main() -> int:
    args = parse_args()
    # Live apply remains disabled until CHR-backed interactive Safe Mode verification.
    sys.stderr.write("Live apply blocked: interactive Safe Mode has not been verified.\n")
    return 4


if __name__ == "__main__":
    raise SystemExit(main())
