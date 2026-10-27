"""The native curl transport must not rely on the deprecated Mono action."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest


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


if __name__ == "__main__":
    unittest.main()
