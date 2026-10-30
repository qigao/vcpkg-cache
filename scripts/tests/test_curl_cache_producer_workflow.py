"""Static admission contract for the single privileged native cache uploader.

Complements the actual source-built ABI/C11 consumer and package protocol CI.
Requires no PyYAML dependency, network credentials or real package uploads.
"""
from pathlib import Path
import unittest


WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/curl-only-vcpkg-producer.yml"


class CanonicalCurlProducerWorkflowPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = WORKFLOW.read_text(encoding="utf-8")
        header, producer = cls.source.split("\n  native-producer:", 1)
        producer, publisher = producer.split("\n  native-publish:", 1)
        publisher, reader = publisher.split("\n  read-back:", 1)
        cls.header = header
        cls.producer = producer
        cls.publisher = publisher
        cls.reader = reader

    def test_source_build_job_never_receives_package_write_permission(self):
        self.assertIn("permissions:\n  contents: read\n  packages: read", self.header)
        self.assertIn("expected_master_sha:", self.header)
        self.assertIn("default: false", self.header)
        self.assertIn("require_new_upload:", self.header)
        self.assertIn("  pull_request:", self.header)
        self.assertIn("  workflow_dispatch:", self.header)
        self.assertIn("github.event_name == 'workflow_dispatch'", self.producer)
        self.assertIn("VCPKG_BINARY_SOURCES=\"clear;files,$VCPKG_BINARY_CACHE,write\"", self.producer)
        self.assertIn("test \"$EXPECTED_MASTER_SHA\" = \"$GITHUB_SHA\"", self.producer)
        self.assertIn("curl-native-producer/cache", self.producer)
        self.assertIn('probe="$RUNNER_TEMP/native-producer-abi-probe"', self.producer)
        self.assertIn('"--x-install-root=$probe"', self.producer)
        self.assertIn('test ! -e "$probe"', self.producer)
        # Installed state from the previous real source build must not hide
        # packages from the immutable ABI plan.
        self.assertEqual(self.producer.count(
            '"--x-install-root=$RUNNER_TEMP/native-producer-install"'), 1)
        self.assertIn("sha256sum --check --status SHA256SUMS", self.producer)
        self.assertIn("actions/upload-artifact@v4", self.producer)
        self.assertNotIn("packages: write", self.producer)
        self.assertNotIn("environment:", self.producer)
        self.assertNotIn("--publish", self.producer)

    def test_only_protected_job_can_upload_an_immutable_native_package(self):
        self.assertEqual(self.source.count("packages: write"), 1)
        self.assertIn("needs: native-producer", self.publisher)
        self.assertIn("environment: native-cache-publish", self.publisher)
        self.assertIn("secrets.NATIVE_CACHE_PUBLISH_ARM", self.publisher)
        self.assertIn("native-cache-publish-v1", self.publisher)
        self.assertIn("inputs.publish == true", self.publisher)
        self.assertIn("github.ref == 'refs/heads/master'", self.publisher)
        self.assertIn("actions/download-artifact@v4", self.publisher)
        self.assertIn("sha256sum --check --status SHA256SUMS", self.publisher)
        self.assertIn("test \"$EXPECTED_MASTER_SHA\" = \"$(git rev-parse HEAD)\"", self.publisher)
        self.assertIn("git ls-remote --exit-code", self.publisher)
        self.assertIn('test "$remote_master" = "$EXPECTED_MASTER_SHA"', self.publisher)
        self.assertIn("--publish", self.publisher)
        self.assertIn("REQUIRE_NEW_UPLOAD", self.publisher)
        self.assertIn("existing-only verification cannot qualify", self.publisher)

    def test_clean_consumer_starts_only_after_approved_upload(self):
        self.assertIn("needs: native-publish", self.reader)
        self.assertIn("--only-binarycaching", self.reader)
        self.assertIn("packages: read", self.reader)
        self.assertNotIn("packages: write", self.reader)
        self.assertNotIn("setup-vcpkg-cache", self.source)

    def test_single_canonical_transport_and_no_old_native_provider(self):
        self.assertIn("scripts/publish-vcpkg-curl-cache.py", self.source)
        self.assertNotIn("scripts/publish-vcpkg-curl.py", self.source)
        for forbidden in ("mono-complete", "brew install mono", "dotnet restore",
                          "vcpkg fetch nuget", "nugetconfig", "nuget push"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.source)


class CoreArm64ReadOnlyWorkflowPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = WORKFLOW.with_name("core-arm64-cache-source-proof.yml")
        cls.source = path.read_text(encoding="utf-8")
        cls.producer, cls.reader = cls.source.split("\n  fresh-read-back:", 1)

    def test_proof_cannot_extend_the_privileged_publisher(self):
        self.assertIn("permissions:\n  contents: read\n  packages: read", self.source)
        for forbidden in ("packages: write", "--publish", "native-cache-publish",
                          "continue-on-error", "setup-vcpkg-cache", "nuget push"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.source)
        self.assertIn("inputs.expected_source_sha", self.producer)
        self.assertIn('test "$REQUESTED_SHA" = "$PROOF_SOURCE_SHA"', self.producer)

    def test_independent_reader_never_downloads_source_cache(self):
        self.assertIn("needs: source-proof", self.reader)
        self.assertIn("runs-on: ubuntu-24.04-arm", self.reader)
        self.assertIn("--only-binarycaching", self.reader)
        self.assertIn('VCPKG_BINARY_SOURCES="clear;files,$VCPKG_BINARY_CACHE,read"', self.reader)
        self.assertIn("core-arm64-source-contract-", self.reader)
        self.assertNotIn("core-arm64-source-diagnostics-", self.reader)
        self.assertIn("github-packages.py cache", self.reader)
        self.assertIn("--compare", self.reader)
        self.assertIn('"--x-install-root=$proof/abi-probe"', self.reader)

    def test_native_source_graph_uses_fresh_roots_and_consumer_infrastructure(self):
        self.assertIn('VCPKG_BINARY_SOURCES="clear;files,$VCPKG_BINARY_CACHE,write"', self.producer)
        for root in ("source-install", "abi-before", "abi-cached-tools", "abi-after"):
            with self.subTest(root=root):
                self.assertIn(f'test ! -e "$proof/{root}"', self.producer)
                self.assertIn(f'"--x-install-root=$proof/{root}"', self.producer)
        for section in (self.producer, self.reader):
            self.assertIn("ref: 1d8efe881a7ddb65f2ecc512530ef15a9814b034", section)
            self.assertIn("--version 4.6.5", section)
            self.assertIn("--sha256 dfdcf77dfd36e60500532a3fcc8a1bd32dc2232edeb63e053267a712bc4489ed", section)
            self.assertIn("--triplet=arm64-linux --host-triplet=arm64-linux", section)
            for feature in ("simd", "usb", "playback", "capture", "zstd"):
                self.assertIn("--x-feature=" + feature, section)

    def test_all_installs_use_effective_environment_and_recheck_cached_tools(self):
        for section, invocations in ((self.producer, 4), (self.reader, 3)):
            with self.subTest(invocations=invocations):
                self.assertNotIn('"$VCPKG_ROOT/vcpkg"', section)
                self.assertEqual(section.count("core-arm64-cache-source-proof.py vcpkg-install --"), invocations)
                self.assertIn('test ! -e "$proof/abi-cached-tools"', section)
                self.assertIn('"--x-install-root=$proof/abi-cached-tools"', section)
                self.assertIn('--dry-run "--x-write-nuget-packages-config=$proof/cached-tools.config"', section)
                self.assertIn('core-arm64-cache-source-proof.py plan --plan "$proof/cached-tools.config"', section)
                cached_check = section.index('plan --plan "$proof/cached-tools.config"')
                actual_install = section.index('"--x-install-root=$proof/' + (
                    "source-install" if invocations == 4 else "installed") + '"')
                self.assertLess(cached_check, actual_install)

    def test_re2c_repair_alone_does_not_trigger_intentional_cache_readback(self):
        filters = self.source.split("  pull_request:\n", 1)[1].split("  workflow_dispatch:", 1)[0]
        for unrelated in ("scripts/github-packages.py", "re2c-tools-package", "ports/**", "scripts/**"):
            with self.subTest(path=unrelated):
                self.assertNotIn(unrelated, filters)
        self.assertIn("scripts/ci/core-arm64-cache-source-proof.py", filters)
        self.assertIn("cache-contracts/salts-core-arm64/**", filters)


if __name__ == "__main__":
    unittest.main()
