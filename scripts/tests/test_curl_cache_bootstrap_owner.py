"""The native curl transport must not rely on the deprecated Mono action."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / "setup-vcpkg-curl-cache.py"
SPEC = importlib.util.spec_from_file_location("canonical_curl_bootstrap", SOURCE)
assert SPEC and SPEC.loader
bootstrap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bootstrap)

NATIVE_FILES = (
    ".github/actions/setup-vcpkg-curl-cache/action.yml",
    "scripts/github-packages.py",
    "scripts/restore-manifest-cache.py",
    "scripts/setup-vcpkg-curl-cache.py",
    "scripts/windows_pkgconf.py",
    "scripts/setup-compiler-toolchain.py",
)


class CurlBootstrapOwnerContract(unittest.TestCase):
    def setup_fixture(self, root: Path):
        for path in NATIVE_FILES:
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("required native transport fixture\n", encoding="utf-8")

    def test_curl_bootstrap_survives_deleting_legacy_mono_action(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.setup_fixture(root)
            # The deprecated setup-vcpkg-cache/action.yml is absent.
            self.assertFalse((root / ".github/actions/setup-vcpkg-cache/action.yml").exists())
            bootstrap.require_native_curl_owner(root)

    def test_deprecated_action_is_not_accepted_as_curl_bootstrap(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            legacy = root / ".github/actions/setup-vcpkg-cache/action.yml"
            legacy.parent.mkdir(parents=True)
            legacy.write_text("old Mono/NuGet action\n")
            with self.assertRaisesRegex(ValueError, "setup-vcpkg-curl-cache/action.yml"):
                bootstrap.require_native_curl_owner(root)

    def test_every_native_package_client_file_is_mandatory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.setup_fixture(root)
            for name in NATIVE_FILES:
                file = root / name
                with self.subTest(path=name):
                    file.unlink()
                    with self.assertRaisesRegex(ValueError, "incomplete canonical curl-only"):
                        bootstrap.require_native_curl_owner(root)
                    file.write_text("required native transport fixture\n", encoding="utf-8")

    def test_real_repository_has_exact_native_owner(self):
        bootstrap.require_native_curl_owner(SOURCE.parents[1])


class WindowsCurlBootstrap(unittest.TestCase):
    def metadata(self, root: Path, tag: str = bootstrap.WINDOWS_TOOL_TAG):
        (root / "scripts").mkdir()
        (root / "scripts/vcpkg-tool-metadata.txt").write_text(
            f"VCPKG_TOOL_RELEASE_TAG={tag}\n", encoding="utf-8")

    def test_host_architecture_selects_exact_release_and_disables_metrics(self):
        for host, (asset, digest) in bootstrap.WINDOWS_TOOL_ASSETS.items():
            with self.subTest(host=host), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self.metadata(root)
                with mock.patch.object(bootstrap.downloads, "verified_download") as download:
                    bootstrap.bootstrap_windows_tool(root, bootstrap.WINDOWS_TOOL_VERSION, host)
                download.assert_called_once_with(
                    f"https://github.com/microsoft/vcpkg-tool/releases/download/{bootstrap.WINDOWS_TOOL_TAG}/{asset}",
                    root / "vcpkg.exe", digest, 16 * 1024 * 1024,
                )
                self.assertTrue((root / "vcpkg.disable-metrics").is_file())

    def test_tool_version_and_scripts_tag_must_both_match_the_hash_lock(self):
        for version, tag in (("unexpected-version", bootstrap.WINDOWS_TOOL_TAG),
                             (bootstrap.WINDOWS_TOOL_VERSION, "2099-01-01")):
            with self.subTest(version=version, tag=tag), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self.metadata(root, tag)
                with mock.patch.object(bootstrap.downloads, "verified_download") as download:
                    with self.assertRaises(ValueError):
                        bootstrap.bootstrap_windows_tool(root, version, "X64")
                download.assert_not_called()
                self.assertFalse((root / "vcpkg.disable-metrics").exists())

    def test_unknown_host_has_no_architecture_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.metadata(root)
            for host in ("", "X86", "AMD64", "x64"):
                with self.subTest(host=host), mock.patch.object(
                        bootstrap.downloads, "verified_download") as download:
                    with self.assertRaisesRegex(ValueError, "unsupported Windows vcpkg host"):
                        bootstrap.bootstrap_windows_tool(root, bootstrap.WINDOWS_TOOL_VERSION, host)
                    download.assert_not_called()

    def test_failed_download_does_not_mark_bootstrap_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.metadata(root)
            with mock.patch.object(bootstrap.downloads, "verified_download",
                                   side_effect=ValueError("SHA256 mismatch")):
                with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                    bootstrap.bootstrap_windows_tool(root, bootstrap.WINDOWS_TOOL_VERSION, "X64")
            self.assertFalse((root / "vcpkg.disable-metrics").exists())


if __name__ == "__main__":
    unittest.main()

