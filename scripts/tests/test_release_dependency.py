"""Release selection and immutable restore-input contract tests.

Run: python -m unittest discover -s scripts/tests -v
"""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import shutil
import zipfile


spec = importlib.util.spec_from_file_location(
    "restore_native_dependency", Path(__file__).resolve().parents[1] / "restore-native-dependency.py")
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class ReleaseClient:
    def __init__(self, release):
        self.release = release
        self.urls = []

    def json(self, url):
        self.urls.append(url)
        return self.release


class ReleaseDependencyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.descriptor = self.root / "dependency.json"
        self.output = self.root / "build" / "dependency.lock.json"
        self.source = {"schema": 1, "source": {"kind": "github-release",
            "repository": "qigao/vcpkg-cache", "version_env": "VCPKG_CACHE_VERSION",
            "asset": "installed-${VCPKG_TARGET_TRIPLET}.tar.xz"}}
        self.environment = {"VCPKG_CACHE_VERSION": "0.1.2", "VCPKG_TARGET_TRIPLET": "x64-linux"}
        self.asset = {"name": "installed-x64-linux.tar.xz", "size": 42,
            "browser_download_url": "https://github.com/qigao/vcpkg-cache/releases/download/v0.1.2/installed-x64-linux.tar.xz",
            "digest": "sha256:" + "a" * 64}
        self.release = {"tag_name": "v0.1.2", "draft": False,
            "published_at": "2026-11-01T00:00:00Z", "assets": [self.asset]}

    def resolve(self):
        self.descriptor.write_text(json.dumps(self.source), encoding="utf-8")
        self.client = ReleaseClient(self.release)
        return restore.resolve_release(argparse.Namespace(
            descriptor=str(self.descriptor), output_lock=str(self.output)),
            client=self.client, environment=self.environment)

    def test_exact_version_and_publisher_digest_become_literal_lock(self):
        lock = self.resolve()
        self.assertEqual(self.client.urls, ["https://api.github.com/repos/qigao/vcpkg-cache/releases/tags/v0.1.2"])
        self.assertEqual(lock, {"schema": 1, "source": {"kind": "url",
            "url": self.asset["browser_download_url"]}, "sha256": "a" * 64})
        self.assertEqual(json.loads(self.output.read_text()), lock)
        self.assertEqual(json.loads(self.descriptor.read_text()), self.source)
        # Existing locked restore accepts the result without a new source protocol.
        args = restore.parser().parse_args(["locked", str(self.output), "--destination", str(self.root / "sdk")])
        restore.validate_request(args)
        self.assertEqual(restore.source_descriptor(args), lock["source"])

    def test_version_change_changes_the_restore_identity(self):
        first = self.resolve()
        self.environment["VCPKG_CACHE_VERSION"] = "0.1.3"
        self.release["tag_name"] = "v0.1.3"
        self.asset["browser_download_url"] = self.asset["browser_download_url"].replace("v0.1.2", "v0.1.3")
        self.asset["digest"] = "sha256:" + "b" * 64
        second = self.resolve()
        self.assertNotEqual(first, second)
        self.assertEqual(second["sha256"], "b" * 64)

    def test_missing_empty_floating_and_prefixed_versions_fail(self):
        for value in (None, "", "latest", "0.1", "v0.1.2", "0.1.2\n"):
            with self.subTest(value=value):
                self.environment.pop("VCPKG_CACHE_VERSION", None)
                if value is not None:
                    self.environment["VCPKG_CACHE_VERSION"] = value
                with self.assertRaisesRegex(ValueError, "VCPKG_CACHE_VERSION"):
                    self.resolve()
                self.assertFalse(self.output.exists())

    def test_missing_or_unsafe_asset_environment_fails(self):
        for value in (None, "", "../escape", "x64-linux?query"):
            with self.subTest(value=value):
                self.environment.pop("VCPKG_TARGET_TRIPLET", None)
                if value is not None:
                    self.environment["VCPKG_TARGET_TRIPLET"] = value
                with self.assertRaises(ValueError):
                    self.resolve()

    def test_invalid_release_metadata_preserves_previous_lock(self):
        self.resolve()
        original = self.output.read_bytes()
        mutations = [
            {"draft": True}, {"published_at": None}, {"tag_name": "v0.1.3"},
            {"assets": []}, {"assets": [self.asset, self.asset]},
        ]
        baseline = copy.deepcopy(self.release)
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.release = {**baseline, **mutation}
                with self.assertRaises(ValueError):
                    self.resolve()
                self.assertEqual(self.output.read_bytes(), original)

    def test_invalid_digest_size_or_url_fails(self):
        baseline = copy.deepcopy(self.asset)
        for mutation in ({"digest": None}, {"digest": "sha256:bad"},
                         {"size": 0}, {"size": True},
                         {"browser_download_url": "https://example.com/sdk.tar.xz"}):
            with self.subTest(mutation=mutation):
                self.release["assets"] = [{**baseline, **mutation}]
                with self.assertRaises(ValueError):
                    self.resolve()
                self.assertFalse(self.output.exists())

    def test_descriptor_cannot_be_overwritten(self):
        self.output = self.descriptor
        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.resolve()
        self.assertEqual(json.loads(self.descriptor.read_text()), self.source)

    def test_locked_restore_does_not_implicitly_resolve_a_descriptor(self):
        self.descriptor.write_text(json.dumps(self.source))
        args = restore.parser().parse_args(["download", str(self.descriptor), "--destination", str(self.root / "blobs")])
        with self.assertRaisesRegex(ValueError, "unsupported locked source"):
            restore.download_locked(args)

    def test_new_release_restores_separately_and_rejects_old_receipt(self):
        archive = self.root / "sdk.zip"
        self.source["source"]["asset"] = "sdk.zip"
        self.asset["name"] = "sdk.zip"

        def select(version, content):
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr("sdk/identity.txt", content)
            self.environment["VCPKG_CACHE_VERSION"] = version
            self.release["tag_name"] = "v" + version
            self.asset.update(size=archive.stat().st_size,
                digest="sha256:" + restore.packages.sha256(archive),
                browser_download_url=f"https://github.com/qigao/vcpkg-cache/releases/download/v{version}/sdk.zip")
            self.resolve()

        def install(destination):
            args = restore.parser().parse_args(["locked", str(self.output),
                "--destination", str(destination), "--payload", "sdk",
                "--require", "identity.txt", "--reuse"])
            return restore.restore(args, download=lambda url, target, digest, **kwargs: shutil.copyfile(archive, target))

        old = self.root / "old"
        select("0.1.2", "release one")
        install(old)
        select("0.1.3", "release two")
        with self.assertRaisesRegex(ValueError, "does not match"):
            install(old)
        receipt = install(self.root / "new")
        self.assertEqual((old / "payload/sdk/identity.txt").read_text(), "release one")
        self.assertEqual((Path(receipt["root"]) / "identity.txt").read_text(), "release two")


if __name__ == "__main__":
    unittest.main()
