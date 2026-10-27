"""Offline tests for the native ABI NuGet producer: no remote writes ever."""
from __future__ import annotations
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "native_cache_curl_publisher", ROOT / "publish-vcpkg-curl.py")
assert SPEC and SPEC.loader
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)
ABI = "a" * 64
VERSION = "1.2.3-vcpkg" + ABI
NAME = "simde_x64-linux"


def synthetic_files_cache(root: Path, package="simde", arch="x64-linux",
                          abi=ABI):
    cache = root / "cache"
    source = cache / abi[:2] / (abi + ".zip")
    source.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("CONTROL", f"Package: {package}\nArchitecture: {arch}\nVersion: 1.2.3\nAbi: {abi}\n")
        z.writestr("BUILD_INFO", "CRTLinkage: dynamic\n")
        z.writestr("include/simde/simde.h", b"native header bytes\n")
    return cache


def manifest(path: Path, items):
    root = ET.Element("packages")
    for name, version in items:
        ET.SubElement(root, "package", id=name, version=version)
    ET.ElementTree(root).write(path, encoding="utf-8")
    return path


class NativeCurlPublisherTest(unittest.TestCase):
    def test_offline_pack_and_binary_cache_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(
            os.environ, {"X_VCPKG_NUGET_ID_PREFIX": ""}
        ):
            base = Path(tmp)
            cache = synthetic_files_cache(base)
            target = base / "dist" / (NAME + "." + VERSION + ".nupkg")
            result = publisher.pack_archive(cache, NAME, VERSION, target)
            self.assertEqual(result, target)
            self.assertTrue(target.is_file())
            with zipfile.ZipFile(target) as archive:
                publisher.package_metadata(archive, NAME, VERSION)
                self.assertEqual(archive.read("include/simde/simde.h"),
                                 b"native header bytes\n")
                self.assertIn("[Content_Types].xml", archive.namelist())
                self.assertIn("_rels/.rels", archive.namelist())
                self.assertIn(NAME + ".nuspec", archive.namelist())
                # OPC content types must cover extensionless native ABI metadata
                # and every ordinary payload extension, not only NuGet files.
                types = ET.fromstring(archive.read("[Content_Types].xml"))
                defaults = {x.attrib["Extension"]: x.attrib["ContentType"]
                            for x in types if x.tag.endswith("Default")}
                overrides = {x.attrib["PartName"] for x in types
                             if x.tag.endswith("Override")}
                self.assertEqual(defaults["h"], "application/octet")
                self.assertEqual(defaults["rels"],
                    "application/vnd.openxmlformats-package.relationships+xml")
                self.assertIn("/CONTROL", overrides)
                self.assertIn("/BUILD_INFO", overrides)
                for name in (NAME + ".nuspec", "[Content_Types].xml",
                             "_rels/.rels"):
                    self.assertEqual(archive.getinfo(name).date_time,
                                     (1980, 1, 1, 0, 0, 0))
            second = base / "dist" / "same-identity-second-run.nupkg"
            publisher.pack_archive(cache, NAME, VERSION, second)
            self.assertEqual(target.read_bytes(), second.read_bytes(),
                             "same exact native ABI must reproduce identical NuGet bytes")
            self.assertGreater(len(publisher.sha256(target)), 63)
            with self.assertRaisesRegex(ValueError, "existing producer"):
                publisher.pack_archive(cache, NAME, VERSION, target)

    def test_identical_abi_ignores_source_zip_order_timestamps_and_extras(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(
            os.environ, {"X_VCPKG_NUGET_ID_PREFIX": ""}
        ):
            base = Path(tmp)
            outputs = []
            payloads = {
                "CONTROL": (
                    f"Package: simde\nArchitecture: x64-linux\n"
                    f"Version: 1.2.3\nAbi: {ABI}\n").encode(),
                "BUILD_INFO": b"CRTLinkage: dynamic\n",
                "tools/simde/tool": b"#!/bin/sh\necho verified\n",
                "include/simde/simde.h": b"same header\n",
            }
            for run in range(2):
                cache = base / f"cache{run}"
                source = cache / ABI[:2] / (ABI + ".zip")
                source.parent.mkdir(parents=True)
                entries = list(payloads.items())
                if run:
                    entries.reverse()
                with zipfile.ZipFile(source, "w", zipfile.ZIP_DEFLATED) as z:
                    for name, payload in entries:
                        stamp = (2026, 10, 27, 12, 0, 0) if run else (
                            2001, 2, 3, 4, 5, 6)
                        entry = zipfile.ZipInfo(name, date_time=stamp)
                        entry.create_system = 3
                        entry.compress_type = zipfile.ZIP_STORED if run else zipfile.ZIP_DEFLATED
                        entry.external_attr = (
                            (0o100755 if name == "tools/simde/tool" else 0o100644)
                            << 16
                        )
                        if run:
                            entry.extra = b"\xfe\xca\x04\x00abcd"
                            entry.comment = b"local-build-timestamp"
                        z.writestr(entry, payload)
                destination = base / f"same-abi-{run}.nupkg"
                publisher.pack_archive(cache, NAME, VERSION, destination)
                outputs.append(destination)
            self.assertEqual(outputs[0].read_bytes(), outputs[1].read_bytes(),
                             "same native bytes and ABI must produce one NuGet digest")
            with zipfile.ZipFile(outputs[0]) as published:
                self.assertEqual(published.namelist()[:4], sorted(payloads))
                tool = published.getinfo("tools/simde/tool")
                self.assertEqual(tool.date_time, (1980, 1, 1, 0, 0, 0))
                self.assertEqual(tool.extra, b"")
                self.assertEqual(tool.comment, b"")
                self.assertEqual((tool.external_attr >> 16) & 0o111, 0o111)

    def test_multi_megabyte_native_library_preserves_exact_payload(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(
            os.environ, {"X_VCPKG_NUGET_ID_PREFIX": ""}
        ):
            base = Path(tmp)
            cache = synthetic_files_cache(base)
            native_zip = cache / ABI[:2] / (ABI + ".zip")
            payload = bytes(range(256)) * 16384  # 4 MiB, handled in 1 MiB chunks
            with zipfile.ZipFile(native_zip, "a", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("lib/libsample.a", payload)
            package = base / "native-library.nupkg"
            publisher.pack_archive(cache, NAME, VERSION, package)
            with zipfile.ZipFile(package) as archive:
                self.assertEqual(archive.getinfo("lib/libsample.a").file_size,
                                 len(payload))
                self.assertEqual(archive.read("lib/libsample.a"), payload)

    def test_opc_part_types_with_spaces_and_extensionless_paths(self):
        data = publisher.content_types_for_native_members([
            "CONTROL", "BUILD_INFO", "include/native.h",
            "docs/read me", "lib/libexample.so.2",
        ])
        root = ET.fromstring(data)
        defaults = {x.attrib["Extension"] for x in root
                    if x.tag.endswith("Default")}
        overrides = {x.attrib["PartName"] for x in root
                     if x.tag.endswith("Override")}
        self.assertTrue({"h", "2", "rels", "nuspec"} <= defaults)
        self.assertTrue({"/CONTROL", "/BUILD_INFO", "/docs/read%20me"} <= overrides)
        self.assertEqual(len(overrides), len(set(overrides)))

    def test_abi_prefix_and_wrong_control_must_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            cache = synthetic_files_cache(base)
            with mock.patch.dict(os.environ, {"X_VCPKG_NUGET_ID_PREFIX": "vcpkg-cache"}):
                publisher.pack_archive(cache, "vcpkg-cache_" + NAME, VERSION,
                                       base / "prefixed.nupkg")
                with self.assertRaisesRegex(ValueError, "CONTROL"):
                    publisher.pack_archive(cache, "cxxopts_x64-linux", VERSION,
                                           base / "wrong.nupkg")
            with mock.patch.dict(os.environ, {"X_VCPKG_NUGET_ID_PREFIX": ""}):
                with self.assertRaisesRegex(ValueError, "exact ID"):
                    publisher.pack_archive(cache, NAME, "1.2.3", base / "floating.nupkg")
                with self.assertRaisesRegex(ValueError, "exact ID"):
                    publisher.pack_archive(cache, "../evil", VERSION, base / "evil.nupkg")
                with self.assertRaisesRegex(ValueError, "missing exact"):
                    publisher.pack_archive(cache, NAME,
                                           "1.2.3-vcpkg" + "b" * 64,
                                           base / "missing.nupkg")

    def test_exact_package_config_must_be_nonempty(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            doc = manifest(base / "packages.config", [(NAME, VERSION)])
            self.assertEqual(list(publisher.requested_packages(doc)), [(NAME, VERSION)])
            doc = manifest(doc, [])
            with self.assertRaisesRegex(ValueError, "empty"):
                list(publisher.requested_packages(doc))
            doc = manifest(doc, [(NAME, VERSION), (NAME.upper(), VERSION)])
            with self.assertRaisesRegex(ValueError, "duplicate"):
                list(publisher.requested_packages(doc))
            doc = manifest(doc, [(NAME, "1.2.3")])
            with self.assertRaisesRegex(ValueError, "exact vcpkg"):
                list(publisher.requested_packages(doc))

    def test_upload_endpoint_must_be_single_trusted_package_publish(self):
        class Client:
            def __init__(self, resources):
                self.resources = resources
            def json(self, url):
                self.assertUrl = url
                return {"resources": self.resources}
        accepted = publisher.publisher_url(Client([
            {"@type": "PackagePublish/2.0.0",
             "@id": "https://nuget.pkg.github.com/qigao/"}
        ]))
        self.assertEqual(accepted, "https://nuget.pkg.github.com/qigao/")
        for url in ("http://nuget.pkg.github.com/qigao/",
                    "https://other.example/qigao/",
                    "https://nuget.pkg.github.com/eve/",
                    "https://user:password@nuget.pkg.github.com/qigao/"):
            with self.subTest(url=url):
                with self.assertRaisesRegex(ValueError, "unsafe"):
                    publisher.publisher_url(Client([{
                        "@type": "PackagePublish/2.0.0", "@id": url
                    }]))
        with self.assertRaisesRegex(ValueError, "one PackagePublish"):
            publisher.publisher_url(Client([]))

    def test_upload_uses_curl_form_without_token_on_argv(self):
        class Client:
            token = "fake-ci-token"
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "simde.nupkg"
            archive.write_bytes(b"fake but bounded")
            statuses = ["201", "202", "409", "400"]
            for expected in statuses:
                seen = []
                def fake_run(cmd, **kwargs):
                    seen.append((cmd, kwargs))
                    return subprocess.CompletedProcess(cmd, 0,
                        stdout=expected, stderr="")
                with mock.patch.object(publisher.subprocess, "run",
                                       side_effect=fake_run):
                    if expected == "400":
                        with self.assertRaisesRegex(ValueError, "rejected"):
                            publisher.push_new(Client(),
                                "https://nuget.pkg.github.com/qigao/", archive)
                    else:
                        self.assertEqual(publisher.push_new(Client(),
                             "https://nuget.pkg.github.com/qigao/", archive),
                             expected)
                self.assertEqual(len(seen), 1)
                args, options = seen[0]
                self.assertNotIn("fake-ci-token", repr(args))
                self.assertIn("fake-ci-token", options["input"])
                self.assertIn("form =", options["input"])
                self.assertIn("--config", args)

    def test_unauthorized_pull_request_cannot_publish(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(
            os.environ, {"GITHUB_EVENT_NAME": "pull_request",
                         "GITHUB_REPOSITORY": "qigao/vcpkg-cache"}
        ):
            base = Path(tmp)
            cache = synthetic_files_cache(base)
            config = manifest(base / "packages.config", [(NAME, VERSION)])
            args = ["publisher", "--packages-config", str(config),
                    "--cache", str(cache), "--output", str(base / "out"),
                    "--publish"]
            with mock.patch.object(publisher.sys, "argv", args):
                with mock.patch.object(publisher.subprocess, "run",
                                       side_effect=AssertionError("network forbidden")):
                    with self.assertRaisesRegex(ValueError, "untrusted PR"):
                        publisher.main()
            self.assertEqual(list((base / "out").glob("*.nupkg")).__len__(), 1)


if __name__ == "__main__":
    unittest.main()
