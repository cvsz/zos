#!/usr/bin/env python3
"""Regression tests for the RouterOS Safe Mode session driver."""

from __future__ import annotations

import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import MagicMock

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "routeros-safe-session.py"

spec = importlib.util.spec_from_file_location("routeros_safe_session", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("failed to load RouterOS Safe Mode session driver")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

SessionError = module.SessionError
read_until = module.read_until
rollback = module.rollback
enter_safe_mode = module.enter_safe_mode
release_safe_mode = module.release_safe_mode
send = module.send
drain = module.drain


class MockProc:
    def __init__(self, returncode=0):
        self.stdout = MagicMock()
        self.stdout.fileno.return_value = tempfile.TemporaryFile().fileno()
        self.stdin = MagicMock()
        self.stdin.write = MagicMock()
        self.stdin.flush = MagicMock()
        self._returncode = returncode
        self._poll_result = None

    def poll(self):
        return self._poll_result

    def wait(self, timeout=None):
        return self._returncode

    def terminate(self):
        self._poll_result = -15

    def kill(self):
        self._poll_result = -9


def _make_evidence():
    return tempfile.TemporaryFile()


# --- read_until tests ---

def test_preloaded_safe_prompt_survives_previous_match() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(b"Taking Safe Mode session... Success!\r\n[admin@MikroTik] <SAFE>\r\n")
        with _make_evidence() as evidence:
            token = read_until(proc, evidence, receive_buffer, (b"<SAFE>",), 0.1)
        assert token == b"<SAFE>"
    finally:
        proc.terminate()
        proc.wait(timeout=2)


def test_read_until_timeout_raises() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray()
        with _make_evidence() as evidence:
            with pytest.raises(SessionError, match="timeout waiting for"):
                read_until(proc, evidence, receive_buffer, (b"NEVER_APPEARS",), 0.1)
    finally:
        proc.terminate()
        proc.wait(timeout=2)


def test_read_until_ssh_exit_raises() -> None:
    proc = subprocess.Popen(["true"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    receive_buffer = bytearray()
    with _make_evidence() as evidence:
        with pytest.raises(SessionError):
            read_until(proc, evidence, receive_buffer, (b"SOMETHING",), 0.5)


def test_read_until_abort_token_raises() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(b"Hijacking Safe Mode from someone detected\r\n")
        with _make_evidence() as evidence:
            with pytest.raises(SessionError, match="abort token observed"):
                read_until(proc, evidence, receive_buffer, (b"[Safe Mode taken]",), 0.1, abort=(b"Hijacking Safe Mode from someone",))
    finally:
        proc.terminate()
        proc.wait(timeout=2)


def test_read_until_preloaded_token_returns_immediately() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(b"] >")
        with _make_evidence() as evidence:
            token = read_until(proc, evidence, receive_buffer, (b"] >",), 0.1)
        assert token == b"] >"
    finally:
        proc.terminate()
        proc.wait(timeout=2)


# --- rollback tests ---

def test_rollback_sends_ctrl_c_and_ctrl_d() -> None:
    proc = MockProc()
    with tempfile.TemporaryFile() as evidence:
        rollback(proc, evidence)
    assert proc.stdin.write.call_count >= 2
    written = [c.args[0] for c in proc.stdin.write.call_args_list]
    assert b"\x03" in written
    assert b"\x04" in written


def test_rollback_terminates_running_process() -> None:
    proc = subprocess.Popen(["sleep", "30"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        with tempfile.TemporaryFile() as evidence:
            rollback(proc, evidence)
        assert proc.poll() is not None
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_rollback_no_op_if_already_closed() -> None:
    proc = subprocess.Popen(["true"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    proc.wait(timeout=2)
    with tempfile.TemporaryFile() as evidence:
        rollback(proc, evidence)


# --- enter_safe_mode tests ---

def test_enter_safe_mode_accepts_taking_session() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(b"Taking Safe Mode session... Success!")
        with _make_evidence() as evidence:
            token = enter_safe_mode(proc, evidence, receive_buffer, 0.1)
        assert token == b"Taking Safe Mode session... Success!"
    finally:
        proc.terminate()
        proc.wait(timeout=2)


def test_enter_safe_mode_accepts_bracket_token() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(b"[Safe Mode taken]")
        with _make_evidence() as evidence:
            token = enter_safe_mode(proc, evidence, receive_buffer, 0.1)
        assert token == b"[Safe Mode taken]"
    finally:
        proc.terminate()
        proc.wait(timeout=2)


def test_enter_safe_mode_fail_closed_without_env_var() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(b"Safe Mode is taken by current user in another session.")
        if "OMEGA_ALLOW_SAFE_MODE_UNROLL" in os.environ:
            del os.environ["OMEGA_ALLOW_SAFE_MODE_UNROLL"]
        with _make_evidence() as evidence:
            with pytest.raises(SessionError, match="OMEGA_ALLOW_SAFE_MODE_UNROLL"):
                enter_safe_mode(proc, evidence, receive_buffer, 0.1)
    finally:
        proc.terminate()
        proc.wait(timeout=2)


def test_enter_safe_mode_unroll_with_permission() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(b"Safe Mode is taken by current user in another.session.Taking Safe Mode session... Success!")
        os.environ["OMEGA_ALLOW_SAFE_MODE_UNROLL"] = "1"
        try:
            with _make_evidence() as evidence:
                token = enter_safe_mode(proc, evidence, receive_buffer, 0.1)
            assert token == b"Taking Safe Mode session... Success!"
        finally:
            del os.environ["OMEGA_ALLOW_SAFE_MODE_UNROLL"]
    finally:
        proc.terminate()
        proc.wait(timeout=2)


# --- release_safe_mode tests ---

def test_release_safe_mode_normal() -> None:
    proc = MockProc(returncode=0)
    drain_orig = module.drain
    read_until_orig = module.read_until
    module.drain = lambda *a, **kw: None
    module.read_until = lambda *a, **kw: a[3][0] if len(a) > 3 and a[3] else None
    try:
        receive_buffer = bytearray()
        with _make_evidence() as evidence:
            rc = release_safe_mode(proc, evidence, receive_buffer, 10.0)
        assert rc == 0
    finally:
        module.drain = drain_orig
        module.read_until = read_until_orig


def test_release_safe_mode_sends_quit_after_release() -> None:
    proc = MockProc(returncode=0)
    drain_orig = module.drain
    read_until_orig = module.read_until
    module.drain = lambda *a, **kw: None
    module.read_until = lambda *a, **kw: a[3][0] if len(a) > 3 and a[3] else None
    sent = []
    proc.stdin.write = lambda data: sent.append(data) or None
    try:
        receive_buffer = bytearray()
        with _make_evidence() as evidence:
            release_safe_mode(proc, evidence, receive_buffer, 10.0)
        assert b"/quit\n" in sent
    finally:
        module.drain = drain_orig
        module.read_until = read_until_orig


def test_release_safe_mode_raises_on_timeout() -> None:
    proc = MockProc()
    drain_orig = module.drain
    read_until_orig = module.read_until
    module.drain = lambda *a, **kw: None
    module.read_until = lambda *a, **kw: (_ for _ in ()).throw(SessionError("timeout waiting for: test"))
    try:
        receive_buffer = bytearray(b"some partial output")
        with _make_evidence() as evidence:
            with pytest.raises(SessionError, match="timeout waiting for"):
                release_safe_mode(proc, evidence, receive_buffer, 0.1)
    finally:
        module.drain = drain_orig
        module.read_until = read_until_orig


# --- integration tests ---

def test_phase_fail_triggers_rollback() -> None:
    proc = subprocess.Popen(["sleep", "30"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        receive_buffer = bytearray(
            b"] >"
            b"Taking Safe Mode session... Success!"
            b"<SAFE>"
            b"OMEGA_PHASE_FAIL"
        )
        with _make_evidence() as evidence:
            token = enter_safe_mode(proc, evidence, receive_buffer, 0.1)
            assert token == b"Taking Safe Mode session... Success!"
            result = read_until(proc, evidence, receive_buffer, (b"OMEGA_APPLY_PASS", b"OMEGA_PHASE_FAIL"), 0.1)
            assert result == b"OMEGA_PHASE_FAIL"
            rollback(proc, evidence)
        assert proc.poll() is not None
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_never_quit_during_safe() -> None:
    proc = subprocess.Popen(["cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sent = []
    original_write = proc.stdin.write

    def tracking_write(data):
        sent.append(data)
        original_write(data)

    proc.stdin.write = tracking_write
    try:
        receive_buffer = bytearray(
            b"] >"
            b"Taking Safe Mode session... Success!"
            b"<SAFE>"
        )
        with _make_evidence() as evidence:
            token = enter_safe_mode(proc, evidence, receive_buffer, 0.1)
            assert token == b"Taking Safe Mode session... Success!"
            read_until(proc, evidence, receive_buffer, (b"<SAFE>",), 0.1)
            with pytest.raises(SessionError):
                read_until(proc, evidence, receive_buffer, (b"OMEGA_APPLY_PASS",), 0.1)
        assert b"/quit\n" not in sent
    finally:
        proc.terminate()
        proc.wait(timeout=2)



def test_main_blocks_unprotected_ssh_apply(monkeypatch, tmp_path, capsys) -> None:
    """An unverified remote-command SSH invocation must never be started."""
    import argparse

    monkeypatch.setattr(module, "parse_args", lambda: argparse.Namespace(
        target="admin@192.0.2.1",
        command_file=str(tmp_path / "commands.rsc"),
        output_file=str(tmp_path / "evidence.log"),
        identity=None,
        prompt_timeout=1.0,
        safe_timeout=1.0,
        transaction_timeout=1.0,
    ))
    monkeypatch.setattr(module.subprocess, "Popen", lambda *args, **kwargs: pytest.fail(
        "unsafe SSH process started"
    ))
    assert module.main() != 0
    assert "Live apply blocked" in capsys.readouterr().err


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
