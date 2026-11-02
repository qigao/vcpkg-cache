"""Native Windows pkgconf integrity, host selection and real metadata lookup."""
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / "windows_pkgconf.py"
SPEC = importlib.util.spec_from_file_location("native_windows_pkgconf", SOURCE)
assert SPEC and SPEC.loader
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)


class NativePkgconfContract(unittest.TestCase):
    def test_host_selection_is_independent_of_cross_compile_target(self):
        self.assertEqual(native.host_arch({"PROCESSOR_ARCHITECTURE": "AMD64",
                                          "LLVM_MINGW_TARGET": "arm64"}), "x64")
        self.assertEqual(native.host_arch({"PROCESSOR_ARCHITECTURE": "x86",
                                          "PROCESSOR_ARCHITEW6432": "ARM64"}), "arm64")
        for environment in ({}, {"PROCESSOR_ARCHITECTURE": "unknown"}, {"PROCESSOR_ARCHITECTURE": "x86"}):
            with self.assertRaisesRegex(ValueError, "unsupported Windows host"):
                native.host_arch(environment)

    def tool_paths(self, temporary):
        root = Path(temporary) / f"qigao-pkgconf-{native.VERSION}-x64"
        return root, root / "bin/pkg-config.exe"

    def test_verified_cache_reuse_preserves_existing_vcpkg_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, exe = self.tool_paths(temporary)
            exe.parent.mkdir(parents=True)
            exe.write_bytes(b"native fixture")
            digest = hashlib.sha256(exe.read_bytes()).hexdigest()
            with mock.patch.dict(native.PACKAGES, {"x64": ("https://files.pythonhosted.org/fixture.whl", "a" * 64, digest)}), \
                 mock.patch.object(native.downloads, "verified_download") as download:
                values = native.prepare_pkgconf(Path(temporary), {
                    "PROCESSOR_ARCHITECTURE": "AMD64",
                    "VCPKG_KEEP_ENV_VARS": "GIT_ASKPASS;PKG_CONFIG;CUSTOM;",
                })
            download.assert_not_called()
            self.assertEqual(values["PKG_CONFIG"], exe.resolve().as_posix())
            self.assertEqual(values["QIGAO_PKGCONF_VERSION"], native.VERSION)
            self.assertEqual(values["VCPKG_KEEP_ENV_VARS"],
                             "GIT_ASKPASS;PKG_CONFIG;CUSTOM;QIGAO_PKGCONF_VERSION")

    def test_corrupt_executable_is_rejected_without_download_or_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, exe = self.tool_paths(temporary)
            exe.parent.mkdir(parents=True)
            exe.write_bytes(b"corrupt")
            with mock.patch.object(native.downloads, "verified_download") as download:
                with self.assertRaisesRegex(ValueError, "cached native pkg-config SHA256"):
                    native.prepare_pkgconf(Path(temporary), {"PROCESSOR_ARCHITECTURE": "AMD64"})
            download.assert_not_called()

    def wheel(self, content):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            archive.writestr(native.MEMBER, content)
        return stream.getvalue()

    def test_corrupt_archive_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, _ = self.tool_paths(temporary)
            root.mkdir()
            archive = root / native.PACKAGES["x64"][0].rsplit("/", 1)[1]
            archive.write_bytes(b"wrong archive")
            with self.assertRaisesRegex(ValueError, "archive SHA256"):
                native.prepare_pkgconf(Path(temporary), {"PROCESSOR_ARCHITECTURE": "AMD64"})

    def test_private_extraction_admits_only_pinned_standalone_executable(self):
        exe_bytes = b"native executable fixture"
        archive_bytes = self.wheel(exe_bytes)
        url = "https://files.pythonhosted.org/fixture.whl"
        pins = (url, hashlib.sha256(archive_bytes).hexdigest(),
                hashlib.sha256(exe_bytes).hexdigest())
        with tempfile.TemporaryDirectory(prefix="pkgconf path with spaces ") as temporary:
            def download(source, destination, expected, limit, **kwargs):
                self.assertEqual(source, url)
                self.assertEqual(expected, pins[1])
                self.assertEqual(kwargs["initial_hosts"], ("files.pythonhosted.org",))
                self.assertEqual(kwargs["redirect_hosts"], ("files.pythonhosted.org",))
                self.assertLess(len(archive_bytes), limit)
                destination.write_bytes(archive_bytes)

            with mock.patch.dict(native.PACKAGES, {"x64": pins}), \
                 mock.patch.object(native.downloads, "verified_download", side_effect=download):
                values = native.prepare_pkgconf(Path(temporary), {"PROCESSOR_ARCHITECTURE": "AMD64"})
            self.assertEqual(Path(values["PKG_CONFIG"]).read_bytes(), exe_bytes)

    def test_executable_hash_mismatch_does_not_publish_tool(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, exe = self.tool_paths(temporary)
            root.mkdir()
            archive = root / "fixture.whl"
            archive.write_bytes(self.wheel(b"wrong executable"))
            pins = ("https://files.pythonhosted.org/fixture.whl",
                    hashlib.sha256(archive.read_bytes()).hexdigest(), "b" * 64)
            with mock.patch.dict(native.PACKAGES, {"x64": pins}):
                with self.assertRaisesRegex(ValueError, "executable SHA256"):
                    native.prepare_pkgconf(Path(temporary), {"PROCESSOR_ARCHITECTURE": "AMD64"})
            self.assertFalse(exe.exists())

    def test_compiler_downloader_still_rejects_pypi_by_default(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "untrusted initial"):
                native.downloads.verified_download(
                    native.PACKAGES["x64"][0], Path(temporary) / "tool", "a" * 64, 1024)

    @unittest.skipUnless(os.name == "nt", "upstream native Windows package")
    def test_real_native_tool_reads_pc_metadata_without_msys(self):
        # This exercises the real production setup and native packaged tool,
        # using a .pc input fixture instead of a synthetic consumer build.
        with tempfile.TemporaryDirectory(prefix="native pkgconf integration ") as temporary:
            values = native.prepare_pkgconf(Path(temporary))
            pc = Path(temporary) / "metadata"
            pc.mkdir()
            (pc / "fixture.pc").write_text(
                "Name: fixture\nDescription: native pkgconf contract\nVersion: 1.2.3\n"
                "Cflags: -DFIXTURE=1\nLibs: -lfixture\n", encoding="utf-8")
            environment = dict(os.environ, PKG_CONFIG_LIBDIR=str(pc), PKG_CONFIG_PATH="")
            result = subprocess.run([values["PKG_CONFIG"], "--cflags", "--libs", "fixture"],
                                    env=environment, check=True, capture_output=True, text=True)
            self.assertIn("-DFIXTURE=1", result.stdout)
            self.assertIn("-lfixture", result.stdout)


if __name__ == "__main__":
    unittest.main()
