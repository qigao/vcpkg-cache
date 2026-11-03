"""Offline tests for Lemon's paired source, host architecture and package lock."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("lemon_package", Path(__file__).resolve().parents[2] / "packaging/lemon/package.py")
lemon = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lemon)


def host_binary(rid):
    data = bytearray(128)
    arch = rid.rsplit("-", 1)[1]
    if rid.startswith("linux-"):
        data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", data, 18, 62 if arch == "x64" else 183)
    elif rid.startswith("windows-"):
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 60, 64)
        data[64:68] = b"PE\x00\x00"
        struct.pack_into("<H", data, 68, 0x8664 if arch == "x64" else 0xAA64)
    else:
        data[:4] = b"\xcf\xfa\xed\xfe"
        struct.pack_into("<I", data, 4, 0x01000007 if arch == "x64" else 0x0100000C)
    return data


class LemonPackageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.root = self.work / "package"
        template = self.work / "lempar.c"
        template.write_text("paired parser template\n")
        lock = copy.deepcopy(lemon.LOCK)
        lock["files"]["lempar.c"] = lemon.native.packages.sha256(template)
        patch = mock.patch.object(lemon, "LOCK", lock)
        patch.start()
        self.addCleanup(patch.stop)
        for rid in lemon.RIDS:
            root = self.root / "tools" / rid
            (root / "bin").mkdir(parents=True)
            (root / "share/lemon").mkdir(parents=True)
            binary = root / "bin" / lemon.executable(rid)
            binary.write_bytes(host_binary(rid))
            (root / "share/lemon/lempar.c").write_bytes(template.read_bytes())
            (root / "share/lemon/source.json").write_text(json.dumps(lemon.manifest(rid, binary)))

    def test_complete_six_host_package_is_deterministic_and_lock_verifies(self):
        first = lemon.pack(self.root, self.work / "one")
        second = lemon.pack(self.root, self.work / "two")
        self.assertEqual(first.read_bytes(), second.read_bytes())
        lemon.verify_archive(first, first.parent / "lemon.lock.json")
        lock = json.loads((first.parent / "lemon.lock.json").read_text())
        self.assertEqual(lock["sha256"], lemon.native.packages.sha256(first))

    def test_missing_host_or_extra_payload_is_not_packed(self):
        member = self.root / "tools/windows-arm64/bin/lemon.exe"
        data = member.read_bytes()
        member.unlink()
        with self.assertRaisesRegex(ValueError, "exactly all six"):
            lemon.pack(self.root, self.work / "dist")
        member.write_bytes(data)
        (self.root / "unreviewed.dll").write_bytes(b"unexpected")
        with self.assertRaisesRegex(ValueError, "exactly all six"):
            lemon.pack(self.root, self.work / "dist")

    def test_template_and_executable_cannot_be_mixed_between_pairs_or_architectures(self):
        root = self.root / "tools/linux-x64"
        template = root / "share/lemon/lempar.c"
        original = template.read_bytes()
        template.write_bytes(b"different template")
        with self.assertRaisesRegex(ValueError, "mixed Lemon template"):
            lemon.validate_root(root, "linux-x64")
        template.write_bytes(original)
        binary = root / "bin/lemon"
        binary.write_bytes(host_binary("linux-arm64"))
        with self.assertRaisesRegex(ValueError, "architecture"):
            lemon.validate_root(root, "linux-x64")

    def test_binary_mutation_is_rejected_even_when_architecture_is_unchanged(self):
        root = self.root / "tools/linux-x64"
        with (root / "bin/lemon").open("ab") as out:
            out.write(b"changed bytes")
        with self.assertRaisesRegex(ValueError, "pair metadata"):
            lemon.validate_root(root, "linux-x64")

    def test_publish_requires_trusted_manual_master_event(self):
        with mock.patch.dict("os.environ", {"GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF": "refs/pull/1/merge"}):
            with self.assertRaisesRegex(ValueError, "trusted manual master"):
                lemon.publish(self.work / "absent.nupkg", self.work / "absent.lock")


if __name__ == "__main__":
    unittest.main()
