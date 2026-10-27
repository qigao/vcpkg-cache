"""Offline policy tests: no package network fetch or compiler is required."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET


MODULE = Path(__file__).resolve().parents[1] / "restore-manifest-cache.py"
SPEC = importlib.util.spec_from_file_location("curl_vcpkg_restore", MODULE)
assert SPEC and SPEC.loader
restore = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(restore)
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


if __name__ == "__main__":
    unittest.main()
