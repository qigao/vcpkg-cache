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

    def test_tre_manual_dry_run_is_one_pinned_branch_without_upload_rights(self):
        self.assertIn("inputs.publish == false", self.producer)
        self.assertIn("inputs.package_set == 'tre'", self.producer)
        self.assertIn("refs/heads/codex/tre-ios-sdk-cache-warm", self.producer)
        self.assertIn('test "$PUBLISH_REQUESTED" = "false"', self.producer)
        self.assertIn('test "$PACKAGE_SET" = tre', self.producer)
        self.assertIn('test "$EXPECTED_MASTER_SHA" = "$GITHUB_SHA"', self.producer)
        self.assertNotIn("packages: write", self.producer)
        self.assertNotIn("environment:", self.producer)
        self.assertNotIn("--publish", self.producer)
        # Actual publication remains master-only and requires protected review.
        self.assertIn("github.ref == 'refs/heads/master'", self.publisher)
        self.assertIn("environment: native-cache-publish", self.publisher)
        self.assertIn("secrets.NATIVE_CACHE_PUBLISH_ARM", self.publisher)

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
        self.assertIn("--approved-id", self.publisher)
        self.assertIn("--approved-version", self.publisher)
        self.assertIn("REQUIRE_NEW_UPLOAD", self.publisher)
        self.assertIn("existing-only verification cannot qualify", self.publisher)

    def test_clean_consumer_starts_only_after_approved_upload(self):
        self.assertIn("needs: native-publish", self.reader)
        self.assertIn("--only-binarycaching", self.reader)
        self.assertIn("packages: read", self.reader)
        self.assertNotIn("packages: write", self.reader)
        self.assertNotIn("setup-vcpkg-cache", self.source)

    def test_tre_is_explicit_master_gated_and_has_fresh_binary_read_back(self):
        self.assertIn("options: [simde, wabt, tre]", self.header)
        self.assertIn('tre) manifest="$GITHUB_WORKSPACE/cache-contracts/tre-producer" ;;',
                      self.producer)
        self.assertIn("github.ref == 'refs/heads/master'", self.producer)
        self.assertIn("native-cache-publish", self.publisher)
        self.assertIn("needs: native-publish", self.reader)
        self.assertIn('tre:x64-linux@0.9.0#1', self.reader)
        self.assertIn("x64-linux/include/tre/tre.h", self.reader)
        self.assertIn("x64-linux/lib/libtre.a", self.reader)
        self.assertIn("x64-linux/share/unofficial-tre/unofficial-tre-config.cmake",
                      self.reader)
        self.assertIn("cache-contracts/tre-producer", self.source)
        self.assertTrue((WORKFLOW.parents[2] / "cache-contracts/tre-producer/vcpkg.json").is_file())

    def test_fresh_reader_rechecks_operator_approved_abi_not_only_version(self):
        self.assertIn("needs: native-publish", self.reader)
        self.assertIn("qigao-curl-vcpkg-abi/packages.config", self.reader)
        self.assertIn("scripts/ci/verify-native-publish-target.py", self.reader)
        self.assertIn('--expected-id "$EXPECTED_NATIVE_ID"', self.reader)
        self.assertIn('--expected-version "$EXPECTED_NATIVE_VERSION"', self.reader)
        self.assertIn("test -s \"$plan\"", self.reader)
        self.assertIn("--only-binarycaching", self.reader)
        self.assertNotIn("packages: write", self.reader)

    def test_single_canonical_transport_and_no_old_native_provider(self):
        self.assertIn("scripts/publish-vcpkg-curl-cache.py", self.source)
        self.assertNotIn("scripts/publish-vcpkg-curl.py", self.source)
        for forbidden in ("mono-complete", "brew install mono", "dotnet restore",
                          "vcpkg fetch nuget", "nugetconfig", "nuget push"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.source)


if __name__ == "__main__":
    unittest.main()
