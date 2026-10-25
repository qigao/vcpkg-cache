"""Prevent source handoff CI from silently disappearing due to shell quoting."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
FILE = ROOT / "tools/check_gmssl_crypto_workflow.py"
spec = importlib.util.spec_from_file_location("gmssl_ci_guard", FILE)
assert spec is not None and spec.loader is not None
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class WorkflowShellQualification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = (
            ROOT / ".github/workflows/gmssl-crypto-handoff.yml"
        ).read_text(encoding="utf-8")

    def test_complete_workflow_has_two_real_shell_blocks(self):
        self.assertEqual(len(guard.extract_run_blocks(self.workflow)), 2)
        self.assertEqual(guard.validate(self.workflow), [])

    def test_truncated_negative_regex_must_fail(self):
        damaged = self.workflow.replace("GmSSLConfig[.]cmake)$'", "GmSSLConfig[.]cmake)")
        self.assertNotEqual(self.workflow, damaged)
        self.assertTrue(guard.validate(damaged))

    def test_duplicated_artifact_upload_is_forbidden(self):
        extra = self.workflow + "\n- uses: actions/upload-artifact@v4\n"
        self.assertTrue(guard.validate(extra))

    def test_malformed_shell_block_is_rejected(self):
        bad = self.workflow.replace("          fi\n", "          if true; then\n", 1)
        self.assertNotEqual(self.workflow, bad)
        self.assertTrue(guard.validate(bad))


if __name__ == "__main__":
    unittest.main()
