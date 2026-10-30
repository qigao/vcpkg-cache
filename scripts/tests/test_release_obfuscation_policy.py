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

PROOF_SCRIPT = ROOT / "scripts" / "ci" / "verify_llvm_mingw_obfuscation.py"
PROOF_SPEC = importlib.util.spec_from_file_location("llvm_mingw_obfuscation_proof", PROOF_SCRIPT)
assert PROOF_SPEC and PROOF_SPEC.loader
proof = importlib.util.module_from_spec(PROOF_SPEC)
PROOF_SPEC.loader.exec_module(proof)


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

    def test_plugin_release_preflight_does_not_accept_an_unpinned_host(self):
        with self.assertRaisesRegex(proof.GateError, "no unique pinned"):
            proof.check_pin(self.data(), "windows-x64",
                            pathlib.Path("/nonexistent/LLVMObfuscator.dll"))

    def test_ir_proof_requires_a_real_compiler_function(self):
        self.assertIn("ret i32", proof.function_body(
            "define dso_local i32 @obf_probe(i32 %x) {\nentry:\n"
            "  ret i32 %x\n}\n"))
        with self.assertRaisesRegex(proof.GateError, "eliminated or renamed"):
            proof.function_body("declare i32 @obf_probe(i32)\n")

    def test_llvm_release_seed_policy(self):
        self.assertIsNotNone(proof.SEED.fullmatch(
            "0xA04252B187478C00A40BC6D81D1A8A52"))
        self.assertIsNone(proof.SEED.fullmatch("1234"))

    def test_debug_does_not_require_obfuscator(self):
        self.assertIsNone(module.select_profile(
            self.data(), "Debug", "", "", ""))

    def test_relwithdebinfo_is_a_protected_release_variant(self):
        with self.assertRaisesRegex(module.PolicyError, "plugin host artifact not SHA256-pinned"):
            module.select_profile(
                self.data(), "RelWithDebInfo", "llvm-mingw", "windows-x64", "windows-x64")

    def test_tinycc_release_without_evidence_fails_closed(self):
        with self.assertRaisesRegex(module.PolicyError, "requires llvm-mingw"):
            module.select_profile(
                self.data(), "Release", "tinycc-builder", "windows-x64", "windows-x64")

    def test_llvm_mingw_release_without_evidence_fails_closed(self):
        with self.assertRaisesRegex(module.PolicyError, "plugin host artifact not SHA256-pinned"):
            module.select_profile(
                self.data(), "Release", "llvm-mingw", "linux-arm64", "windows-arm64")

    def test_native_llvm_release_without_evidence_fails_closed(self):
        with self.assertRaisesRegex(module.PolicyError, "compiler distribution not SHA256-pinned"):
            module.select_profile(
                self.data(), "Release", "llvm-native", "linux-x64", "linux-x64")

    def test_all_native_llvm_platforms_are_selected_and_fail_closed(self):
        for platform in ("linux-x64", "linux-arm64", "macos-x64", "macos-arm64"):
            for mode in ("Release", "MinSizeRel", "RelWithDebInfo"):
                with self.subTest(platform=platform, mode=mode):
                    with self.assertRaisesRegex(
                            module.PolicyError, "compiler distribution not SHA256-pinned"):
                        module.select_profile(
                            self.data(), mode, "llvm-native", platform, platform)

    def test_gcc_is_never_native_release_backend(self):
        for platform in ("linux-x64", "linux-arm64", "macos-x64", "macos-arm64"):
            with self.subTest(platform=platform):
                with self.assertRaisesRegex(
                        module.PolicyError, "requires llvm-native"):
                    module.select_profile(
                        self.data(), "Release", "gcc", platform, platform)

    def test_appleclang_cannot_generate_mac_release(self):
        for platform in ("macos-x64", "macos-arm64"):
            with self.subTest(platform=platform):
                with self.assertRaisesRegex(
                        module.PolicyError, "requires llvm-native"):
                    module.select_profile(
                        self.data(), "Release", "appleclang", platform, platform)

    def test_gcc_and_appleclang_can_still_run_diagnostic_tests(self):
        for backend in ("gcc", "appleclang"):
            self.assertIsNone(module.select_profile(
                self.data(), "Debug", backend, "linux-arm64", "linux-arm64"))

    def test_native_llvm_archive_without_digest_is_rejected(self):
        data = self.data()
        data["sources"]["llvm-native"]["distribution"] = "pinned"
        data["sources"]["llvm-native"]["source_commit"] = "a" * 40
        data["sources"]["llvm-native"]["assets"] = [{
            "host": "linux-x64", "name": "llvm-23.1.4.tar.xz",
            "sha256": "fake",
        }]
        with self.assertRaisesRegex(module.PolicyError, "archive needs pinned"):
            module.validate_contract(data)

    def test_native_llvm_plugin_must_match_the_host_os(self):
        data = self.data()
        data["sources"]["obfuscator-llvm"]["host_plugin_assets"] = [{
            "host": "linux-arm64", "name": "LLVMObfuscator.dll",
            "sha256": "a"*64, "llvm_version": "23.1.4",
            "source_commit": data["sources"]["obfuscator-llvm"]["source_commit"],
        }]
        with self.assertRaisesRegex(module.PolicyError, "plugin needs locked"):
            module.validate_contract(data)

    def test_pinned_native_llvm_still_requires_matching_plugin(self):
        data = self.data()
        data["sources"]["llvm-native"]["distribution"] = "pinned"
        data["sources"]["llvm-native"]["source_commit"] = "b"*40
        data["sources"]["llvm-native"]["assets"] = [{
            "host": "linux-x64", "name": "llvm-23.1.4.tar.xz",
            "sha256": "c"*64,
        }]
        module.validate_contract(data)
        with self.assertRaisesRegex(
                module.PolicyError, "plugin host artifact not SHA256-pinned"):
            module.select_profile(data, "Release", "llvm-native",
                                  "linux-x64", "linux-x64")

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

    def test_windows_release_must_never_select_msvc(self):
        with self.assertRaisesRegex(module.PolicyError, "requires llvm-mingw"):
            module.select_profile(
                self.data(), "Release", "msvc", "windows-x64", "windows-arm64")

    def test_msvc_is_still_allowed_for_unprotected_debug(self):
        self.assertIsNone(module.select_profile(
            self.data(), "Debug", "msvc", "windows-x64", "windows-x64"))

    def test_no_unlocked_host_plugin_is_accepted(self):
        data = self.data()
        data["sources"]["obfuscator-llvm"]["host_plugin_assets"] = [{
            "host": "windows-x64", "name": "LLVMObfuscator.dll",
            "sha256": "fake", "llvm_version": "23.1.4",
            "source_commit": data["sources"]["obfuscator-llvm"]["source_commit"],
        }]
        with self.assertRaisesRegex(module.PolicyError, "plugin needs locked host binary"):
            module.validate_contract(data)

    def test_plugin_is_not_same_as_windows_target_arch(self):
        data = self.data()
        data["sources"]["obfuscator-llvm"]["host_plugin_assets"] = [{
            "host": "windows-x64", "name": "LLVMObfuscator.dll",
            "sha256": "a"*64, "llvm_version": "23.1.4",
            "source_commit": data["sources"]["obfuscator-llvm"]["source_commit"],
        }]
        module.validate_contract(data)
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(
                data, "Release", "llvm-mingw", "windows-x64", "windows-arm64")

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
