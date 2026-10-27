"""WABT native tooling uses the same exact files-cache verifier as generic Linux."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WARM = ROOT / ".github/workflows/warm-cache.yml"
PR = ROOT / ".github/workflows/curl-warm-wabt-reader-preflight.yml"
GENERIC_PR = ROOT / ".github/workflows/curl-warm-linux-reader-preflight.yml"
HELPER = ROOT / "scripts/ci/verify-native-linux-l2.sh"
MANIFEST = ROOT / "cache-contracts/wabt-producer/vcpkg.json"


class WabtNativeCurlReader(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.warm = WARM.read_text(encoding="utf-8")
        cls.wabt = cls.warm.split("\n  wabt-tools-cache-contract:\n", 1)[1].split(
            "\n  android:\n", 1)[0]
        cls.preflight = PR.read_text(encoding="utf-8")
        cls.generic = GENERIC_PR.read_text(encoding="utf-8")
        cls.helper = HELPER.read_text(encoding="utf-8")

    def test_production_and_pr_both_use_one_strict_wabt_profile(self):
        for name, source in (("production", self.wabt), ("PR", self.preflight)):
            with self.subTest(name=name):
                self.assertIn("uses: ./.github/actions/setup-vcpkg-curl-cache", source)
                self.assertIn("manifest-root: cache-contracts/wabt-producer", source)
                self.assertIn("mode: read", source)
                self.assertIn("triplet: x64-linux", source)
                self.assertIn("host-triplet: x64-linux", source)
                self.assertIn("bash scripts/ci/verify-native-linux-l2.sh wabt", source)
                self.assertNotIn("uses: ./.github/actions/setup-vcpkg-cache", source)
                self.assertNotIn("packages: write", source)

    def test_wabt_and_generic_explicitly_share_single_native_consumer(self):
        self.assertIn("bash scripts/ci/verify-native-linux-l2.sh generic", self.generic)
        self.assertIn("bash scripts/ci/verify-native-linux-l2.sh wabt", self.wabt)
        self.assertIn('if [[ "$#" -ne 1 ]]', self.helper)
        self.assertIn('case "$profile" in', self.helper)
        self.assertIn('Unsupported exact native cache profile', self.helper)
        self.assertIn('cache-contracts/wabt-producer', self.helper)
        self.assertIn('test -x "$install_root/x64-linux/tools/wabt/wast2json"', self.helper)
        self.assertIn("--only-binarycaching", self.helper)
        self.assertNotIn('rm -rf "$VCPKG_BINARY_CACHE"', self.helper)
        self.assertNotIn("nugetconfig", self.helper)

    def test_local_cache_is_fresh_before_http_download(self):
        for name, source in (("production", self.wabt), ("PR", self.preflight)):
            with self.subTest(name=name):
                before = source.index("VCPKG_BINARY_CACHE=$cache")
                after = source.index("uses: ./.github/actions/setup-vcpkg-curl-cache")
                self.assertLess(before, after)
                self.assertIn('rm -rf "$cache"', source[:after])
        self.assertIn("packages: read", self.preflight)
        self.assertNotIn("--publish", self.preflight)

    def test_checked_in_manifest_requires_native_wabt_tools(self):
        import json
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(len(data["dependencies"]), 1)
        self.assertEqual(data["dependencies"][0]["name"], "wabt")
        self.assertEqual(data["dependencies"][0]["features"], ["tools"])
        self.assertEqual(len(data["builtin-baseline"]), 40)


if __name__ == "__main__":
    unittest.main()
