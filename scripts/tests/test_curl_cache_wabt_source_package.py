"""Offline canonical native WABT publisher tests; no GitHub Packages writes."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/ci/qualify-wabt-source-package.py"
WORKFLOW = ROOT / ".github/workflows/curl-wabt-source-package-qualification.yml"
SPEC = importlib.util.spec_from_file_location("wabt_source_candidate", HELPER)
assert SPEC and SPEC.loader
wabt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wabt)

ABI = "a" * 64
NAME = "wabt_x64-linux"
VERSION = "1.0.42-vcpkg" + ABI


def exact_plan(path: Path, nodes: list[tuple[str, str]]) -> Path:
    root = ET.Element("packages")
    for identity, version in nodes:
        ET.SubElement(root, "package", id=identity, version=version)
    ET.ElementTree(root).write(path, encoding="utf-8")
    return path


def source_cache(root: Path) -> Path:
    cache = root / "files"
    archive = cache / ABI[:2] / (ABI + ".zip")
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as result:
        result.writestr(
            "CONTROL",
            f"Package: wabt\nArchitecture: x64-linux\nVersion: 1.0.42\nAbi: {ABI}\n",
        )
        result.writestr("BUILD_INFO", "CRTLinkage: dynamic\n")
        result.writestr("tools/wabt/wast2json", b"native source-built executable bytes")
    return cache


class NativeWabtExactSourceCandidate(unittest.TestCase):
    def setup_source(self, root: Path):
        tool = root / "installed/x64-linux/tools/wabt/wast2json"
        tool.parent.mkdir(parents=True, exist_ok=True)
        tool.write_text("native test fixture")
        tool.chmod(0o755)
        return tool

    def test_real_canonical_nupkg_roundtrip_never_writes_registry(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            plan = exact_plan(root / "packages.config", [(NAME, VERSION)])
            cache = source_cache(root)
            tool = self.setup_source(root)
            output = root / "qualified"
            rows = wabt.qualify(plan, cache, output,
                                expected_wabt_abi=ABI, installed_tool=tool)
            self.assertEqual(rows, [(NAME, VERSION, ABI)])
            self.assertEqual(
                list(output.glob("*.nupkg")),
                [output / f"{NAME}.{VERSION}.nupkg"],
            )
            with self.assertRaisesRegex(ValueError, "start empty"):
                wabt.qualify(plan, cache, output,
                             expected_wabt_abi=ABI, installed_tool=tool)

    def test_wrong_exact_wabt_abi_fails_before_package_is_created(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            plan = exact_plan(root / "packages.config", [(NAME, VERSION)])
            cache = source_cache(root)
            tool = self.setup_source(root)
            output = root / "qualified"
            with self.assertRaisesRegex(ValueError, "WABT ABI mismatch"):
                wabt.qualify(plan, cache, output,
                             expected_wabt_abi="b" * 64, installed_tool=tool)
            self.assertFalse(output.exists())

    def test_bad_plan_duplicate_missing_wabt_or_unsafe_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            cache = source_cache(root)
            tool = self.setup_source(root)
            output = root / "packages"
            cases = [
                ([], "exactly one"),
                ([(NAME, VERSION), (NAME, VERSION)], "duplicate"),
                ([("../bad", VERSION)], "canonical"),
                ([(NAME, "1.0.42")], "canonical"),
                ([("simde_x64-linux", "1.0.1-vcpkg" + ABI)], "exactly one"),
            ]
            for entries, error in cases:
                with self.subTest(entries=entries):
                    plan = exact_plan(root / "plan.xml", entries)
                    with self.assertRaisesRegex(ValueError, error):
                        wabt.qualify(plan, cache, output,
                                     expected_wabt_abi=ABI, installed_tool=tool)
                    self.assertFalse(output.exists())

    def test_missing_exact_files_cache_fails_closed_not_source_fallback(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            tool = self.setup_source(root)
            plan = exact_plan(root / "packages.config", [(NAME, VERSION)])
            with self.assertRaisesRegex(ValueError, "missing source-built"):
                wabt.qualify(plan, root / "empty-l1", root / "qualified",
                             expected_wabt_abi=ABI, installed_tool=tool)
            self.assertFalse((root / "qualified").exists())

    def test_nonexecuting_wast2json_never_qualifies_publisher(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            plan = exact_plan(root / "packages.config", [(NAME, VERSION)])
            cache = source_cache(root)
            tool = self.setup_source(root)
            tool.chmod(0o644)
            with self.assertRaisesRegex(ValueError, "executable"):
                wabt.qualify(plan, cache, root / "qualified",
                             expected_wabt_abi=ABI, installed_tool=tool)

    def test_source_producer_ci_has_no_package_write_or_legacy_nuget(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("on:\n  pull_request:", source)
        self.assertIn("packages: read", source)
        self.assertNotIn("packages: write", source)
        self.assertNotIn("--publish", source)
        self.assertNotIn("setup-vcpkg-cache", source)
        self.assertIn("clear;files,$cache,write", source)
        self.assertIn("test ! -e \"$probe\"", source)
        self.assertIn(
            "cbc2c2ae595865ddfbb317e7822e4f81633cb5dae4103085140643d7fb77f946",
            source,
        )
        self.assertIn("remote_publish_attempted=false", source)


if __name__ == "__main__":
    unittest.main()
