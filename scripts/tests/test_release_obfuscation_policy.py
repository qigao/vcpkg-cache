#!/usr/bin/env python3
"""Fail-closed policy tests, not a claim of successful obfuscator execution."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import pathlib
import struct
import tempfile
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
BUILDER_SCRIPT = ROOT / "scripts" / "ci" / "build_llvm_obfuscator_candidate.py"
BUILDER_SPEC = importlib.util.spec_from_file_location("source_built_llvm_plugin", BUILDER_SCRIPT)
assert BUILDER_SPEC and BUILDER_SPEC.loader
builder = importlib.util.module_from_spec(BUILDER_SPEC)
BUILDER_SPEC.loader.exec_module(builder)


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

    def test_llvm_release_verifier_checks_elf_and_macho_machines(self):
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "native"
            path.write_bytes(bytes.fromhex("7f454c46") + bytes((2, 1)) +
                             bytes(12) + struct.pack("<H", 183) + bytes(44))
            self.assertEqual(proof.binary_machine(path), ("ELF", 183))
            path.write_bytes(bytes.fromhex("cffaedfe") +
                             struct.pack("<I", 0x0100000c) + bytes(56))
            self.assertEqual(proof.binary_machine(path),
                             ("Mach-O", 0x0100000c))
            path.write_bytes(bytes(64))
            with self.assertRaisesRegex(proof.GateError, "not an expected"):
                proof.binary_machine(path)

    def test_llvm_plugin_is_a_real_host_shared_library(self):
        with tempfile.TemporaryDirectory() as temporary:
            lib = pathlib.Path(temporary) / "LLVMObfuscator"
            elf = bytearray(64)
            elf[:4] = bytes.fromhex("7f454c46")
            elf[4] = 2
            elf[5] = 1
            struct.pack_into("<H", elf, 16, 3)  # ET_DYN
            struct.pack_into("<H", elf, 18, 183)  # Linux AArch64
            lib.write_bytes(elf)
            proof.check_host_plugin_image(lib, "linux-arm64")
            with self.assertRaisesRegex(proof.GateError, "host plugin machine"):
                proof.check_host_plugin_image(lib, "linux-x64")
            struct.pack_into("<H", elf, 16, 2)  # ET_EXEC
            lib.write_bytes(elf)
            with self.assertRaisesRegex(proof.GateError, "ET_DYN"):
                proof.check_host_plugin_image(lib, "linux-arm64")

            macho = bytearray(64)
            macho[:4] = bytes.fromhex("cffaedfe")
            struct.pack_into("<I", macho, 4, 0x0100000c)
            struct.pack_into("<I", macho, 12, 6)  # MH_DYLIB
            lib.write_bytes(macho)
            proof.check_host_plugin_image(lib, "macos-arm64")
            struct.pack_into("<I", macho, 12, 2)  # MH_EXECUTE
            lib.write_bytes(macho)
            with self.assertRaisesRegex(proof.GateError, "MH_DYLIB"):
                proof.check_host_plugin_image(lib, "macos-arm64")

    def test_source_plugin_builder_has_exact_scope_and_no_release_fallback(self):
        with tempfile.TemporaryDirectory() as scratch:
            candidate = argparse.Namespace(
                llvm_root=pathlib.Path(scratch) / "missing",
                output=pathlib.Path(scratch) / "output",
                host="linux-x64", target="linux-x64")
            with self.assertRaisesRegex(
                    builder.CandidateError, "existing absolute pinned installation"):
                builder.validate_inputs(candidate)
            candidate.host = "macos-x64"
            candidate.target = "macos-x64"
            with self.assertRaisesRegex(
                    builder.CandidateError, "no approved native host"):
                builder.validate_inputs(candidate)

    def test_candidate_proof_requires_host_native_execution(self):
        with tempfile.TemporaryDirectory() as scratch:
            base = pathlib.Path(scratch)
            args = argparse.Namespace(
                compiler_family="llvm-native", host="linux-x64",
                target="macos-arm64", require_native=True,
                candidate_plugin_manifest=base / "nonexistent.json")
            with self.assertRaisesRegex(proof.GateError, "matching-host native LLVM"):
                proof.verify(args)

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

    def test_llvm_mingw_release_with_host_candidate_remains_unqualified(self):
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(
                self.data(), "Release", "llvm-mingw", "linux-arm64", "windows-arm64")

    def test_native_llvm_release_without_evidence_fails_closed(self):
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(
                self.data(), "Release", "llvm-native", "linux-x64", "linux-x64")

    def test_all_native_llvm_platforms_are_selected_and_fail_closed(self):
        for platform in ("linux-x64", "linux-arm64", "macos-x64", "macos-arm64"):
            for mode in ("Release", "MinSizeRel", "RelWithDebInfo"):
                with self.subTest(platform=platform, mode=mode):
                    block = ("compiler distribution not SHA256-pinned"
                             if platform == "macos-x64"
                             else "not qualified" if platform.startswith("linux-")
                             else "plugin host artifact not SHA256-pinned")
                    with self.assertRaisesRegex(module.PolicyError, block):
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

    def test_official_native_llvm_archive_receipts_are_locked(self):
        source = self.data()["sources"]["llvm-native"]
        self.assertEqual(source["source_commit"],
                         "7a941dfb2877a0b8cf30323fefa85ad019e0b0f5")
        self.assertEqual(source["distribution"], "pinned")
        self.assertEqual({a["host"] for a in source["assets"]},
                         {"linux-x64", "linux-arm64", "macos-arm64"})
        self.assertEqual(len({a["sha256"] for a in source["assets"]}), 3)

    def test_pinned_linux_x64_host_plugin_remains_a_candidate_not_release(self):
        data = self.data()
        assets = data["sources"]["obfuscator-llvm"]["host_plugin_assets"]
        candidate = next(x for x in assets if x["host"] == "linux-x64")
        self.assertEqual(candidate["sha256"],
                         "25d60344fd90d80ce31f1578e4195ef154c28bf768c22a43dc3d7c2b845ea86a")
        self.assertEqual(candidate["candidate_artifact_id"], 12993687562)
        self.assertIs(candidate["release_qualified"], False)
        module.validate_contract(data)
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(data, "Release", "llvm-native",
                                  "linux-x64", "linux-x64")

    def test_pinned_linux_arm64_host_plugin_is_native_and_candidate_only(self):
        data = self.data()
        assets = data["sources"]["obfuscator-llvm"]["host_plugin_assets"]
        candidate = next(x for x in assets if x["host"] == "linux-arm64")
        self.assertEqual(candidate["sha256"],
                         "0866756e4f08058c1d407feff59ac55172aea357f7348c7bacda6dee34a8334b")
        self.assertEqual(candidate["compiler_archive_sha256"],
                         "9b27cf263d711aa6ebfd4045ab241d947bd09b3cd19ffa5728f48a80c9eb3a91")
        self.assertEqual(candidate["candidate_artifact_id"], 12994358091)
        self.assertEqual(candidate["qualification"], "source-built-candidate-only")
        self.assertIs(candidate["release_qualified"], False)
        module.validate_contract(data)
        with self.assertRaisesRegex(module.PolicyError, "not qualified"):
            module.select_profile(data, "Release", "llvm-native",
                                  "linux-arm64", "linux-arm64")

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
        data["sources"]["obfuscator-llvm"]["host_plugin_assets"] = []
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
