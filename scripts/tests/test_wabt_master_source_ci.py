"""Current-master WABT CI policy: source compilation, never native publishing."""
from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/wabt-master-source-ci.yml"
SCRIPT = ROOT / "scripts/ci/verify-wabt-master-source.sh"
MANIFEST = ROOT / "cache-contracts/wabt-producer/vcpkg.json"
OBSOLETE_WORKFLOW = ROOT / ".github/workflows/curl-wabt-source-package-qualification.yml"


class WabtMasterSourceOnlyPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.script = SCRIPT.read_text(encoding="utf-8")

    def test_ci_uses_master_as_authoritative_source_and_pr_is_premerge(self):
        self.assertIn("push:\n    branches: [master]", self.workflow)
        self.assertIn("pull_request:", self.workflow)
        self.assertIn("actions/checkout@v4", self.workflow)
        self.assertIn("persist-credentials: false", self.workflow)
        self.assertIn("scripts/setup-vcpkg-curl-cache.py", self.workflow)
        self.assertIn("scripts/ci/verify-wabt-master-source.sh", self.workflow)
        self.assertIn('git -C "$GITHUB_WORKSPACE" rev-parse HEAD', self.script)

    def test_no_native_registry_write_or_implicit_binary_restore(self):
        self.assertIn("permissions:\n  contents: read", self.workflow)
        self.assertNotIn("packages: write", self.workflow)
        self.assertNotIn("packages: read", self.workflow)
        for source in (self.workflow, self.script):
            for forbidden in ("--publish", "PackagePublish/2.0.0",
                              "dotnet restore", "nuget.exe",
                              "--only-binarycaching",
                              "setup-vcpkg-cache/action.yml"):
                with self.subTest(forbidden=forbidden):
                    self.assertNotIn(forbidden, source)
        self.assertIn("export VCPKG_BINARY_SOURCES=clear", self.script)
        self.assertIn("--binarysource=clear", self.script)
        self.assertNotIn("nupkg", self.script.lower())
        self.assertNotIn("cbc2c2ae595865ddfbb317e7822e4f81633cb5dae4103085140643d7fb77f946",
                         self.workflow + self.script)

    def test_source_only_build_is_not_an_unadvertised_cache_fallback(self):
        self.assertIn("--x-manifest-root=$manifest", self.script)
        self.assertIn("--triplet=x64-linux --host-triplet=x64-linux", self.script)
        self.assertIn("test -z", self.script)
        self.assertIn("A native binary-cache ZIP was produced", self.script)
        self.assertIn("WABT did not compile from the selected master source graph",
                      self.script)
        self.assertIn("test -x", self.script)
        self.assertIn("wast2json", self.script)

    def test_actual_wast_to_json_and_semantic_assertion_are_checked(self):
        self.assertIn("(module", self.script)
        self.assertIn('i32.const 42', self.script)
        self.assertIn('(assert_return (invoke "answer")', self.script)
        self.assertIn('commands[0].get("type") != "module"', self.script)
        self.assertIn('command.get("type") == "assert_return"', self.script)

    def test_master_owned_pinned_manifest_drives_wabt_version(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(data["name"], "qigao-wabt-producer")
        self.assertEqual(data["dependencies"], [
            {"name": "wabt", "features": ["tools"]}
        ])
        self.assertRegex(data["builtin-baseline"], r"^[a-f0-9]{40}$")
        self.assertIn("cache-contracts/wabt-producer", self.script)
        self.assertNotIn("1.0.42-vcpkg", self.script)

    def test_obsolete_missing_l2_publisher_workflow_is_gone(self):
        self.assertFalse(OBSOLETE_WORKFLOW.exists())


if __name__ == "__main__":
    unittest.main()
