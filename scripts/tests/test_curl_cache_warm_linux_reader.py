"""Cold-L2 Linux generic vcpkg ABI admission uses only published curl payloads."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WARM = ROOT / ".github/workflows/warm-cache.yml"
PREFLIGHT = ROOT / ".github/workflows/curl-warm-linux-reader-preflight.yml"
HELPER = ROOT / "scripts/ci/verify-native-linux-l2.sh"


class WarmLinuxCurlContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.warm = WARM.read_text(encoding="utf-8")
        cls.smoke = PREFLIGHT.read_text(encoding="utf-8")
        cls.consumer = HELPER.read_text(encoding="utf-8")
        cls.linux = cls.warm.split("\n  linux-cache-contract:\n", 1)[1].split(
            "\n  linux-arm64-sdk-deps:\n", 1)[0]

    def test_production_read_job_is_curl_only_and_source_abi_pinned(self):
        self.assertIn("uses: ./.github/actions/setup-vcpkg-curl-cache", self.linux)
        self.assertNotIn("uses: ./.github/actions/setup-vcpkg-cache", self.linux)
        for required in ("manifest-root: .", "triplet: x64-linux",
                         "host-triplet: x64-linux", "mode: read"):
            self.assertIn(required, self.linux)
        self.assertIn("scripts/ci/verify-native-linux-l2.sh", self.linux)
        self.assertIn("needs: linux", self.linux)
        self.assertIn("packages: read", self.linux)
        self.assertNotIn("packages: write", self.linux)

    def test_single_consumer_helper_never_destroys_downloaded_l1(self):
        self.assertIn("--only-binarycaching", self.consumer)
        self.assertIn("clear;files,$VCPKG_BINARY_CACHE,readwrite", self.consumer)
        self.assertIn("include/simde/x86/sse2.h", self.consumer)
        self.assertIn("include/gmssl/tls.h", self.consumer)
        self.assertNotIn('rm -rf "$VCPKG_BINARY_CACHE"', self.consumer)
        self.assertNotIn("dotnet restore", self.consumer)
        self.assertNotIn("nugetconfig", self.consumer)
        self.assertNotIn("--no-binarycaching", self.consumer)

    def test_pull_request_qualification_is_always_read_only(self):
        self.assertIn("pull_request:", self.smoke)
        self.assertIn("packages: read", self.smoke)
        self.assertNotIn("packages: write", self.smoke)
        self.assertNotIn("setup-vcpkg-cache", self.smoke)
        self.assertIn("scripts/ci/verify-native-linux-l2.sh", self.smoke)
        self.assertIn("uses: ./.github/actions/setup-vcpkg-curl-cache", self.smoke)
        self.assertIn("manifest-root: .", self.smoke)
        self.assertIn("mode: read", self.smoke)
        self.assertNotIn("--publish", self.smoke)

    def test_empty_local_cache_precedes_download_for_both_callers(self):
        for name, source in (("production", self.linux), ("PR acceptance", self.smoke)):
            with self.subTest(name=name):
                empty = source.index("VCPKG_BINARY_CACHE=$cache")
                download = source.index("uses: ./.github/actions/setup-vcpkg-curl-cache")
                self.assertLess(empty, download)
                self.assertIn("rm -rf \"$cache\"", source[:download])


if __name__ == "__main__":
    unittest.main()
