"""Exercise exact re2c packages through the real ZIP/metadata validation path."""
from __future__ import annotations

from contextlib import redirect_stderr
import importlib.util
import io
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile


MODULE = Path(__file__).resolve().parents[1] / "github-packages.py"
SPEC = importlib.util.spec_from_file_location("curl_re2c_packages", MODULE)
assert SPEC and SPEC.loader
packages = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packages)
VERSION = "4.6.4"
PACKAGE = "Qigao.Re2c.Binary"
BASE = "https://nuget.pkg.github.com/qigao/download"
NUSPEC = "Qigao.Re2c.Binary.nuspec"
BINARY = "tools/linux-x64/bin/re2c"
SYNTAX = "tools/linux-x64/share/re2c/stdlib/syntax/c"
CATEGORIES = "tools/linux-x64/share/re2c/stdlib/unicode_categories.re"
PROPERTIES = "tools/linux-x64/share/re2c/stdlib/unicode_properties.re"


class LocalClient:
    """Only transport is replaced; no metadata, hashing or ZIP checks are mocked."""

    def __init__(self, archive):
        self.archive = archive
        self.downloads = []
        self.index_reads = []

    def json(self, url):
        self.index_reads.append(url)
        if url != "https://nuget.pkg.github.com/qigao/index.json":
            raise AssertionError("re2c must never consult a package version listing")
        return {"resources": [{"@type": "PackageBaseAddress/3.0.0", "@id": BASE}]}

    def download(self, url, destination, accept="application/json", allow_not_found=False):
        if allow_not_found:
            raise AssertionError("re2c download must not tolerate a missing version")
        self.downloads.append(url)
        shutil.copyfile(self.archive, destination)
        return True


class ExactRe2cPackage(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.environment = self.folder / "github-env"
        self.search_path = self.folder / "github-path"
        self.environment.write_text("PREEXISTING=value\n", encoding="utf-8")
        self.search_path.write_text("/preexisting/bin\n", encoding="utf-8")
        self.env = mock.patch.dict(os.environ, {
            "RUNNER_OS": "Linux", "RUNNER_ARCH": "X64",
            "GITHUB_ENV": str(self.environment), "GITHUB_PATH": str(self.search_path),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.destination = self.folder / "restored"

    def make_package(self, *, identity=PACKAGE, version=VERSION, omit=(), extra=(), metadata=None):
        nuspec = metadata or (
            f"<package><metadata><id>{identity}</id><version>{version}</version>"
            "</metadata></package>")
        entries = [(NUSPEC, nuspec.encode()), (BINARY, b"\x7fELFfixture"), (SYNTAX, b"syntax\n"),
                   (CATEGORIES, b"categories\n"), (PROPERTIES, b"properties\n")]
        archive = self.folder / "input.nupkg"
        with zipfile.ZipFile(archive, "w") as target:
            for name, data in entries + list(extra):
                if name not in omit:
                    target.writestr(name, data)
        return archive

    def feed(self, archive):
        return packages.NugetFeed(LocalClient(archive))

    def unchanged_outputs(self):
        self.assertEqual(self.environment.read_text(), "PREEXISTING=value\n")
        self.assertEqual(self.search_path.read_text(), "/preexisting/bin\n")

    def reject(self, archive, *, version=VERSION, digest=None, message=None):
        feed = self.feed(archive)
        with mock.patch.object(packages.subprocess, "run") as execute:
            with self.assertRaisesRegex(ValueError, message or ".+"):
                packages.restore_re2c(feed, self.destination, version,
                                      digest if digest is not None else packages.sha256(archive))
            execute.assert_not_called()
        self.assertFalse(self.destination.exists())
        self.unchanged_outputs()
        return feed

    def test_exact_identity_and_digest_precede_execution_and_exports(self):
        archive = self.make_package()
        digest = packages.sha256(archive)
        feed = self.feed(archive)

        def execute(command, *, check):
            self.assertTrue(check)
            self.assertEqual(command[1:], ["--version"])
            executable = Path(command[0])
            self.assertEqual(executable.read_bytes(), b"\x7fELFfixture")
            self.assertTrue(executable.stat().st_mode & 0o111)
            self.assertFalse(self.destination.exists())
            self.unchanged_outputs()
            return subprocess.CompletedProcess(command, 0)

        with mock.patch.object(packages.subprocess, "run", side_effect=execute) as runner:
            packages.restore_re2c(feed, self.destination, VERSION, digest.upper())
            self.assertEqual(runner.call_count, 1)
        self.assertEqual(feed.client.downloads, [
            f"{BASE}/qigao.re2c.binary/{VERSION}/qigao.re2c.binary.{VERSION}.nupkg"])
        root = self.destination / "package/tools/linux-x64"
        self.assertEqual((root / "bin/re2c").read_bytes(), b"\x7fELFfixture")
        self.assertEqual(self.environment.read_text(),
                         f"PREEXISTING=value\nRE2C_ROOT={root.as_posix()}\n"
                         f"RE2C_PACKAGE_VERSION={VERSION}\nRE2C_PACKAGE_SHA256={digest}\n")
        self.assertEqual(self.search_path.read_text(), f"/preexisting/bin\n{root.as_posix()}/bin\n")

    def test_wrong_digest_rejected_before_zip_parsing(self):
        archive = self.make_package()
        with mock.patch.object(packages.zipfile, "ZipFile") as parse:
            self.reject(archive, digest="0" * 64, message="SHA-256 mismatch")
            parse.assert_not_called()

    def test_wrong_id_or_version_even_with_matching_digest(self):
        for identity, version in (("Untrusted.Re2c", VERSION), (PACKAGE, "4.6.3")):
            with self.subTest(identity=identity, version=version):
                self.reject(self.make_package(identity=identity, version=version),
                            message="identity mismatch")

    def test_duplicate_identity_metadata_rejected(self):
        self.reject(self.make_package(metadata=(
            "<package><metadata><id>Untrusted</id><id>Qigao.Re2c.Binary</id>"
            f"<version>{VERSION}</version></metadata></package>")), message="identity mismatch")

    def test_missing_unicode_data_is_not_filled_from_existing_host(self):
        for missing in (SYNTAX, CATEGORIES, PROPERTIES):
            with self.subTest(missing=missing):
                self.reject(self.make_package(omit=(missing,)), message="missing re2c package file")

    def test_incomplete_other_host_payload_rejected_before_any_extract(self):
        self.reject(self.make_package(extra=(("tools/windows-x64/bin/re2c.exe", b"MZfixture"),)),
                    message="missing re2c package file")

    def test_path_traversal_at_end_of_archive_does_not_materialize_earlier_files(self):
        for name in ("../escaped", "/absolute", "tools/../../escaped", "tools\\escaped"):
            with self.subTest(name=name):
                self.reject(self.make_package(extra=((name, b"untrusted"),)), message="unsafe")
                self.assertFalse((self.folder / "escaped").exists())
                self.assertFalse(list(self.folder.glob("verified-re2c-*")))

    def test_symlink_special_file_and_parent_file_rejected(self):
        for mode in (stat.S_IFLNK | 0o777, stat.S_IFIFO | 0o644):
            with self.subTest(mode=mode):
                link = zipfile.ZipInfo("tools/linux-x64/link")
                link.create_system = 3
                link.external_attr = mode << 16
                self.reject(self.make_package(extra=((link, b"../bin/re2c"),)))
        self.reject(self.make_package(extra=(("tools/linux-x64/bin", b"file"),)),
                    message="file used as re2c package directory")

    def test_windows_sanitized_member_names_are_rejected_on_every_host(self):
        for character in '<>"|?*':
            with self.subTest(character=character):
                self.reject(self.make_package(extra=((f"tools/linux-x64/a{character}b", b"data"),)),
                            message="unsafe re2c package member")

    def test_windows_device_aliases_are_rejected_on_every_host(self):
        aliases = ("COM1", "COM¹", "COM².txt", "COM³", "LPT1", "LPT¹",
                   "LPT².txt", "LPT³", "CONIN$", "CONOUT$")
        for alias in aliases:
            with self.subTest(alias=alias):
                self.reject(self.make_package(extra=((f"tools/linux-x64/{alias}", b"data"),)),
                            message="unsafe re2c package member")

    def test_floating_and_noncanonical_versions_rejected_without_download(self):
        archive = self.make_package()
        for version in ("latest", "4.6.*", "4.6.4-*", "04.6.4", "", " 4.6.4"):
            with self.subTest(version=version):
                feed = self.reject(archive, version=version, message="exact three-component")
                self.assertFalse(feed.client.downloads)

    def test_invalid_digest_rejected_without_download(self):
        archive = self.make_package()
        for digest in ("", "0" * 63, "g" * 64, "sha256:" + "a" * 64):
            with self.subTest(digest=digest):
                feed = self.reject(archive, digest=digest, message="exact package SHA-256")
                self.assertFalse(feed.client.downloads)

    def test_execution_failure_publishes_neither_destination_nor_environment(self):
        archive = self.make_package()
        with mock.patch.object(packages.subprocess, "run",
                               side_effect=subprocess.CalledProcessError(1, ["re2c", "--version"])):
            with self.assertRaises(subprocess.CalledProcessError):
                packages.restore_re2c(self.feed(archive), self.destination, VERSION,
                                      packages.sha256(archive))
        self.assertFalse(self.destination.exists())
        self.unchanged_outputs()

    def test_preexisting_payload_is_not_reused_or_overwritten(self):
        archive = self.make_package()
        self.destination.mkdir()
        sentinel = self.destination / "sentinel"
        sentinel.write_text("keep")
        with self.assertRaisesRegex(ValueError, "must not already exist"):
            packages.restore_re2c(self.feed(archive), self.destination, VERSION,
                                  packages.sha256(archive))
        self.assertEqual(sentinel.read_text(), "keep")
        self.unchanged_outputs()

    def test_unavailable_host_has_no_architecture_fallback(self):
        archive = self.make_package()
        with mock.patch.dict(os.environ, {"RUNNER_ARCH": "X86"}):
            feed = self.reject(archive, message="unsupported re2c runner host")
        self.assertFalse(feed.client.downloads)

    def test_missing_selected_rid_does_not_use_another_payload(self):
        with mock.patch.dict(os.environ, {"RUNNER_OS": "macOS", "RUNNER_ARCH": "X64"}):
            self.reject(self.make_package(), message="missing re2c package file: tools/macos-x64")

    def test_cli_requires_both_lock_arguments_before_authentication(self):
        for extra in ([], ["--version", VERSION], ["--sha256", "a" * 64]):
            with self.subTest(extra=extra), redirect_stderr(io.StringIO()):
                with mock.patch.object(packages, "Curl") as client:
                    with mock.patch("sys.argv", ["github-packages.py", "re2c",
                                                 str(self.destination), *extra]):
                        with self.assertRaises(SystemExit) as error:
                            packages.main()
                        self.assertEqual(error.exception.code, 2)
                    client.assert_not_called()
                self.unchanged_outputs()


if __name__ == "__main__":
    unittest.main()
