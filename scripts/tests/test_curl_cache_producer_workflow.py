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
        self.assertIn("VCPKG_BINARY_SOURCES=\"clear;files,$VCPKG_BINARY_CACHE,write\"", self.producer)
        self.assertIn("test \"$EXPECTED_MASTER_SHA\" = \"$GITHUB_SHA\"", self.producer)
        self.assertIn("curl-native-producer/cache", self.producer)
        self.assertIn("sha256sum --check --status SHA256SUMS", self.producer)
        self.assertIn("actions/upload-artifact@v4", self.producer)
        self.assertNotIn("packages: write", self.producer)
        self.assertNotIn("environment:", self.producer)
        self.assertNotIn("--publish", self.producer)

    def test_only_protected_job_can_upload_an_immutable_native_package(self):
        self.assertEqual(self.source.count("packages: write"), 1)
        self.assertIn("needs: native-producer", self.publisher)
        self.assertIn("environment: native-cache-publish", self.publisher)
        self.assertIn("inputs.publish == true", self.publisher)
        self.assertIn("github.ref == 'refs/heads/master'", self.publisher)
        self.assertIn("actions/download-artifact@v4", self.publisher)
        self.assertIn("sha256sum --check --status SHA256SUMS", self.publisher)
        self.assertIn("test \"$EXPECTED_MASTER_SHA\" = \"$(git rev-parse HEAD)\"", self.publisher)
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


if __name__ == "__main__":
    unittest.main()
