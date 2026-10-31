"""Offline policy tests: no package network fetch or compiler is required."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET


MODULE = Path(__file__).resolve().parents[1] / "restore-manifest-cache.py"
SPEC = importlib.util.spec_from_file_location("curl_vcpkg_restore", MODULE)
assert SPEC and SPEC.loader
restore = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(restore)
GITHUB_MODULE = Path(__file__).resolve().parents[1] / "github-packages.py"
GITHUB_SPEC = importlib.util.spec_from_file_location("curl_exact_github_packages", GITHUB_MODULE)
assert GITHUB_SPEC and GITHUB_SPEC.loader
github_packages = importlib.util.module_from_spec(GITHUB_SPEC)
GITHUB_SPEC.loader.exec_module(github_packages)
ABI = "a" * 64


class CurlCacheContract(unittest.TestCase):
    def write_config(self, folder: str, package_id: str, version: str):
        path = Path(folder) / "packages.config"
        root = ET.Element("packages")
        ET.SubElement(root, "package", id=package_id, version=version)
        ET.ElementTree(root).write(path, encoding="utf-8")
        return path

    def test_canonical_unprefixed_identity(self):
        with tempfile.TemporaryDirectory() as work:
            file = self.write_config(work, "simde_x64-linux", "0.0.0-vcpkg" + ABI)
            self.assertEqual(restore.validate(file), 1)

    def test_configured_prefix_exact_underscore(self):
        old = os.environ.get("X_VCPKG_NUGET_ID_PREFIX")
        try:
            os.environ["X_VCPKG_NUGET_ID_PREFIX"] = "vcpkg-cache"
            with tempfile.TemporaryDirectory() as work:
                file = self.write_config(work, "vcpkg-cachesimde_x64-linux",
                                         "0.0.0-vcpkg" + ABI)
                self.assertEqual(restore.validate(file), 1)
                root = ET.parse(file).getroot()
                self.assertEqual(root[0].attrib["id"], "vcpkg-cache_simde_x64-linux")
                bad = self.write_config(work, "untrusted_x64-linux", "0.0.0-vcpkg" + ABI)
                with self.assertRaises(ValueError):
                    restore.validate(bad)
        finally:
            if old is None:
                os.environ.pop("X_VCPKG_NUGET_ID_PREFIX", None)
            else:
                os.environ["X_VCPKG_NUGET_ID_PREFIX"] = old

    def test_no_floating_or_malformed_abi(self):
        with tempfile.TemporaryDirectory() as work:
            for version in ("1.0.0", "1.0.0-rc.1",
                            "0.0.0-vcpkg" + "a" * 63,
                            "0.0.0-vcpkg" + "g" * 64):
                file = self.write_config(work, "simde_x64-linux", version)
                with self.assertRaises(ValueError):
                    restore.validate(file)

    def test_no_traversal_or_untrusted_package_name(self):
        with tempfile.TemporaryDirectory() as work:
            file = self.write_config(work, "../evil", "0.0.0-vcpkg" + ABI)
            with self.assertRaises(ValueError):
                restore.validate(file)


class ExactArchive404Classification(unittest.TestCase):
    """No network, tokens, producers or fallback paths: same-feed diagnostics."""

    class Feed:
        def __init__(self, advertised=(), inaccessible=False):
            self.advertised = advertised
            self.inaccessible = inaccessible
            self.calls = []

        def package(self, identity, version, destination, allow_not_found=False):
            self.calls.append(("archive", identity, version, allow_not_found))
            return False  # Exactly one real HTTP 404, no other transport.

        def versions(self, identity):
            self.calls.append(("metadata", identity))
            if self.inaccessible:
                raise ValueError("simulated inaccessible V3 package index")
            return list(self.advertised)

    def test_advertised_version_but_archive_404_is_not_called_unpublished(self):
        feed = self.Feed(["0.0.0-vcpkg" + ABI])
        with self.assertRaisesRegex(ValueError, "advertises this precise version"):
            github_packages.reject_missing_exact_archive(
                feed, "simde_x64-linux", "0.0.0-vcpkg" + ABI)
        self.assertEqual(feed.calls, [("metadata", "simde_x64-linux")])

    def test_absent_version_does_not_assert_package_deletion(self):
        feed = self.Feed(["0.0.0-vcpkg" + "b" * 64])
        with self.assertRaisesRegex(ValueError, "does not distinguish removal from denied access"):
            github_packages.reject_missing_exact_archive(
                feed, "simde_x64-linux", "0.0.0-vcpkg" + ABI)

    def test_inaccessible_package_index_preserves_underlying_error(self):
        feed = self.Feed(inaccessible=True)
        with self.assertRaisesRegex(ValueError, "same credential also could not read") as reported:
            github_packages.reject_missing_exact_archive(
                feed, "simde_x64-linux", "0.0.0-vcpkg" + ABI)
        self.assertIsInstance(reported.exception.__cause__, ValueError)
        self.assertEqual(feed.calls, [("metadata", "simde_x64-linux")])

    def test_restore_stops_on_first_404_not_all_15(self):
        feed = self.Feed(inaccessible=True)
        with tempfile.TemporaryDirectory() as work:
            config = Path(work) / "packages.config"
            root = ET.Element("packages")
            for identity in ("first_x64-windows", "second_x64-windows"):
                ET.SubElement(root, "package", id=identity,
                              version="0.0.0-vcpkg" + ABI)
            ET.ElementTree(root).write(config, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "exact NuGet archive returned HTTP 404"):
                github_packages.restore_cache(feed, config, Path(work) / "cache")
        self.assertEqual(feed.calls, [
            ("archive", "first_x64-windows", "0.0.0-vcpkg" + ABI, True),
            ("metadata", "first_x64-windows"),
        ])


    def test_successful_exact_archives_restore_without_metadata_lookup(self):
        """Normal cache hits must remain read-only, exact-ABI and metadata-free."""

        class PresentFeed(self.Feed):
            def package(self, identity, version, destination, allow_not_found=False):
                self.calls.append(("archive", identity, version, allow_not_found))
                name, architecture = identity.split("_", 1)
                abi = version.split("-vcpkg", 1)[1]
                with zipfile.ZipFile(destination, "w") as archive:
                    archive.writestr(
                        f"{name}.nuspec",
                        f"<package><metadata><id>{identity}</id>"
                        f"<version>{version}</version></metadata></package>")
                    archive.writestr(
                        "CONTROL",
                        f"Package: {name}\nArchitecture: {architecture}\nAbi: {abi}\n")
                    archive.writestr("BUILD_INFO", "test: synthetic native package\n")
                    archive.writestr(f"include/{name}.h", name)
                return True

        feed = PresentFeed(inaccessible=True)
        packages = [
            ("simde_x64-windows", "a" * 64),
            ("fmt_x64-windows", "b" * 64),
        ]
        with tempfile.TemporaryDirectory() as work:
            config = Path(work) / "packages.config"
            cache = Path(work) / "cache"
            root = ET.Element("packages")
            for identity, abi in packages:
                ET.SubElement(root, "package", id=identity,
                              version="0.0.0-vcpkg" + abi)
            ET.ElementTree(root).write(config, encoding="utf-8")
            self.assertEqual(github_packages.restore_cache(feed, config, cache), (2, 0))
            for identity, abi in packages:
                archive_path = cache / abi[:2] / f"{abi}.zip"
                self.assertTrue(archive_path.is_file())
                with zipfile.ZipFile(archive_path) as restored:
                    self.assertEqual(
                        restored.read(f"include/{identity.split('_', 1)[0]}.h"),
                        identity.split("_", 1)[0].encode())
                    self.assertIn("CONTROL", restored.namelist())
                    self.assertIn("BUILD_INFO", restored.namelist())
                    self.assertFalse(any(name.endswith(".nuspec")
                                         for name in restored.namelist()))
        self.assertEqual(feed.calls, [
            ("archive", identity, "0.0.0-vcpkg" + abi, True)
            for identity, abi in packages
        ])

    def test_non_404_download_error_does_not_query_metadata(self):
        """Only an actual archive 404 can trigger the diagnostic version probe."""

        class TransportErrorFeed(self.Feed):
            def package(self, identity, version, destination, allow_not_found=False):
                self.calls.append(("archive", identity, version, allow_not_found))
                raise OSError("simulated HTTP 403")

        feed = TransportErrorFeed(inaccessible=True)
        with tempfile.TemporaryDirectory() as work:
            config = Path(work) / "packages.config"
            root = ET.Element("packages")
            ET.SubElement(root, "package", id="simde_x64-windows",
                          version="0.0.0-vcpkg" + ABI)
            ET.ElementTree(root).write(config, encoding="utf-8")
            with self.assertRaisesRegex(OSError, "simulated HTTP 403"):
                github_packages.restore_cache(feed, config, Path(work) / "cache")
        self.assertEqual(feed.calls, [
            ("archive", "simde_x64-windows", "0.0.0-vcpkg" + ABI, True),
        ])


if __name__ == "__main__":
    unittest.main()
