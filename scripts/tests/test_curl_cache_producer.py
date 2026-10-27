"""Offline publisher safety and byte-exact native vcpkg roundtrip tests."""
from __future__ import annotations

import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET
import zipfile

MODULE = Path(__file__).resolve().parents[1] / "publish-vcpkg-curl-cache.py"
SPEC = importlib.util.spec_from_file_location("qigao_curl_publisher", MODULE)
assert SPEC and SPEC.loader
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)
ABI = "a" * 64
PACKAGE = "simde_x64-linux"
VERSION = "1.0.0-vcpkg" + ABI


def binary_package(path: Path, *, package="simde", arch="x64-linux",
                   abi=ABI, info="vcpkg-tool=v1\n", injection=False) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("CONTROL",
            f"Package: {package}\nArchitecture: {arch}\nAbi: {abi}\n")
        archive.writestr("BUILD_INFO", info)
        archive.writestr("include/simde/simde.h", "/* source */\n")
        archive.writestr("bin/qualified-binary", b"\x7fELFtest")
        if injection:
            archive.writestr("../unsafe", "payload")


class StubFeed:
    def __init__(self, packaged=None):
        self.packaged = packaged
        self.requests = []
    def package(self, package_id, version, destination, allow_not_found=False):
        self.requests.append((package_id, version, allow_not_found))
        if self.packaged:
            import shutil
            shutil.copyfile(self.packaged, destination)
            return True
        return False


class CurlCachePublisherTests(unittest.TestCase):
    def test_exact_zip_to_nupkg_and_back_with_executable_payload(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            native = root / (ABI + ".zip")
            output = root / "package.nupkg"
            binary_package(native)
            self.assertEqual(publisher.identify_source(native, PACKAGE, VERSION), ABI)
            publisher.build_nupkg(native, PACKAGE, VERSION, output)
            native_hash = publisher.check_roundtrip(native, output, PACKAGE, VERSION)
            self.assertEqual(native_hash, publisher.entries_digest(native))
            with zipfile.ZipFile(output) as archive:
                self.assertIn("[Content_Types].xml", archive.namelist())
                self.assertIn("_rels/.rels", archive.namelist())
                self.assertIn("BUILD_INFO", archive.namelist())
                self.assertIn("bin/qualified-binary", archive.namelist())
                publisher.packages.package_metadata(archive, PACKAGE, VERSION)

    def test_native_zip_wrong_abi_id_missing_build_info_and_traversal(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            native = root / "pkg.zip"
            binary_package(native)
            for identity, version in (
                ("something_x64-linux", VERSION),
                (PACKAGE, "1.0.0"),
                (PACKAGE, "1.0.0-vcpkg" + "b" * 64),
                ("../unsafe", VERSION),
            ):
                with self.subTest(identity=identity, version=version):
                    with self.assertRaises(ValueError):
                        publisher.identify_source(native, identity, version)
            binary_package(native, abi="b" * 64)
            with self.assertRaisesRegex(ValueError, "CONTROL ABI"):
                publisher.identify_source(native, PACKAGE, VERSION)
            binary_package(native, info="")
            with self.assertRaisesRegex(ValueError, "BUILD_INFO"):
                publisher.identify_source(native, PACKAGE, VERSION)
            binary_package(native, injection=True)
            with self.assertRaisesRegex(ValueError, "unsafe"):
                publisher.identify_source(native, PACKAGE, VERSION)

    def test_dry_run_requests_no_upload_and_stable_existing_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            native = root / (ABI + ".zip")
            binary_package(native)
            existing = root / "existing.nupkg"
            publisher.build_nupkg(native, PACKAGE, VERSION, existing)
            feed = StubFeed()
            with mock.patch.object(publisher, "upload") as upload:
                self.assertEqual(publisher.publish(feed, PACKAGE, VERSION, native, False),
                                 "dry-run")
                upload.assert_not_called()
            self.assertEqual(feed.requests, [(PACKAGE, VERSION, True)])
            feed = StubFeed(existing)
            with mock.patch.object(publisher, "upload") as upload:
                self.assertEqual(publisher.publish(feed, PACKAGE, VERSION, native, True),
                                 "verified-existing")
                upload.assert_not_called()
            # Same ID/version but different binary contents must never "skip".
            different = root / "different.zip"
            binary_package(different, info="source=other immutable revision\n")
            # The different archive remains structurally valid and passes its
            # independent NuGet roundtrip before comparing the fixed version.
            alternative = root / "alternative.nupkg"
            publisher.build_nupkg(different, PACKAGE, VERSION, alternative)
            publisher.check_roundtrip(different, alternative, PACKAGE, VERSION)
            with self.assertRaisesRegex(ValueError, "DIFFERENT"):
                publisher.publish(StubFeed(existing), PACKAGE, VERSION, different, False)

    def test_publisher_endpoint_whitelist(self):
        class Client:
            def __init__(self, uri):
                self.uri = uri
            def json(self, ignored):
                return {"resources": [{"@id": self.uri, "@type": "PackagePublish/2.0.0"}]}
        for endpoint in (
            "https://evil.example/qigao/api/v2/package",
            "https://nuget.pkg.github.com/attacker/api/v2/package",
            "http://nuget.pkg.github.com/qigao/api/v2/package",
            "https://nuget.pkg.github.com/qigao@evil.example/api/v2/package",
        ):
            with self.subTest(endpoint=endpoint):
                with self.assertRaises(ValueError):
                    publisher.resource(type("Stub", (), {"client": Client(endpoint)})())
        good = "https://nuget.pkg.github.com/qigao/api/v2/package"
        self.assertEqual(publisher.resource(type("Stub", (), {"client": Client(good)})()), good)

    def test_curl_multipart_credentials_only_on_stdin(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "approved.nupkg"
            source.write_bytes(b"safe fixture")
            class Client:
                token = "not-a-real-token"
            def fake_run(cmd, **kwargs):
                self.assertIn("--form", cmd)
                self.assertEqual(cmd[cmd.index("--request") + 1], "PUT")
                self.assertFalse(any("not-a-real-token" in value for value in cmd))
                self.assertIn("not-a-real-token", kwargs["input"])
                return type("Status", (), {"stdout": "201", "stderr": "", "returncode": 0})()
            with mock.patch.object(publisher.subprocess, "run", side_effect=fake_run):
                publisher.upload(Client(), "https://nuget.pkg.github.com/qigao/api/v2/package", source)

    def test_zero_publisher_plan_is_rejected_and_duplicate_ids_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            native = root / ABI[:2] / f"{ABI}.zip"
            native.parent.mkdir()
            binary_package(native)
            manifest = root / "packages.config"
            config = ET.Element("packages")
            ET.SubElement(config, "package", id=PACKAGE, version=VERSION)
            ET.SubElement(config, "package", id=PACKAGE, version=VERSION)
            ET.ElementTree(config).write(manifest)
            # Admission must reject duplicates before any network client is
            # created; no mocking of archive_members or CONTROL is permitted.
            with mock.patch("sys.argv", [
                "publish", "--packages-config", str(manifest), "--cache", str(root)
            ]):
                with self.assertRaisesRegex(ValueError, "duplicate"):
                    publisher.main()


if __name__ == "__main__":
    unittest.main()
