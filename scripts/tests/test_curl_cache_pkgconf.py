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


class CurlHostDownloads(unittest.TestCase):
    """The shared compiler/pkgconf downloader publishes only verified bytes."""

    def fake_curl(self, payload=b"archive", status=200, redirect="", exit_code=0):
        process = mock.Mock()
        process.stdout = io.BytesIO(payload)
        process.wait.return_value = exit_code

        def start(command, *, stdout, stderr):
            self.assertEqual(command[0], "curl")
            self.assertNotIn("--location", command)
            self.assertEqual(command[command.index("--proto") + 1], "=https")
            self.assertLessEqual(int(command[command.index("--max-time") + 1]), 180)
            stderr.write(f"{status}\n{redirect}\n".encode())
            return process

        return process, start

    def test_redirected_download_is_verified_before_atomic_publication(self):
        payload = b"verified compiler archive"
        digest = hashlib.sha256(payload).hexdigest()
        redirect = "https://release-assets.githubusercontent.com/pinned.zip?signature=opaque"
        _, first = self.fake_curl(b"", 302, redirect)
        _, second = self.fake_curl(payload)
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "tool.zip"
            target.write_bytes(b"previous complete archive")
            factories = iter((first, second))

            def start(command, **kwargs):
                self.assertEqual(target.read_bytes(), b"previous complete archive")
                return next(factories)(command, **kwargs)

            with mock.patch.object(native.downloads.subprocess, "Popen", side_effect=start) as curl:
                native.downloads.verified_download(
                    "https://github.com/owner/repo/archive.zip", target, digest, 1024)
            self.assertEqual(curl.call_count, 2)
            self.assertEqual(curl.call_args_list[1].args[0][-1], redirect)
            self.assertEqual(target.read_bytes(), payload)
            self.assertEqual(list(Path(temporary).iterdir()), [target])

    def test_redirect_destination_is_rejected_before_connecting(self):
        redirects = (
            "http://github.com/archive.zip", "https://elsewhere.invalid/archive.zip",
            "https://user@github.com/archive.zip", "https://github.com:444/archive.zip",
        )
        for redirect in redirects:
            with self.subTest(redirect=redirect), tempfile.TemporaryDirectory() as temporary:
                _, start = self.fake_curl(b"", 302, redirect)
                target = Path(temporary) / "tool"
                with mock.patch.object(native.downloads.subprocess, "Popen", side_effect=start) as curl:
                    with self.assertRaisesRegex(ValueError, "untrusted compiler download redirect"):
                        native.downloads.verified_download(
                            "https://github.com/owner/archive", target, "a" * 64, 1024)
                self.assertEqual(curl.call_count, 1)
                self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_streaming_limit_kills_curl_and_preserves_existing_file(self):
        process, start = self.fake_curl(b"too much data")
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "tool"
            target.write_bytes(b"previous verified file")
            with mock.patch.object(native.downloads.subprocess, "Popen", side_effect=start) as curl:
                with self.assertRaisesRegex(ValueError, "size bound"):
                    native.downloads.verified_download(
                        "https://github.com/owner/archive", target, "a" * 64, 4)
            process.kill.assert_called_once()
            self.assertTrue(process.stdout.closed)
            self.assertEqual(curl.call_count, 1)
            self.assertEqual(target.read_bytes(), b"previous verified file")
            self.assertEqual(list(Path(temporary).iterdir()), [target])

    def test_bad_digest_and_empty_body_never_publish_or_retry(self):
        for payload, message in ((b"wrong archive", "SHA256 mismatch"), (b"", "empty compiler download")):
            with self.subTest(message=message), tempfile.TemporaryDirectory() as temporary:
                _, start = self.fake_curl(payload)
                target = Path(temporary) / "tool"
                with mock.patch.object(native.downloads.subprocess, "Popen", side_effect=start) as curl:
                    with self.assertRaisesRegex(ValueError, message):
                        native.downloads.verified_download(
                            "https://github.com/owner/archive", target, "a" * 64, 1024)
                self.assertEqual(curl.call_count, 1)
                self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_transient_failure_retries_with_a_fresh_archive(self):
        payload = b"good archive"
        digest = hashlib.sha256(payload).hexdigest()
        _, first = self.fake_curl(b"interrupted", status=0, exit_code=7)
        _, second = self.fake_curl(payload)
        factories = iter((first, second))
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "tool"
            with mock.patch.object(native.downloads.subprocess, "Popen",
                    side_effect=lambda command, **kwargs: next(factories)(command, **kwargs)) as curl, \
                 mock.patch.object(native.downloads.time, "sleep") as pause:
                native.downloads.verified_download(
                    "https://github.com/owner/archive", target, digest, 1024)
            self.assertEqual(curl.call_count, 2)
            pause.assert_called_once_with(1)
            self.assertEqual(target.read_bytes(), payload)

    def test_network_failures_and_redirect_cycles_are_bounded(self):
        for status, exit_code, expected_calls, message in (
            (0, 28, 3, "curl source download failed"),
            (302, 0, 6, "redirect limit"),
            (0, 63, 1, "size bound"),
        ):
            with self.subTest(status=status, exit_code=exit_code), tempfile.TemporaryDirectory() as temporary:
                def start(command, **kwargs):
                    _, factory = self.fake_curl(b"", status,
                        "https://github.com/owner/archive", exit_code)
                    return factory(command, **kwargs)

                target = Path(temporary) / "tool"
                with mock.patch.object(native.downloads.subprocess, "Popen", side_effect=start) as curl, \
                     mock.patch.object(native.downloads.time, "sleep"):
                    with self.assertRaisesRegex(ValueError, message):
                        native.downloads.verified_download(
                            "https://github.com/owner/archive", target, "a" * 64, 1024)
                self.assertEqual(curl.call_count, expected_calls)
                self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_pkgconf_explicit_host_allowlist_uses_the_same_curl_path(self):
        payload = b"native pkgconf wheel"
        _, start = self.fake_curl(payload)
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "pkgconf.whl"
            with mock.patch.object(native.downloads.subprocess, "Popen", side_effect=start) as curl:
                native.downloads.verified_download(
                    "https://files.pythonhosted.org/pkgconf.whl", target,
                    hashlib.sha256(payload).hexdigest(), 1024,
                    initial_hosts=("files.pythonhosted.org",),
                    redirect_hosts=("files.pythonhosted.org",))
            self.assertEqual(curl.call_count, 1)
            self.assertEqual(target.read_bytes(), payload)


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
