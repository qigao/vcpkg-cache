"""Exercise real package parsing/extraction with only the network transport replaced."""
from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PureWindowsPath
import shutil
import stat
import tarfile
import tempfile
import unittest
from unittest import mock
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "restore-native-dependency.py"
SPEC = importlib.util.spec_from_file_location("restore_native_dependency", SCRIPT)
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)
PACKAGE_ID = "Qigao.Example.Native"
VERSION = "1.2.3-rc.1"
NUSPEC = f"<package><metadata><id>{PACKAGE_ID}</id><version>{VERSION}</version></metadata></package>"


class LocalClient:
    def __init__(self, archive):
        self.archive = archive
        self.calls = []

    def json(self, url):
        self.calls.append(url)
        if url != "https://nuget.pkg.github.com/qigao/index.json":
            raise AssertionError("no version catalog or latest lookup is permitted")
        return {"resources": [{"@type": "PackageBaseAddress/3.0.0",
                               "@id": "https://nuget.pkg.github.com/qigao/download"}]}

    def download(self, url, destination, accept):
        self.calls.append(url)
        shutil.copyfile(self.archive, destination)
        return True


class NativeDependencyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.destination = self.work / "SDK and tools"
        self.archive = self.work / "input.nupkg"
        self.zip_archive()
        self.exports = {}
        for key in ("GITHUB_ENV", "GITHUB_PATH", "GITHUB_OUTPUT"):
            path = self.work / key
            path.write_text("sentinel\n", encoding="utf-8")
            self.exports[key] = str(path)
        self.environment = mock.patch.dict(os.environ, self.exports)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def zip_archive(self, extra=(), nuspec=NUSPEC):
        with zipfile.ZipFile(self.archive, "w") as zf:
            zf.writestr("Example.nuspec", nuspec)
            zf.writestr("sdk/windows-x64/include/example.h", "// SDK header\n")
            binary = zipfile.ZipInfo("sdk/windows-x64/bin/example")
            binary.create_system = 3
            binary.external_attr = (stat.S_IFREG | 0o755) << 16
            zf.writestr(binary, "#!/bin/sh\nexit 0\n")
            for name, data in extra:
                zf.writestr(name, data)

    def arguments(self, *extra, kind="package"):
        source = ["package", PACKAGE_ID, VERSION] if kind == "package" else ["url", "https://github.com/example/tools/releases/download/v1.2.3/tools.zip"]
        return native.parser().parse_args(source + [
            "--destination", str(self.destination), "--sha256", native.packages.sha256(self.archive),
            "--payload", "sdk/windows-x64", "--require", "include/example.h"] + list(extra))

    def feed(self):
        self.client = LocalClient(self.archive)
        return native.packages.NugetFeed(self.client)

    def assert_unpublished(self):
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.work.glob(".native-dependency-*")), [])
        for path in self.exports.values():
            self.assertEqual(Path(path).read_text(encoding="utf-8"), "sentinel\n")

    def test_exact_package_local_restore_receipt_and_no_catalog(self):
        receipt = native.restore(self.arguments(), feed=self.feed())
        root = Path(receipt["root"])
        self.assertEqual((root / "include/example.h").read_text(), "// SDK header\n")
        self.assertEqual(json.loads(Path(receipt["receipt"]).read_text()), receipt)
        self.assertEqual(receipt["source"]["version"], VERSION)
        self.assertEqual(self.client.calls, [
            "https://nuget.pkg.github.com/qigao/index.json",
            f"https://nuget.pkg.github.com/qigao/download/{PACKAGE_ID.lower()}/{VERSION}/{PACKAGE_ID.lower()}.{VERSION}.nupkg"])
        self.assertFalse((self.destination / "source.nupkg").exists())
        for path in self.exports.values():
            self.assertEqual(Path(path).read_text(), "sentinel\n")
        if os.name != "nt":
            self.assertEqual((root / "bin/example").stat().st_mode & 0o777, 0o755)

    def test_actions_outputs_env_path_and_receipt_agree(self):
        args = self.arguments("--github-output", "--env-prefix", "EXAMPLE", "--add-path", "bin",
                              "--executable", "bin/example")
        receipt = native.restore(args, feed=self.feed())
        output = Path(self.exports["GITHUB_OUTPUT"]).read_text()
        env = Path(self.exports["GITHUB_ENV"]).read_text()
        self.assertIn(f"root={receipt['root']}\n", output)
        self.assertIn(f"receipt={receipt['receipt']}\n", output)
        self.assertIn(f"EXAMPLE_ROOT={receipt['root']}\n", env)
        self.assertIn(f"EXAMPLE_SHA256={receipt['sha256']}\n", env)
        self.assertEqual(Path(self.exports["GITHUB_PATH"]).read_text(),
                         f"sentinel\n{receipt['root']}/bin\n")
        self.assertNotIn("\\", receipt["root"])

    def test_hash_mismatch_precedes_zip_parsing_and_no_exports(self):
        self.archive.write_bytes(b"not a zip")
        args = self.arguments("--github-output", "--env-prefix", "EXAMPLE")
        args.sha256 = "0" * 64
        with mock.patch.object(native.packages.zipfile, "ZipFile", side_effect=AssertionError("ZIP opened before hash")):
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                native.restore(args, feed=self.feed())
        self.assert_unpublished()

    def test_missing_target_file_or_path_does_not_fall_back(self):
        for flag, value in (("--payload", "sdk/linux-x64"), ("--require", "missing.h"),
                            ("--add-path", "missing-bin"), ("--executable", "missing-tool")):
            with self.subTest(flag=flag):
                with self.assertRaises(ValueError):
                    native.restore(self.arguments(flag, value), feed=self.feed())
                self.assert_unpublished()

    def test_bad_package_identity_is_rejected(self):
        self.zip_archive(nuspec=NUSPEC.replace(PACKAGE_ID, "Different.Package"))
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            native.restore(self.arguments(), feed=self.feed())
        self.assert_unpublished()

    def test_unsafe_zip_members_are_rejected_before_publication(self):
        entries = ["../outside", "sdk/CON/file", "sdk/trailing./file", "sdk/bad?.h",
                   "sdk/windows-x64/INCLUDE/EXAMPLE.H", "sdk/windows-x64/include"]
        for entry in entries:
            with self.subTest(entry=entry):
                self.zip_archive(extra=[(entry, "bad")])
                with self.assertRaises(ValueError):
                    native.restore(self.arguments(), feed=self.feed())
                self.assert_unpublished()
        for mode in (stat.S_IFLNK | 0o777, stat.S_IFIFO | 0o644):
            self.zip_archive()
            with zipfile.ZipFile(self.archive, "a") as zf:
                special = zipfile.ZipInfo("sdk/special")
                special.create_system = 3
                special.external_attr = mode << 16
                zf.writestr(special, "target")
            with self.assertRaises(ValueError):
                native.restore(self.arguments(), feed=self.feed())
            self.assert_unpublished()

    def test_invalid_requests_do_not_start_transport(self):
        for attribute, value in (("version", "latest"), ("version", "1.2.*"),
                                 ("sha256", "deadbeef"), ("payload", "../outside"),
                                 ("env_prefix", "ROOT\nINJECT=yes")):
            args = self.arguments()
            setattr(args, attribute, value)
            with self.subTest(attribute=attribute), mock.patch.object(native.packages, "Curl", side_effect=AssertionError("transport started")):
                with self.assertRaises(ValueError):
                    native.restore(args)
            self.assert_unpublished()

    def test_existing_destination_and_symlink_are_never_replaced(self):
        self.destination.mkdir()
        sentinel = self.destination / "sentinel"
        sentinel.write_text("keep")
        with self.assertRaisesRegex(ValueError, "fresh"):
            native.restore(self.arguments())
        self.assertEqual(sentinel.read_text(), "keep")
        if os.name != "nt":
            link = self.work / "dangling"
            link.symlink_to(self.work / "absent")
            args = self.arguments()
            args.destination = str(link)
            with self.assertRaisesRegex(ValueError, "fresh"):
                native.restore(args)
            self.assertTrue(link.is_symlink())

    def test_windows_drive_and_unc_path_serialization(self):
        for path, expected in ((PureWindowsPath(r"D:\a\SDK space\include"), "D:/a/SDK space/include"),
                               (PureWindowsPath(r"\\server\share\SDK space"), "//server/share/SDK space")):
            self.assertEqual(native.normalized(path), expected)

    def test_resolve_latest_selects_numeric_stable_and_locked_restore_never_resolves_again(self):
        selected = "1.2.10.1"
        self.zip_archive(nuspec=NUSPEC.replace(VERSION, selected))
        class VersionClient(LocalClient):
            def json(self, url):
                if url.endswith(f"/{PACKAGE_ID.lower()}/index.json"):
                    self.calls.append(url)
                    return {"versions": ["1.2.9", "1.2.10", selected, "2.0.0-rc.1"]}
                return super().json(url)
        client = VersionClient(self.archive)
        output = self.work / "dependency.lock.json"
        args = native.parser().parse_args(["resolve", PACKAGE_ID, "--version", "latest", "--output-lock", str(output)])
        lock = native.resolve_package(args, feed=native.packages.NugetFeed(client))
        self.assertEqual(lock["source"]["version"], selected)
        self.assertEqual(lock["sha256"], native.packages.sha256(self.archive))
        self.assertEqual(json.loads(output.read_text()), lock)
        locked = native.parser().parse_args(["locked", str(output), "--destination", str(self.destination),
                                             "--payload", "sdk/windows-x64", "--require", "include/example.h"])
        receipt = native.restore(locked, feed=self.feed())
        self.assertEqual(receipt["source"], lock["source"])
        # LocalClient rejects version index requests: locked restore is exact.
        self.assertEqual(len(self.client.calls), 2)

    def test_resolve_exact_skips_version_index_and_failed_update_preserves_lock(self):
        output = self.work / "dependency.lock.json"
        args = native.parser().parse_args(["resolve", PACKAGE_ID, "--version", VERSION, "--output-lock", str(output)])
        lock = native.resolve_package(args, feed=self.feed())
        self.assertEqual(lock["source"]["version"], VERSION)
        original = output.read_bytes()
        with mock.patch.object(self.client, "download", side_effect=ValueError("access denied")):
            with self.assertRaisesRegex(ValueError, "access denied"):
                native.resolve_package(args, feed=native.packages.NugetFeed(self.client))
        self.assertEqual(output.read_bytes(), original)
        self.assertEqual(list(self.work.glob(".native-lock-*")), [])

    def test_latest_without_a_stable_package_fails_without_download(self):
        client = LocalClient(self.archive)
        original_json = client.json
        client.json = lambda url: ({"versions": ["2.0.0-rc.1"]} if url.endswith(f"/{PACKAGE_ID.lower()}/index.json") else original_json(url))
        args = native.parser().parse_args(["resolve", PACKAGE_ID, "--version", "latest", "--output-lock", str(self.work / "lock.json")])
        with mock.patch.object(client, "download", side_effect=AssertionError("downloaded prerelease")):
            with self.assertRaisesRegex(ValueError, "no stable"):
                native.resolve_package(args, feed=native.packages.NugetFeed(client))
        self.assertFalse((self.work / "lock.json").exists())

    def test_matching_installation_reuses_receipt_without_network(self):
        first = native.restore(self.arguments(), feed=self.feed())
        with mock.patch.object(native.packages, "Curl", side_effect=AssertionError("reuse downloaded")):
            second = native.restore(self.arguments("--reuse"))
        self.assertEqual(first, second)

    def test_modern_python_archive_validation_uses_ntpath_without_removed_pathlib_api(self):
        with mock.patch.object(native.archives.ntpath, "isreserved", create=True,
                               side_effect=lambda name: name.upper() in {"CON", "NUL"}) as modern, \
             mock.patch.object(native.archives, "PureWindowsPath", side_effect=AssertionError("removed Python 3.15 API")):
            self.assertEqual(native.archives.safe_path("tools/bin/example"), ("tools", "bin", "example"))
            with self.assertRaises(ValueError):
                native.archives.safe_path("tools/CON/example")
            self.assertIn(mock.call("CON"), modern.call_args_list)

    @unittest.skipIf(os.name == "nt", "creating symlinks requires Windows privileges")
    def test_reuse_rejects_a_payload_directory_replaced_by_a_symlink(self):
        native.restore(self.arguments(), feed=self.feed())
        moved = self.work / "moved-payload"
        (self.destination / "payload").rename(moved)
        (self.destination / "payload").symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "real installation directory"):
            native.restore(self.arguments("--reuse"))

    def test_reuse_rejects_changed_hash_options_and_missing_required_file(self):
        first = native.restore(self.arguments(), feed=self.feed())
        for change in ("hash", "options", "file"):
            args = self.arguments("--reuse")
            if change == "hash":
                args.sha256 = "0" * 64
            elif change == "options":
                args.require += ["bin/example"]
            else:
                (Path(first["root"]) / "include/example.h").unlink()
            with self.subTest(change=change), mock.patch.object(native.packages, "Curl", side_effect=AssertionError("reuse downloaded")):
                with self.assertRaises(ValueError):
                    native.restore(args)
            self.assertEqual(json.loads(Path(first["receipt"]).read_text()), first)

    def test_invalid_lock_and_conflicting_sha_fail_before_transport(self):
        output = self.work / "lock.json"
        source = {"kind": "package", "id": PACKAGE_ID, "version": VERSION,
                  "feed": "https://nuget.pkg.github.com/qigao/index.json"}
        for lock in ({"schema": 2, "source": source, "sha256": "a" * 64},
                     {"schema": 1, "source": dict(source, feed="https://other.invalid"), "sha256": "a" * 64},
                     {"schema": 1, "source": source, "sha256": None},
                     {"schema": 1, "source": dict(source, version="latest"), "sha256": "a" * 64}):
            output.write_text(json.dumps(lock))
            args = native.parser().parse_args(["locked", str(output), "--destination", str(self.destination)])
            with mock.patch.object(native.packages, "Curl", side_effect=AssertionError("invalid lock downloaded")):
                with self.assertRaises(ValueError):
                    native.restore(args)
            self.assert_unpublished()
        output.write_text(json.dumps({"schema": 1, "source": source, "sha256": "a" * 64}))
        args = native.parser().parse_args(["locked", str(output), "--destination", str(self.destination), "--sha256", "b" * 64])
        with self.assertRaisesRegex(ValueError, "override differs"):
            native.restore(args)
        self.assert_unpublished()

    def test_public_url_reuses_verified_curl_download_and_safe_extractor(self):
        args = self.arguments(kind="url")
        data = self.archive.read_bytes()
        with mock.patch.object(native.archives, "_curl_response") as response:
            def transfer(url, destination, limit, timeout):
                self.assertEqual(url, args.url)
                destination.write_bytes(data)
                return 200, "", len(data), hashlib.sha256(data).hexdigest()
            response.side_effect = transfer
            with mock.patch.object(native.packages, "Curl", side_effect=AssertionError("public tool requested token")):
                receipt = native.restore(args)
        self.assertEqual(receipt["source"], {"kind": "url", "url": args.url})

    def test_public_tar_xz_with_relative_internal_link(self):
        self.archive = self.work / "input.tar.xz"
        with tarfile.open(self.archive, "w:xz") as tf:
            for name in ("tools/bin/tool", "tools/include/example.h"):
                item = tarfile.TarInfo(name)
                item.size, item.mode = 2, 0o755
                tf.addfile(item, io.BytesIO(b"ok"))
            link = tarfile.TarInfo("tools/alias")
            link.type, link.linkname = tarfile.SYMTYPE, "bin/tool"
            tf.addfile(link)
        args = self.arguments(kind="url")
        args.url = "https://github.com/example/tools/releases/download/v1.2.3/tool.tar.xz"
        args.payload = "tools"
        def download(url, destination, digest, limit):
            shutil.copyfile(self.archive, destination)
        receipt = native.restore(args, download=download)
        self.assertEqual((Path(receipt["root"]) / "alias").read_text(), "ok")

    def test_escaping_tar_link_and_untrusted_tool_url_are_rejected(self):
        self.archive = self.work / "input.tar.xz"
        with tarfile.open(self.archive, "w:xz") as tf:
            link = tarfile.TarInfo("tools/alias")
            link.type, link.linkname = tarfile.SYMTYPE, "../../outside"
            tf.addfile(link)
        args = self.arguments(kind="url")
        args.url = "https://github.com/example/tools/releases/download/v1.2.3/tool.tar.xz"
        def download(url, destination, digest, limit):
            shutil.copyfile(self.archive, destination)
        with self.assertRaises(ValueError):
            native.restore(args, download=download)
        self.assert_unpublished()
        for url in ("http://github.com/example/tool.zip", "https://other.example/tool.zip",
                    "https://github.com/example/tool.zip?token=private", "https://github.com/example/tool.exe"):
            args.url = url
            with self.subTest(url=url), mock.patch.object(native.archives, "verified_download", side_effect=AssertionError("transport started")):
                with self.assertRaises(ValueError):
                    native.restore(args)
            self.assert_unpublished()


if __name__ == "__main__":
    unittest.main()
