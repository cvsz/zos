#!/usr/bin/env python3
"""Drive one RouterOS Safe Mode SSH session without Bash coprocess FDs."""

from __future__ import annotations

import argparse
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path


class SessionError(RuntimeError):
    pass


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
    wanted: tuple[bytes, ...],
    timeout: float,
    abort: tuple[bytes, ...] = (),
) -> bytes:
    selector = selectors.DefaultSelector()
    if proc.stdout is None:
        raise SessionError("SSH stdout is unavailable")
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    buf = bytearray()

    try:
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
            buf.extend(chunk)
            if len(buf) > 65536:
                del buf[:-32768]

            for token in abort:
                if token in buf:
                    raise SessionError(f"abort token observed: {token.decode(errors='replace')}")
            for token in wanted:
                if token in buf:
                    return token

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


def rollback(proc: subprocess.Popen[bytes], evidence) -> None:
    if proc.poll() is not None:
        return
    try:
        # Ctrl-C clears any partial input/current action; Ctrl-D on an empty
        # Safe Mode prompt exits and asks RouterOS to undo floating changes.
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
    command = Path(args.command_file).read_bytes().rstrip(b"\n") + b"\n"
    output_path = Path(args.output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    ssh_cmd = [
        "ssh",
        "-tt",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=8",
        "-o",
        "ServerAliveInterval=20",
        "-o",
        "ServerAliveCountMax=3",
    ]
    if args.identity:
        ssh_cmd.extend(["-i", args.identity, "-o", "IdentitiesOnly=yes"])
    ssh_cmd.append(args.target)

    safe_mode = False
    proc = subprocess.Popen(
        ssh_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )

    with output_path.open("wb") as evidence:
        try:
            read_until(proc, evidence, (b"] >",), args.prompt_timeout)

            send(proc, b"\x18")
            safe_token = read_until(
                proc,
                evidence,
                (b"[Safe Mode taken]", b"Taking Safe Mode session... Success!"),
                args.safe_timeout,
                abort=(b"Hijacking Safe Mode from someone",),
            )
            safe_mode = True
            sys.stdout.write(
                f"\nOMEGA_SAFE_MODE_CONFIRMED ({safe_token.decode(errors='replace')})\n"
            )
            sys.stdout.flush()

            read_until(proc, evidence, (b"<SAFE>",), args.safe_timeout)

            send(proc, command)
            result = read_until(
                proc,
                evidence,
                (b"OMEGA_APPLY_PASS", b"OMEGA_PHASE_FAIL"),
                args.transaction_timeout,
            )
            if result == b"OMEGA_PHASE_FAIL":
                raise SessionError("RouterOS transaction reported OMEGA_PHASE_FAIL")

            # The success branch executes /quit immediately after the PASS marker.
            drain(proc, evidence, timeout=15.0)
            try:
                rc = proc.wait(timeout=5)
            except subprocess.TimeoutExpired as exc:
                raise SessionError("SSH did not exit after successful /quit") from exc
            if rc != 0:
                raise SessionError(f"SSH exited with code {rc} after OMEGA_APPLY_PASS")
            return 0

        except SessionError as exc:
            sys.stderr.write(f"RouterOS Safe Mode session error: {exc}\n")
            if safe_mode:
                rollback(proc, evidence)
            elif proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)
            return 4


if __name__ == "__main__":
    raise SystemExit(main())
