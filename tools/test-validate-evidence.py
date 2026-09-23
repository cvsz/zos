#!/usr/bin/env python3
"""Regression tests for evidence validator reporting (no router or network access)."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("validate-evidence.py")
spec = importlib.util.spec_from_file_location("zos_evidence_validator", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class EvidenceOutputTests(unittest.TestCase):
    def test_text_and_json_pass(self):
        with patch.object(validator, "run_validation", return_value={
            "schema_version": 1, "status": "PASS", "total_rows": 5,
            "checks_passed": 2, "checks_failed": 0, "duration_ms": 3,
            "checks": [
                {"name": "analyzer", "status": "PASS", "rows": 5, "duration_ms": 1, "error": None},
                {"name": "harness", "status": "PASS", "rows": 0, "duration_ms": 2, "error": None},
            ],
        }):
            for fmt in ("text", "json"):
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    self.assertEqual(validator.main(["--format", fmt]), 0)
                if fmt == "json":
                    self.assertEqual(json.loads(out.getvalue())["checks_passed"], 2)
                else:
                    self.assertIn("2/2 checks", out.getvalue())
                    self.assertIn("ANALYZER", out.getvalue())

    def test_failure_exit_and_independent_checks(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths = {}
            for name in validator.JSONL_FILES:
                path = Path(tmp) / f"{name}.jsonl"
                path.write_text('{"id":"fixture","expected":{}}\\n', encoding="utf-8")
                paths[name] = path
            with patch.object(validator, "JSONL_FILES", paths), patch.object(
                validator, "validate_harness", side_effect=AssertionError("missing contract")
            ):
                report = validator.run_validation()
            self.assertEqual(report["status"], "FAIL")
            self.assertEqual(len(report["checks"]), 6)
            self.assertEqual(report["checks"][-1]["error"], "missing contract")
            self.assertGreater(report["checks_failed"], 0)
            self.assertIn("Error:", validator.format_text(report))

    def test_empty_and_duplicate_ids_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "cases.jsonl"
            path.write_text("", encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "empty"):
                validator.load_jsonl(path)
            path.write_text('{"id":"same"}\\n{"id":"same"}\\n', encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "duplicate"):
                validator.load_jsonl(path)


if __name__ == "__main__":
    unittest.main()
