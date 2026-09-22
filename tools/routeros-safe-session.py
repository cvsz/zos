#!/usr/bin/env python3
"""Drive one RouterOS Safe Mode SSH session without Bash coprocess FDs."""

from __future__ import annotations

import argparse
import os
import re
import secrets
import selectors
import subprocess
import sys
import time
from pathlib import Path


class SessionError(RuntimeError):
    pass


class SessionState:
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


def generate_nonce(nbytes: int = 16) -> str:
    """สร้าง transaction nonce แบบสุ่ม (hex) สำหรับผูก pass/fail กับรอบเดียว."""
    return secrets.token_hex(nbytes)


def build_framed_markers(nonce: str) -> dict:
    """สร้าง pass/fail marker ที่ผูก nonce เพื่อกัน command echo ปลอม success."""
    return {
        "pass": f"OMEGA_APPLY_{nonce}_PASS",
        "fail": f"OMEGA_PHASE_{nonce}_FAIL",
    }


def classify_output(data: bytes, nonce: str) -> dict:
    """แยกประเภท output แบบ pure function; static PASS เดี่ยวๆ ไม่นับเป็น success."""
    markers = build_framed_markers(nonce)
    pass_marker = markers["pass"].encode()
    fail_marker = markers["fail"].encode()
    return {
        # ยืนยัน Safe Mode จาก RouterOS จริง
        "safe_taken": b"[Safe Mode taken]" in data
        or b"Taking Safe Mode session... Success!" in data,
        # session ค้างของ operator ปัจจุบัน (ต้อง opt-in ก่อน unroll)
        "stale_session": b"Safe Mode is taken by current user in another session." in data,
        # ห้าม hijack session ของ operator อื่นเด็ดขาด
        "hijack": b"Hijacking Safe Mode from someone" in data,
        # มี phase ถูกประมวลผลจริง
        "phase_file": b"OMEGA_PHASE_" in data and b"FILE:" in data,
        # ยอมรับเฉพาะ pass ที่ผูก nonce ตรงรอบนี้
        "pass_accepted": pass_marker in data,
        # fail ปิดแบบ fail-closed: รับทั้ง nonce marker และ legacy static FAIL
        "fail": fail_marker in data or b"OMEGA_PHASE_FAIL" in data,
    }


def next_action(state: str, events: dict, health_ok: bool) -> str:
    """ตัดสินใจ commit/rollback; commit ได้เฉพาะทางสำเร็จครบถ้วนเท่านั้น."""
    if (
        state in (SessionState.SAFE_MODE_CONFIRMED, SessionState.VERIFYING)
        and events.get("pass_accepted")
        and health_ok
        and not events.get("fail")
        and not events.get("hijack")
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
