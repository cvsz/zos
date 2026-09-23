#!/usr/bin/env python3
"""Validate deterministic zOS evidence fixtures using only the Python standard library."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]

JSONL_FILES = {
    "analyzer": ROOT / "evidence/corpus/analyzer/golden.jsonl",
    "rag": ROOT / "evidence/corpus/rag/ranking.jsonl",
    "pr_salvage": ROOT / "evidence/corpus/pr-salvage/cases.jsonl",
    "discussions": ROOT / "evidence/corpus/discussions/triage.jsonl",
    "ci": ROOT / "evidence/ci/failure-modes.jsonl",
}


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"{path}:{line_no}: invalid JSON: {exc}") from exc
        if not isinstance(row, dict):
            raise AssertionError(f"{path}:{line_no}: row must be an object")
        rows.append(row)
    if not rows:
        raise AssertionError(f"{path}: corpus is empty")
    ids = [row.get("id") for row in rows]
    if any(not value for value in ids):
        raise AssertionError(f"{path}: every row needs a non-empty id")
    if len(ids) != len(set(ids)):
        raise AssertionError(f"{path}: duplicate ids found")
    return rows


def expected_object(row: dict) -> dict:
    expected = row.get("expected")
    if not isinstance(expected, dict):
        raise AssertionError(f"{row['id']}: expected must be an object")
    return expected


def validate_analyzer(rows: list[dict]) -> None:
    for row in rows:
        expected = expected_object(row)
        if expected.get("severity") not in {"low", "medium", "high", "critical"}:
            raise AssertionError(f"{row['id']}: invalid analyzer severity")
        if not expected.get("codes"):
            raise AssertionError(f"{row['id']}: analyzer codes required")


def validate_rag(rows: list[dict]) -> None:
    for row in rows:
        candidates = row.get("candidates", [])
        expected = expected_object(row)
        top1 = expected.get("top1")
        if not isinstance(candidates, list) or not all(isinstance(item, str) for item in candidates):
            raise AssertionError(f"{row['id']}: candidates must be a list of strings")
        if not isinstance(top1, str) or top1 not in candidates:
            raise AssertionError(f"{row['id']}: expected top1 must be a candidate")
        prefix = expected.get("ordered_prefix", [])
        if not isinstance(prefix, list):
            raise AssertionError(f"{row['id']}: ordered_prefix must be a list")
        if any(item not in candidates for item in prefix):
            raise AssertionError(f"{row['id']}: ordered_prefix contains unknown candidate")
        if prefix and prefix[0] != top1:
            raise AssertionError(f"{row['id']}: ordered_prefix must start with top1")


def validate_actions(rows: list[dict], allowed: set[str]) -> None:
    for row in rows:
        action = expected_object(row).get("action")
        if action not in allowed:
            raise AssertionError(f"{row['id']}: unsupported expected action {action!r}")


def validate_harness() -> None:
    path = ROOT / "evidence/harness/compatibility.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("canonical_contract") != "AGENTS.md":
        raise AssertionError("harness canonical contract must be AGENTS.md")
    surfaces = data.get("surfaces", [])
    expected_names = {"Claude", "Codex", "Gemini", "OpenCode", "Zed", "dmux"}
    if not isinstance(surfaces, list) or any(not isinstance(item, dict) for item in surfaces):
        raise AssertionError("harness surfaces must be a list of objects")
    names = {item.get("name") for item in surfaces}
    if names != expected_names:
        raise AssertionError(f"harness surfaces mismatch: {names} != {expected_names}")
    for item in surfaces:
        contract = item.get("contract")
        if not contract or not (ROOT / contract).is_file():
            raise AssertionError(f"missing harness contract: {contract}")
        must_reference = item.get("must_reference")
        if must_reference:
            text = (ROOT / contract).read_text(encoding="utf-8")
            if must_reference not in text:
                raise AssertionError(f"{contract} must reference {must_reference!r}")


def run_validation() -> dict:
    """Run independent checks and collect every failure without hiding later checks."""
    checks = [
        ("analyzer", lambda rows: validate_analyzer(rows)),
        ("rag", lambda rows: validate_rag(rows)),
        ("pr_salvage", lambda rows: validate_actions(
            rows, {"close_duplicate", "resolve_outdated_then_recheck",
                   "reopen_for_review", "salvage_safe_commits"})),
        ("discussions", lambda rows: validate_actions(
            rows, {"answer_or_link_docs", "no_followup_required",
                   "queue_for_maintainer_reply", "convert_to_issue_or_fix"})),
        ("ci", lambda rows: validate_ci(rows)),
    ]
    results = []
    started = time.monotonic()
    for name, check in checks:
        tick = time.monotonic()
        count = 0
        try:
            rows = load_jsonl(JSONL_FILES[name])
            count = len(rows)
            check(rows)
            status, error = "PASS", None
        except (AssertionError, OSError, ValueError, TypeError, KeyError) as exc:
            status, error = "FAIL", str(exc)
        results.append({
            "name": name, "status": status, "rows": count,
            "duration_ms": round((time.monotonic() - tick) * 1000),
            "error": error,
        })
    tick = time.monotonic()
    try:
        validate_harness()
        status, error = "PASS", None
    except (AssertionError, OSError, ValueError, TypeError, KeyError) as exc:
        status, error = "FAIL", str(exc)
    results.append({
        "name": "harness", "status": status, "rows": 0,
        "duration_ms": round((time.monotonic() - tick) * 1000),
        "error": error,
    })
    failures = sum(item["status"] == "FAIL" for item in results)
    return {
        "schema_version": 1,
        "status": "FAIL" if failures else "PASS",
        "total_rows": sum(item["rows"] for item in results),
        "checks_passed": len(results) - failures,
        "checks_failed": failures,
        "duration_ms": round((time.monotonic() - started) * 1000),
        "checks": results,
    }


def validate_ci(rows: list[dict]) -> None:
    for row in rows:
        if not row.get("signature") or not expected_object(row).get("diagnosis"):
            raise AssertionError(f"{row['id']}: CI signature and diagnosis required")


def format_text(report: dict) -> str:
    lines = ["zOS Evidence Validation", "=" * 62]
    for item in report["checks"]:
        name = item["name"].replace("_", " ").upper()
        count = f"{item['rows']} rows" if item["name"] != "harness" else "compatibility matrix"
        lines.append(f"[{item['status']:4}] {name:<16} {count:<22} {item['duration_ms']:>5} ms")
        if item["error"]:
            lines.append(f"       Error: {item['error']}")
    lines.extend([
        "-" * 62,
        (f"Result: {report['status']} | {report['checks_passed']}/{len(report['checks'])} checks "
         f"| {report['total_rows']} corpus rows | {report['duration_ms']} ms"),
    ])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate zOS evidence corpora and harness.")
    parser.add_argument("--format", choices=("text", "json"), default="text",
                        help="Human-readable summary or machine-readable JSON.")
    args = parser.parse_args(argv)
    report = run_validation()
    if args.format == "json":
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(format_text(report))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
