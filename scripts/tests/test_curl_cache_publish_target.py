"""Offline validation of manually requested exact native NuGet publication."""
from pathlib import Path
import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/ci/verify-native-publish-target.py"
SPEC = importlib.util.spec_from_file_location("exact_native_publish_target", SOURCE)
assert SPEC and SPEC.loader
contract = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(contract)

ABI = "a" * 64
VERSION = "1.0.42-vcpkg" + ABI


def plan(path, pairs):
    root = ET.Element("packages")
    for name, version in pairs:
        ET.SubElement(root, "package", id=name, version=version)
    ET.ElementTree(root).write(path, encoding="utf-8")
    return path


class ManualNativePublisherTargetTests(unittest.TestCase):
    def verify(self, file, expected_version=VERSION,
               package_set="wabt", expected_id="wabt_x64-linux"):
        return contract.verify(
            file, package_set=package_set,
            expected_id=expected_id, expected_version=expected_version,
        )

    def test_canonical_target_and_exact_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            file = plan(Path(directory) / "config", [
                ("vcpkg-cmake_x64-linux", "2024.4.23-vcpkg" + "b" * 64),
                ("wabt_x64-linux", VERSION),
            ])
            self.assertEqual(self.verify(file)[-1], ("wabt_x64-linux", VERSION))

    def test_missing_or_different_native_hash_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            file = plan(Path(directory) / "config", [("wabt_x64-linux", VERSION)])
            for bad in ("", "1.0.42", "1.0.42-vcpkg" + "b" * 63):
                with self.subTest(version=bad):
                    with self.assertRaisesRegex(ValueError, "full immutable"):
                        self.verify(file, expected_version=bad)
            with self.assertRaisesRegex(ValueError, "target mismatch"):
                self.verify(file, expected_version="1.0.42-vcpkg" + "b" * 64)

    def test_only_selected_id_is_authorized(self):
        with tempfile.TemporaryDirectory() as directory:
            file = plan(Path(directory) / "config", [("wabt_x64-linux", VERSION)])
            with self.assertRaisesRegex(ValueError, "does not match"):
                self.verify(file, expected_id="simde_x64-linux")
            with self.assertRaisesRegex(ValueError, "does not match"):
                self.verify(file, package_set="simde")
            with self.assertRaisesRegex(ValueError, "unapproved"):
                self.verify(file, package_set="other")

    def test_duplicate_missing_or_unsafe_plan_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "config"
            cases = [
                ([], "empty"),
                ([("simde_x64-linux", VERSION)], "target mismatch"),
                ([("wabt_x64-linux", VERSION), ("wabt_x64-linux", VERSION)], "duplicate"),
                ([("wabt_x64-linux", VERSION), ("WABT_x64-linux", VERSION)], "duplicate"),
                ([("../unsafe", VERSION)], "floating"),
            ]
            for entries, message in cases:
                with self.subTest(entries=entries):
                    plan(file, entries)
                    with self.assertRaisesRegex(ValueError, message):
                        self.verify(file)

    def test_unbounded_xml_and_wrong_root_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "config"
            file.write_text("<untrusted/>")
            with self.assertRaisesRegex(ValueError, "canonical"):
                self.verify(file)
            plan(file, [("wabt_x64-linux", VERSION)])
            with mock.patch.object(contract, "MAX_PLAN_SIZE", 1):
                with self.assertRaisesRegex(ValueError, "unbounded"):
                    self.verify(file)

    def test_protected_stage_rechecks_sha_attested_package_plan(self):
        src = (ROOT / ".github/workflows/curl-only-vcpkg-producer.yml").read_text()
        producer, publisher = src.split("\n  native-publish:", 1)
        self.assertIn("expected_native_id:", producer)
        self.assertIn("expected_native_version:", producer)
        self.assertIn("DO_PUBLISH:", producer)
        self.assertIn("scripts/ci/verify-native-publish-target.py", producer)
        self.assertIn("sha256sum packages.config source-proof.txt", producer)
        self.assertIn("scripts/ci/verify-native-publish-target.py", publisher)
        self.assertIn("sha256sum --check --status SHA256SUMS", publisher)
        self.assertIn("environment: native-cache-publish", publisher)
        self.assertEqual(src.count("packages: write"), 1)


if __name__ == "__main__":
    unittest.main()
