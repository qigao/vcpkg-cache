"""Fail-closed SaltsCore exact x64-windows v145-era native ABI producer tests."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from xml.etree import ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ci/verify-saltscore-win2025-abi.py"
SPEC = importlib.util.spec_from_file_location("saltscore_cache_abi", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


def plan(path: Path, pairs: list[tuple[str, str]]) -> None:
    e = ET.Element("packages")
    for name, version in pairs:
        ET.SubElement(e, "package", id=name, version=version)
    ET.ElementTree(e).write(path, encoding="utf-8", xml_declaration=True)


def native_zip(root: Path, name: str, version: str, *, wrong_abi=False) -> Path:
    abi = module.NATIVE_VERSION.fullmatch(version).group(1)
    target = root / abi[:2] / f"{abi}.zip"
    target.parent.mkdir(parents=True, exist_ok=True)
    port, triplet = name.rsplit("_", 1)
    with ZipFile(target, "w", compression=ZIP_DEFLATED) as z:
        z.writestr("CONTROL", f"Package: {port}\nArchitecture: {triplet}\n"
                              f"Abi: {'0' * 64 if wrong_abi else abi}\n")
        z.writestr("BUILD_INFO", "Compiler: MSVC\n")
        z.writestr("include/example.h", "int compiled_native_module;\n")
    return target


class ExactNativeWindowsABI(unittest.TestCase):
    def setUp(self):
        self.expected = module.contract()
        self.pairs = [(p["id"], p["version"]) for p in self.expected["packages"]]

    def test_fixture_is_frozen_with_all_nine_unique_abis(self):
        self.assertEqual(len(self.pairs), 9)
        self.assertEqual(module.blob_sha(
            module.FIXTURE.read_bytes().replace(b"\r\n", b"\n")),
            module.FROZEN_FIXTURE_BLOB)
        self.assertEqual(self.expected["target"]["runner"], "windows-2025")
        self.assertEqual(self.expected["target"]["triplet"], "x64-windows")
        self.assertEqual(self.expected["source"]["feature"], "cnet")

    def test_exact_native_plan_accepted_without_reordering_assumption(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "packages.config"
            plan(p, list(reversed(self.pairs)))
            self.assertEqual(module.validate_plan(p, self.expected), sorted(self.pairs))

    def test_plan_cannot_omit_duplicate_or_change_a_single_abi(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "packages.config"
            variants = [
                self.pairs[1:],
                self.pairs + [self.pairs[0]],
                self.pairs[:-1] + [self.pairs[0]],
                [(self.pairs[0][0], self.pairs[0][1][:-1] + "0")] + self.pairs[1:],
                [("gmssl_qigao-x64-windows-v145", self.pairs[0][1])] + self.pairs[1:],
            ]
            for items in variants:
                plan(p, items)
                with self.subTest(first=items[0][0], count=len(items)):
                    with self.assertRaises(ValueError):
                        module.validate_plan(p, self.expected)

    def test_native_cache_and_artifact_roundtrip_exact_byte_proof(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage = Path(tmp)
            plan(stage / "packages.config", self.pairs)
            for name, version in self.pairs:
                native_zip(stage / "cache", name, version)
            master = "f" * 40
            module.attest(stage, master)
            module.verify(stage, master)
            with self.assertRaisesRegex(ValueError, "provenance"):
                module.verify(stage, "a" * 40)
            archive = next((stage / "cache").rglob("*.zip"))
            archive.write_bytes(archive.read_bytes() + b"altered")
            with self.assertRaisesRegex(ValueError, "provenance"):
                module.verify(stage, master)

    def test_extra_archive_and_fake_control_abi_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            stage = Path(tmp)
            plan(stage / "packages.config", self.pairs)
            for name, version in self.pairs:
                native_zip(stage / "cache", name, version)
            extras = stage / "cache/f0/bad.zip"
            extras.parent.mkdir(exist_ok=True)
            extras.write_bytes(b"not a vcpkg native cache")
            with self.assertRaisesRegex(ValueError, "extra"):
                module.exact_archives(stage / "cache", sorted(self.pairs))
            extras.unlink()
            bad = native_zip(stage / "cache", *self.pairs[0], wrong_abi=True)
            with self.assertRaisesRegex(ValueError, "CONTROL"):
                module.read_native_zip(bad, *self.pairs[0])

    def test_missing_source_and_untrusted_source_root_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "source checkout missing"):
                module.verify_product_source(Path(tmp), self.expected)
            with self.assertRaises(ValueError):
                module.validate_plan(Path(tmp) / "missing", self.expected)


if __name__ == "__main__":
    unittest.main()
