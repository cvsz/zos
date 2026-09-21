#!/usr/bin/env python3
"""Generate file-level SPDX and SARIF security evidence for zOS."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = "zOS security-evidence 1"

PATTERNS = [
    ("PRIVATE_KEY_BLOCK", re.compile(r"-----BEGIN (?:RSA|OPENSSH|EC) PRIVATE KEY-----")),
    ("LITERAL_SECRET", re.compile(r"(?i)(?:password|token|private[-_ ]?key)\s*[:=]\s*[\"'][A-Za-z0-9_./+=-]{20,}[\"']")),
]


def tracked_files() -> list[Path]:
    proc = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, check=True, stdout=subprocess.PIPE
    )
    files: list[Path] = []
    for raw in proc.stdout.split(b"\0"):
        if not raw:
            continue
        path = ROOT / raw.decode("utf-8")
        if path.is_file():
            files.append(path)
    return sorted(files)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_spdx(files: list[Path], out: Path) -> None:
    created = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    doc = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "cvsz-zos-file-inventory",
        "documentNamespace": f"https://github.com/cvsz/zos/security-evidence/{created}",
        "creationInfo": {"created": created, "creators": [f"Tool: {GENERATOR}"]},
        "files": [],
    }
    for index, path in enumerate(files, 1):
        rel = path.relative_to(ROOT).as_posix()
        doc["files"].append(
            {
                "SPDXID": f"SPDXRef-File-{index}",
                "fileName": f"./{rel}",
                "checksums": [{"algorithm": "SHA256", "checksumValue": sha256(path)}],
            }
        )
    out.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def should_scan(rel: str) -> bool:
    # Scan all tracked text files. Documentation and example files are common
    # accidental secret-leak surfaces and must not be exempted.
    return True


def scan(files: list[Path]) -> list[dict]:
    findings: list[dict] = []
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        if not should_scan(rel):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for line_no, line in enumerate(text.splitlines(), 1):
            for code, pattern in PATTERNS:
                if pattern.search(line):
                    findings.append({"code": code, "path": rel, "line": line_no})
    return findings


def write_sarif(findings: list[dict], out: Path) -> None:
    results = []
    for finding in findings:
        results.append(
            {
                "ruleId": finding["code"],
                "level": "error",
                "message": {"text": "Potential committed secret pattern detected."},
                "locations": [
                    {
                        "physicalLocation": {
                            "artifactLocation": {"uri": finding["path"]},
                            "region": {"startLine": finding["line"]},
                        }
                    }
                ],
            }
        )
    sarif = {
        "version": "2.1.0",
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "zOS-secret-audit",
                        "version": "1",
                        "rules": [
                            {"id": "PRIVATE_KEY_BLOCK", "shortDescription": {"text": "Private key material"}},
                            {"id": "LITERAL_SECRET", "shortDescription": {"text": "Literal secret assignment"}},
                        ],
                    }
                },
                "results": results,
            }
        ],
    }
    out.write_text(json.dumps(sarif, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="artifacts/security")
    args = parser.parse_args()
    out_dir = ROOT / args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    files = tracked_files()
    findings = scan(files)
    write_spdx(files, out_dir / "spdx-files.json")
    write_sarif(findings, out_dir / "secret-audit.sarif")

    report = {
        "generator": GENERATOR,
        "tracked_files": len(files),
        "scanned_files": sum(1 for path in files if should_scan(path.relative_to(ROOT).as_posix())),
        "findings": findings,
        "result": "PASS" if not findings else "FAIL",
    }
    (out_dir / "audit-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))
    return 0 if not findings else 1


if __name__ == "__main__":
    raise SystemExit(main())
