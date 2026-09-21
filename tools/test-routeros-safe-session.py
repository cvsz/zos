#!/usr/bin/env python3
"""Regression tests for the RouterOS Safe Mode session driver."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "routeros-safe-session.py"

spec = importlib.util.spec_from_file_location("routeros_safe_session", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("failed to load RouterOS Safe Mode session driver")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_preloaded_safe_prompt_survives_previous_match() -> None:
    proc = subprocess.Popen(
        ["cat"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    try:
        receive_buffer = bytearray(
            b"Taking Safe Mode session... Success!\r\n"
            b"[admin@MikroTik] <SAFE>\r\n"
        )
        with tempfile.TemporaryFile() as evidence:
            token = module.read_until(
                proc,
                evidence,
                receive_buffer,
                (b"<SAFE>",),
                0.1,
            )
        assert token == b"<SAFE>"
    finally:
        proc.terminate()
        proc.wait(timeout=2)


if __name__ == "__main__":
    test_preloaded_safe_prompt_survives_previous_match()
    print("RouterOS Safe Mode session regression tests PASS")
