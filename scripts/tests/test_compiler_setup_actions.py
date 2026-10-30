#!/usr/bin/env python3
"""Offline unit tests for independent reusable compiler composite actions.

Real upstream downloads and native execution are separately gated by the CI
workflow that calls each action on its intended host.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import struct
import tarfile
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/setup-compiler-toolchain.py"
SPEC = importlib.util.spec_from_file_location("compiler_setup", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class FakeResponse(io.BytesIO):
    def __init__(self, value: bytes, url: str):
        super().__init__(value)
        self.url = url

    def geturl(self) -> str:
        return self.url


class CompilerActionTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.temp = Path(self.tempdir.name)
        self.contract = json.loads(
            (ROOT / "compiler-contracts/release-obfuscation.json").read_text(encoding="utf-8")
        )
        self.contract_path = self.temp / "contract.json"

    def save(self):
        self.contract_path.write_text(json.dumps(self.contract), encoding="utf-8")

    def args(self, compiler="tinycc-builder", target="x64", build_type="toolchain-only",
             os="Windows", arch="X64"):
        self.save()
        return argparse.Namespace(
            compiler=compiler, target=target, build_type=build_type,
            runner_os=os, runner_arch=arch, version="",
            destination=self.temp / "install", contract=self.contract_path,
            verify_smoke=True, github_output=None, github_path=None,
            github_env=None,
        )

    def tinycc_fixture(self):
        archive = self.temp / "tinycc-windows-2026-10-29.zip"
        with zipfile.ZipFile(archive, "w") as zipfile_out:
            for name in ("tcc.exe", "i386-win32-tcc.exe", "arm64-win32-tcc.exe",
                         "libtcc.dll"):
                zipfile_out.writestr(f"kit/{name}", b"fixture compiler")
        header = self.temp / "obfus.h"
        header.write_bytes(b"/* pinned header fixture */\n")
        return archive, header

    def llvm_fixture(self):
        archive = self.temp / "llvm-mingw.tar.xz"
        with tarfile.open(archive, "w:xz") as output:
            contents = {
                "kit/bin/x86_64-w64-mingw32-clang": b"fake clang",
                "kit/bin/x86_64-w64-mingw32-clang++": b"fake clang++",
                "kit/bin/x86_64-w64-mingw32-ar": b"fake ar",
            }
            for name, data in contents.items():
                info = tarfile.TarInfo(name=name)
                info.size, info.mode = len(data), 0o755
                output.addfile(info, io.BytesIO(data))
            alias = tarfile.TarInfo("kit/bin/clang")
            alias.type = tarfile.SYMTYPE
            alias.linkname = "x86_64-w64-mingw32-clang"
            output.addfile(alias)
        return archive

    def test_canonical_locks_include_real_header_sha(self):
        h = self.contract["sources"]["obfus-h"]
        self.assertEqual(h["sha256"],
                         "fcb3a591f95413ea1fe41d11f0fe1ccf0927b492e42697680c3b058c09c199da")
        self.assertEqual(len(h["source_commit"]), 40)

    def test_tinycc_installer_produces_relocated_cmake_and_pinned_header(self):
        archive, header = self.tinycc_fixture()

        def fake_download(url, destination, digest, limit):
            source = header if "raw.githubusercontent.com" in url else archive
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(source.read_bytes())

        with mock.patch.object(module, "verified_download", side_effect=fake_download), \
             mock.patch.object(module, "smoke_compiler", return_value="mocked-native"):
            result = module.install(self.args())
        self.assertEqual(result["obfuscator-installed"], "true")
        self.assertEqual(result["release-qualified"], "false")
        self.assertTrue(Path(result["cc"]).is_file())
        self.assertTrue(Path(result["obfus-header"]).is_file())
        self.assertEqual(Path(result["obfus-header"]).read_bytes(), header.read_bytes())
        cmake = Path(result["toolchain-file"]).read_text(encoding="utf-8")
        self.assertIn(result["cc"].replace("\\", "/"), cmake)
        self.assertNotIn("/installed/tcc.exe", cmake)
        self.assertNotIn(".qigao-compiler-", cmake)
        self.assertEqual(
            json.loads((self.temp / "install/qigao-compiler-install.json").read_text())["target"],
            "x64",
        )

    def test_llvm_tar_with_safe_symlink_and_relocated_cmake(self):
        archive = self.llvm_fixture()

        def fake_download(url, destination, digest, limit):
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read_bytes())

        with mock.patch.object(module, "verified_download", side_effect=fake_download), \
             mock.patch.object(module, "smoke_compiler", return_value="mocked-cross"):
            result = module.install(self.args(compiler="llvm-mingw", os="Linux"))
        self.assertTrue(Path(result["cc"]).is_file())
        self.assertTrue(Path(result["cxx"]).is_file())
        cmake = Path(result["toolchain-file"]).read_text(encoding="utf-8")
        self.assertIn(result["cc"].replace("\\", "/"), cmake)
        self.assertNotIn(".qigao-compiler-", cmake)
        self.assertEqual(result["smoke"], "mocked-cross")

    def test_native_llvm_unpinned_distribution_fails_before_network(self):
        self.contract["sources"]["llvm-native"]["distribution"] = "not-yet-pinned"
        self.contract["sources"]["llvm-native"]["source_commit"] = None
        self.contract["sources"]["llvm-native"]["assets"] = []
        for host_os, host_arch, target in (
                ("Linux", "X64", "x64"),
                ("Linux", "ARM64", "arm64"),
                ("macOS", "X64", "x64"),
                ("macOS", "ARM64", "arm64")):
            with self.subTest(os=host_os, arch=host_arch):
                args = self.args(compiler="llvm-native", os=host_os,
                                 arch=host_arch, target=target)
                with mock.patch.object(module, "verified_download") as dl:
                    with self.assertRaisesRegex(
                            module.AdmissionError, "distribution not SHA256-pinned"):
                        module.install(args)
                    dl.assert_not_called()

    def test_native_llvm_cross_arch_is_denied(self):
        args = self.args(compiler="llvm-native", os="Linux",
                         arch="ARM64", target="x64")
        with mock.patch.object(module, "verified_download") as dl:
            with self.assertRaisesRegex(
                    module.AdmissionError, "must exactly match"):
                module.install(args)
            dl.assert_not_called()

    def test_native_machine_audit_is_strict(self):
        payloads = (
            (b"\x7fELF" + bytes((2, 1)) + bytes(12) +
             struct.pack("<H", 183) + bytes(44), ("ELF", 183)),
            (bytes.fromhex("cffaedfe") + struct.pack("<I", 0x0100000c) +
             bytes(56), ("Mach-O", 0x0100000c)),
        )
        for i, (blob, expected) in enumerate(payloads):
            file = self.temp / f"native-{i}"
            file.write_bytes(blob)
            self.assertEqual(module.native_machine(file), expected)
        invalid = self.temp / "unknown"
        invalid.write_bytes(bytes(64))
        with self.assertRaisesRegex(module.AdmissionError, "not ELF64"):
            module.native_machine(invalid)

    def test_native_llvm_installer_reuses_existing_safe_archive_and_cmake(self):
        archive = self.temp / "native-llvm.tar.xz"
        with tarfile.open(archive, "w:xz") as output:
            for tool in ("clang", "clang++", "llvm-ar", "llvm-ranlib"):
                data = b"pinned fixture executable"
                info = tarfile.TarInfo(name=f"kit/bin/{tool}")
                info.size, info.mode = len(data), 0o755
                output.addfile(info, io.BytesIO(data))
        native = self.contract["sources"]["llvm-native"]
        native["distribution"] = "pinned"
        native["source_commit"] = "a" * 40
        native["assets"] = [{
            "host": "linux-arm64", "name": "native-llvm.tar.xz",
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        }]

        def fake_download(url, destination, digest, limit):
            self.assertIn("llvmorg-23.1.4", url)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read_bytes())

        with mock.patch.object(module, "verified_download",
                               side_effect=fake_download), mock.patch.object(
                module, "smoke_compiler", return_value="native-execution"):
            result = module.install(self.args(
                compiler="llvm-native", os="Linux", arch="ARM64",
                target="arm64"))
        self.assertTrue(Path(result["cc"]).is_file())
        self.assertTrue(Path(result["cxx"]).is_file())
        self.assertEqual(result["release-qualified"], "false")
        cmake = Path(result["toolchain-file"]).read_text(encoding="utf-8")
        self.assertIn("set(CMAKE_SYSTEM_NAME Linux)", cmake)
        self.assertIn("set(CMAKE_SYSTEM_PROCESSOR aarch64)", cmake)
        self.assertIn(result["cc"].replace("\\", "/"), cmake)
        self.assertNotIn(".qigao-compiler-", cmake)

    def test_unqualified_release_fails_before_any_network(self):
        with mock.patch.object(module, "verified_download") as download:
            with self.assertRaisesRegex(module.AdmissionError, "unqualified"):
                module.install(self.args(build_type="Release"))
            download.assert_not_called()
        self.assertFalse((self.temp / "install").exists())

    def test_tinycc_requires_windows_x64_host(self):
        with self.assertRaisesRegex(module.AdmissionError, "Windows x64 host"):
            module.install(self.args(os="Linux"))

    def test_tinycc_cannot_claim_armv7(self):
        with self.assertRaisesRegex(module.AdmissionError, "unsupported TinyCC target"):
            module.install(self.args(target="armv7"))

    def test_missing_version_lock_fails_before_network(self):
        args = self.args()
        args.version = "latest"
        with mock.patch.object(module, "verified_download") as download:
            with self.assertRaisesRegex(module.AdmissionError, "immutable lock"):
                module.install(args)
            download.assert_not_called()

    def test_unsafe_archive_paths_are_rejected(self):
        for path in ("../bad", "safe/../../bad", "safe//bad",
                     "/absolute", "C:/drive", "safe\\windows", "./bad",
                     "bad.", "bad "):
            with self.subTest(path=path):
                with self.assertRaises(module.AdmissionError):
                    module.safe_path(path)

    def test_archived_file_cannot_be_parent_of_directory(self):
        with self.assertRaisesRegex(module.AdmissionError, "file has children"):
            module.validate_members([("a/b", False, 2), ("a", False, 3)])

    def test_zip_symlink_is_rejected(self):
        archive = self.temp / "bad.zip"
        with zipfile.ZipFile(archive, "w") as out:
            entry = zipfile.ZipInfo("link")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            out.writestr(entry, "outside")
        with self.assertRaises(module.AdmissionError):
            module.safe_extract(archive, self.temp / "badextract")

    def test_zip_traversal_is_rejected_before_extraction(self):
        archive = self.temp / "bad.zip"
        with zipfile.ZipFile(archive, "w") as out:
            out.writestr("../escape", "attacker")
        with self.assertRaises(module.AdmissionError):
            module.safe_extract(archive, self.temp / "badextract")
        self.assertFalse((self.temp / "escape").exists())

    def test_tar_escaping_symlink_is_rejected(self):
        archive = self.temp / "bad.tar.xz"
        with tarfile.open(archive, "w:xz") as out:
            link = tarfile.TarInfo("kit/bin/out")
            link.type = tarfile.SYMTYPE
            link.linkname = "../../../outside"
            out.addfile(link)
        with self.assertRaises(module.AdmissionError):
            module.safe_extract(archive, self.temp / "badextract")

    def test_remote_download_requires_actual_sha(self):
        url = "https://github.com/example/repo/releases/download/v1/archive.zip"
        output = self.temp / "download.zip"
        with mock.patch.object(module.urllib.request, "urlopen",
                               return_value=FakeResponse(b"bytes", url)):
            with self.assertRaisesRegex(module.AdmissionError, "SHA256 mismatch"):
                module.verified_download(url, output, "0" * 64, 1024)
        self.assertFalse(output.exists())

    def test_verified_download_does_not_need_token_or_mono(self):
        url = "https://github.com/example/repo/releases/download/v1/archive.zip"
        payload = b"some immutable bytes"
        output = self.temp / "download.zip"
        with mock.patch.object(module.urllib.request, "urlopen",
                               return_value=FakeResponse(payload, url)):
            module.verified_download(url, output, hashlib.sha256(payload).hexdigest(), 1024)
        self.assertEqual(payload, output.read_bytes())

    def test_download_redirect_to_untrusted_host_is_rejected(self):
        url = "https://github.com/example/repo/releases/download/v1/archive.zip"
        output = self.temp / "download.zip"
        with mock.patch.object(module.urllib.request, "urlopen",
                               return_value=FakeResponse(b"bad", "https://evil.invalid/bad")):
            with self.assertRaisesRegex(module.AdmissionError, "untrusted compiler download redirect"):
                module.verified_download(url, output, hashlib.sha256(b"bad").hexdigest(), 1024)

    def test_pe_machine_reads_exact_machine(self):
        exe = self.temp / "fixture.exe"
        header = bytearray(128)
        header[:2] = b"MZ"
        struct.pack_into("<I", header, 0x3C, 0x40)
        header[0x40:0x44] = b"PE\x00\x00"
        struct.pack_into("<H", header, 0x44, 0xAA64)
        exe.write_bytes(header)
        self.assertEqual(module.pe_machine(exe), 0xAA64)


if __name__ == "__main__":
    unittest.main()
