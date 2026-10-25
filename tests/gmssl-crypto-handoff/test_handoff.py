"""Unit tests for exact GmSSL Crypto source classification and archive format."""
from __future__ import annotations

import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "tools" / "verify_gmssl_crypto_handoff.py"
SPEC = importlib.util.spec_from_file_location("gmssl_crypto_handoff", TOOL)
assert SPEC and SPEC.loader
handoff = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(handoff)


class HandoffContract(unittest.TestCase):
    def test_port_packaging_never_moves(self):
        for name in ("portfile.cmake", "vcpkg.json", "GmSSLConfig.cmake"):
            group, target = handoff.classify(name)
            self.assertEqual(group, "vcpkg-packaging")
            self.assertEqual(target, "vcpkg-cache/ports/gmssl/" + name)

    def test_preserve_patch_and_backport_relative_paths(self):
        cases = {
            "x509-compat.cmake": (
                "upstream-source-patch",
                "providers/gmssl/patches/x509-compat.cmake",
            ),
            "backports/secp384r1_verify.c": (
                "provider-source-backport",
                "providers/gmssl/patches/backports/secp384r1_verify.c",
            ),
            "aes_key_wrap.c": (
                "provider-source-backport",
                "providers/gmssl/patches/aes_key_wrap.c",
            ),
            "tests/fixtures/p384-ca-sha384.pem": (
                "provider-conformance",
                "providers/gmssl/tests/fixtures/p384-ca-sha384.pem",
            ),
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(handoff.classify(path), expected)

    def test_no_path_traversal_or_unclassified_file(self):
        for path in ("../outside", "tests/../../leak", "/absolute", "tests//weird.c", "notes.md"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                handoff.classify(path)

    def test_git_blob_identity_is_content_addressed(self):
        a = handoff.blob_sha(b"test\n")
        self.assertEqual(len(a), 40)
        self.assertNotEqual(a, handoff.blob_sha(b"test\r\n"))
        self.assertEqual(a, hashlib.sha1(b"blob 5\0test\n").hexdigest())

    def test_export_is_identical_and_relocation_safe(self):
        items = {
            "providers/gmssl/patches/x509-compat.cmake": b"abc\r\n",
            "providers/gmssl/tests/test.c": b"int main(void){return 0;}\n",
            "providers/gmssl/LICENSE": b"Apache-2.0\n",
        }
        first = handoff.deterministic_tar(items)
        second = handoff.deterministic_tar(items)
        self.assertEqual(first, second)
        with tarfile.open(fileobj=io.BytesIO(first), mode="r:gz") as tar:
            paths = tar.getnames()
            self.assertEqual(paths, sorted(items))
            for name in paths:
                self.assertEqual(tar.extractfile(name).read(), items[name])
                self.assertEqual(tar.getmember(name).mtime, 0)
                self.assertEqual(tar.getmember(name).uid, 0)


if __name__ == "__main__":
    unittest.main()
