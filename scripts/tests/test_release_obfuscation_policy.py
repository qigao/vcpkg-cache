#!/usr/bin/env python3
"""Fail-closed policy tests, not a claim of successful obfuscator execution."""
from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "ci" / "validate_release_obfuscation.py"
SPEC = importlib.util.spec_from_file_location("release_obfuscation_validator", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class ReleaseObfuscationPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = json.loads(
            (ROOT / "compiler-contracts" / "release-obfuscation.json").read_text(encoding="utf-8")
        )

    def data(self):
        return copy.deepcopy(self.original)

    def test_contract_is_well_formed(self):
        module.validate_contract(self.data())

    def test_debug_does_not_require_obfuscator(self):
        self.assertIsNone(module.select_profile(
            self.data(), "Debug", "", "", ""))

    def test_relwithdebinfo_is_a_protected_release_variant(self):
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(
                self.data(), "RelWithDebInfo", "llvm-mingw", "windows-x64", "windows-x64")

    def test_tinycc_release_without_evidence_fails_closed(self):
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(
                self.data(), "Release", "tinycc-builder", "windows-x64", "windows-x64")

    def test_llvm_mingw_release_without_evidence_fails_closed(self):
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(
                self.data(), "Release", "llvm-mingw", "linux-x64", "windows-arm64")

    def test_native_llvm_release_without_evidence_fails_closed(self):
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(
                self.data(), "Release", "llvm-native", "linux-x64", "linux-x64")

    def test_tinycc_arm64_release_is_explicitly_denied(self):
        with self.assertRaisesRegex(module.PolicyError, "only claims Windows x86/x64"):
            module.select_profile(
                self.data(), "Release", "tinycc-builder", "windows-x64", "windows-arm64")

    def test_no_fallback_to_unknown_compiler(self):
        with self.assertRaises(module.PolicyError):
            module.select_profile(
                self.data(), "Release", "gcc", "linux-x64", "linux-x64")

    def test_no_fallback_to_unknown_target(self):
        with self.assertRaises(module.PolicyError):
            module.select_profile(
                self.data(), "Release", "llvm-native", "linux-x64", "android-arm64")

    def test_release_archive_hash_is_mandatory(self):
        data = self.data()
        data["sources"]["llvm-mingw"]["assets"][0]["sha256"] = ""
        with self.assertRaisesRegex(module.PolicyError, "SHA256"):
            module.validate_contract(data)

    def test_source_pin_is_mandatory(self):
        data = self.data()
        data["sources"]["obfus-h"]["source_commit"] = "main"
        with self.assertRaisesRegex(module.PolicyError, "40 lowercase hex"):
            module.validate_contract(data)

    def test_llvm_pass_pipeline_cannot_be_empty(self):
        data = self.data()
        data["sources"]["obfuscator-llvm"]["required_passes"] = {}
        with self.assertRaisesRegex(module.PolicyError, "nonempty"):
            module.validate_contract(data)

    def test_disabling_obfus_h_fails(self):
        data = self.data()
        data["sources"]["obfus-h"]["options"]["OBFH_DISABLE_ANY_OBFUSCATION"] = 1
        with self.assertRaisesRegex(module.PolicyError, "disabling is forbidden"):
            module.validate_contract(data)

    def test_unqualified_cannot_be_marked_qualified_without_proof(self):
        data = self.data()
        data["profiles"][0]["qualification"] = "qualified"
        with self.assertRaisesRegex(module.PolicyError, "cannot admit Release"):
            module.validate_contract(data)

    def test_tinycc_arm64_cannot_be_added_as_profile(self):
        data = self.data()
        bad = dict(data["profiles"][0])
        bad.update(id="tinycc-windows-arm64", target="windows-arm64")
        data["profiles"].append(bad)
        with self.assertRaises(module.PolicyError):
            module.validate_contract(data)

    def test_cross_compiler_abi_alias_is_rejected(self):
        data = self.data()
        data["sources"]["llvm-mingw"]["crt"] = "msvcrt"
        with self.assertRaisesRegex(module.PolicyError, "UCRT ABI"):
            module.validate_contract(data)

    def test_unsupported_host_missing_archive_is_rejected(self):
        data = self.data()
        data["profiles"].append(dict(
            id="llvm-mingw-windows-missing-arm64-host",
            compiler="llvm-mingw",
            obfuscator="obfuscator-llvm",
            host="windows-arm64",
            target="windows-x64",
            qualification="pending",
            evidence=[],
        ))
        # This one has an archive and is valid as a candidate: toolchain host and
        # target architecture are intentionally independent.
        module.validate_contract(data)
        data["sources"]["llvm-mingw"]["assets"] = [
            a for a in data["sources"]["llvm-mingw"]["assets"] if a["host"] != "windows-arm64"
        ]
        with self.assertRaisesRegex(module.PolicyError, "compiler archive not pinned"):
            module.validate_contract(data)


if __name__ == "__main__":
    unittest.main()
