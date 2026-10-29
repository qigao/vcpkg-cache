"""Offline validation of manually requested exact native NuGet publication."""
from pathlib import Path
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/ci/verify-native-publish-target.py"
SPEC = importlib.util.spec_from_file_location("exact_native_publish_target", SOURCE)
assert SPEC and SPEC.loader
contract = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(contract)

PROOF_SPEC = importlib.util.spec_from_file_location(
    "core_arm64_source_proof", ROOT / "scripts/ci/core-arm64-cache-source-proof.py")
assert PROOF_SPEC and PROOF_SPEC.loader
proof = importlib.util.module_from_spec(PROOF_SPEC)
PROOF_SPEC.loader.exec_module(proof)

ABI = "a" * 64
VERSION = "1.0.42-vcpkg" + ABI


def plan(path, pairs):
    root = ET.Element("packages")
    for name, version in pairs:
        ET.SubElement(root, "package", id=name, version=version)
    ET.ElementTree(root).write(path, encoding="utf-8")
    return path


class ManualNativePublisherTargetTests(unittest.TestCase):
    def verify(self, file, expected_version=VERSION,
               package_set="wabt", expected_id="wabt_x64-linux"):
        return contract.verify(
            file, package_set=package_set,
            expected_id=expected_id, expected_version=expected_version,
        )

    def test_canonical_target_and_exact_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            file = plan(Path(directory) / "config", [
                ("vcpkg-cmake_x64-linux", "2024.4.23-vcpkg" + "b" * 64),
                ("wabt_x64-linux", VERSION),
            ])
            self.assertEqual(self.verify(file)[-1], ("wabt_x64-linux", VERSION))

    def test_missing_or_different_native_hash_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            file = plan(Path(directory) / "config", [("wabt_x64-linux", VERSION)])
            for bad in ("", "1.0.42", "1.0.42-vcpkg" + "b" * 63):
                with self.subTest(version=bad):
                    with self.assertRaisesRegex(ValueError, "full immutable"):
                        self.verify(file, expected_version=bad)
            with self.assertRaisesRegex(ValueError, "target mismatch"):
                self.verify(file, expected_version="1.0.42-vcpkg" + "b" * 64)

    def test_only_selected_id_is_authorized(self):
        with tempfile.TemporaryDirectory() as directory:
            file = plan(Path(directory) / "config", [("wabt_x64-linux", VERSION)])
            with self.assertRaisesRegex(ValueError, "does not match"):
                self.verify(file, expected_id="simde_x64-linux")
            with self.assertRaisesRegex(ValueError, "does not match"):
                self.verify(file, package_set="simde")
            with self.assertRaisesRegex(ValueError, "unapproved"):
                self.verify(file, package_set="other")
            # Read-only Core qualification never expands the privileged writer.
            with self.assertRaisesRegex(ValueError, "unapproved"):
                self.verify(file, package_set="salts-core-arm64")

    def test_duplicate_missing_or_unsafe_plan_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "config"
            cases = [
                ([], "empty"),
                ([("simde_x64-linux", VERSION)], "target mismatch"),
                ([("wabt_x64-linux", VERSION), ("wabt_x64-linux", VERSION)], "duplicate"),
                ([("wabt_x64-linux", VERSION), ("WABT_x64-linux", VERSION)], "duplicate"),
                ([("../unsafe", VERSION)], "floating"),
            ]
            for entries, message in cases:
                with self.subTest(entries=entries):
                    plan(file, entries)
                    with self.assertRaisesRegex(ValueError, message):
                        self.verify(file)

    def test_unbounded_xml_and_wrong_root_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "config"
            file.write_text("<untrusted/>")
            with self.assertRaisesRegex(ValueError, "canonical"):
                self.verify(file)
            plan(file, [("wabt_x64-linux", VERSION)])
            with mock.patch.object(contract, "MAX_PLAN_SIZE", 1):
                with self.assertRaisesRegex(ValueError, "unbounded"):
                    self.verify(file)

    def test_protected_stage_rechecks_sha_attested_package_plan(self):
        src = (ROOT / ".github/workflows/curl-only-vcpkg-producer.yml").read_text()
        producer, publisher = src.split("\n  native-publish:", 1)
        self.assertIn("expected_native_id:", producer)
        self.assertIn("expected_native_version:", producer)
        self.assertIn("DO_PUBLISH:", producer)
        self.assertIn("scripts/ci/verify-native-publish-target.py", producer)
        self.assertIn("sha256sum packages.config source-proof.txt", producer)
        self.assertIn("scripts/ci/verify-native-publish-target.py", publisher)
        self.assertIn("sha256sum --check --status SHA256SUMS", publisher)
        self.assertIn("environment: native-cache-publish", publisher)
        self.assertEqual(src.count("packages: write"), 1)


class CoreArm64SourceProofTests(unittest.TestCase):
    """Offline tamper fixtures are not evidence of a native source build."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.lock = proof.load_contract()

    def write_plan(self, pairs=None):
        return plan(self.root / "packages.config", (
            self.lock["observed_package_versions"].items() if pairs is None else pairs))

    def make_cache(self, changed=None):
        cache = self.root / "cache"
        for name, version in self.lock["observed_package_versions"].items():
            abi = version.rsplit("-vcpkg", 1)[1]
            archive = cache / abi[:2] / (abi + ".zip")
            archive.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(archive, "w") as target:
                target.writestr("CONTROL", "Package: " + name.removesuffix("_arm64-linux") +
                                "\nArchitecture: arm64-linux\nAbi: " + abi + "\n")
                target.writestr("BUILD_INFO", "fixture-only\n")
                target.writestr("lib/fixture", b"changed" if name == changed else b"fixture")
        return cache

    def test_original_core_bytes_and_reviewed_lock_cannot_drift(self):
        target = self.root / "contract"
        shutil.copytree(proof.CONTRACT, target)
        proof.load_contract(target)
        for filename in ("vcpkg.json", "vcpkg-configuration.json", "source-lock.json"):
            path = target / filename
            original = path.read_bytes()
            path.write_bytes(original + b" ")
            with self.subTest(file=filename), self.assertRaisesRegex(ValueError, "bytes changed|source lock"):
                proof.load_contract(target)
            path.write_bytes(original)

    def test_full_graph_and_every_failed_abi_are_required(self):
        expected = self.lock["observed_package_versions"]
        self.assertEqual(proof.verify_plan(self.write_plan()), expected)
        for name in self.lock["target_packages"]:
            wrong = {**expected, name: expected[name][:-1] + ("0" if expected[name][-1] != "0" else "1")}
            with self.subTest(package=name), self.assertRaisesRegex(ValueError, "ABI mismatch"):
                proof.verify_plan(self.write_plan(wrong.items()))
        for pairs in (
            list(expected.items())[:-1],
            [*expected.items(), ("unexpected_arm64-linux", VERSION)],
            [(name.replace("arm64-linux", "x64-linux"), version) for name, version in expected.items()],
        ):
            with self.subTest(pairs=pairs), self.assertRaisesRegex(ValueError, "14-package"):
                proof.verify_plan(self.write_plan(pairs))
        first = next(iter(expected.items()))
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            proof.verify_plan(self.write_plan([*expected.items(), (first[0].upper(), first[1])]))

    def test_actual_infrastructure_helpers_and_contract_are_verified(self):
        infrastructure = self.root / "infrastructure"
        originals = {}
        for name in ("setup-vcpkg-curl-cache.py", "cache-contract-revision.py",
                     "vcpkg-required-commits.py", "github-packages.py", "restore-manifest-cache.py"):
            relative = "scripts/" + name
            path = infrastructure / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            originals[relative] = ("# exact reviewed helper " + name + "\n").encode()
            path.write_bytes(originals[relative])
        identity = self.lock["infrastructure"]

        def git_object(arguments):
            return originals[arguments[-1].split(":", 1)[1]]

        with mock.patch.object(proof.subprocess, "check_output", side_effect=git_object):
            with mock.patch.object(proof, "run", side_effect=[identity["commit"], identity["contract_revision"]]):
                proof.verify_infrastructure(infrastructure)
            helper = infrastructure / "scripts/setup-vcpkg-curl-cache.py"
            saved = helper.read_bytes()
            helper.write_bytes(saved + b"# unrelated checkout cannot lend executable bytes\n")
            with mock.patch.object(proof, "run", return_value=identity["commit"]):
                with self.assertRaisesRegex(ValueError, "executable changed"):
                    proof.verify_infrastructure(infrastructure)
            helper.write_bytes(saved)
            with mock.patch.object(proof, "run", side_effect=[identity["commit"], "0" * 64]):
                with self.assertRaisesRegex(ValueError, "actual infrastructure contract differs"):
                    proof.verify_infrastructure(infrastructure)

    def test_404_observation_does_not_claim_absent_publication_or_success(self):
        feed = mock.Mock()
        feed.package.return_value = False
        result = proof.probe(self.root / "observation", feed)
        self.assertFalse(result["all_available"])
        self.assertEqual({(r["id"], r["version"]) for r in result["packages"]},
                         set(self.lock["target_packages"].items()))
        self.assertEqual({r["status"] for r in result["packages"]},
                         {"unavailable_to_workflow_token_404"})
        self.assertIn("token access", result["unavailable_meaning"])
        self.assertEqual(feed.package.call_count, 4)

    def test_http_or_payload_error_cannot_be_recorded_as_available(self):
        feed = mock.Mock()
        feed.package.side_effect = OSError("request failed")
        output = self.root / "observation"
        with self.assertRaises(OSError):
            proof.probe(output, feed)
        self.assertFalse(json.loads((output / "availability.json").read_text())["all_available"])

    def test_source_identity_and_reproducibility_diagnostics_are_distinct(self):
        config = self.write_plan()
        cache = self.make_cache()
        original = proof.cache_receipt(config, cache)
        saved = self.root / "source.json"
        saved.write_text(json.dumps(original))
        same = proof.cache_receipt(config, cache, saved)
        self.assertEqual(same["source_payload_comparison"]["status"], "identical")
        self.make_cache(changed="libyuv_arm64-linux")
        comparison = proof.cache_receipt(config, cache, saved)["source_payload_comparison"]
        self.assertEqual(comparison["status"], "different")
        self.assertEqual(comparison["matching_package_count"], 13)
        self.assertEqual([r["id"] for r in comparison["different_packages"]], ["libyuv_arm64-linux"])
        difference = comparison["different_packages"][0]
        self.assertNotEqual(difference["source_payload_sha256"], difference["readback_payload_sha256"])
        self.assertIn("not-publication-admission", comparison["scope"])
        self.make_cache()
        malformed = json.loads(json.dumps(original))
        malformed["packages"][0]["payload_sha256"] = "unverified"
        saved.write_text(json.dumps(malformed))
        with self.assertRaisesRegex(ValueError, "payload digest"):
            proof.cache_receipt(config, cache, saved)
        saved.write_text(json.dumps({**original, "producer_commit": "0" * 40}))
        with self.assertRaisesRegex(ValueError, "source proof identity"):
            proof.cache_receipt(config, cache, saved)
        saved.write_text(json.dumps({**original, "workflow_run": "previous-run"}))
        with self.assertRaisesRegex(ValueError, "source proof identity"):
            proof.cache_receipt(config, cache, saved)

    def test_missing_source_zip_or_forged_control_never_qualifies(self):
        config = self.write_plan()
        cache = self.make_cache()
        first = next(iter(self.lock["target_packages"]))
        abi = self.lock["target_packages"][first].rsplit("-vcpkg", 1)[1]
        archive = cache / abi[:2] / (abi + ".zip")
        archive.unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            proof.cache_receipt(config, cache)
        with zipfile.ZipFile(archive, "w") as target:
            target.writestr("CONTROL", "Package: forged\nArchitecture: x64-linux\nAbi: " + abi + "\n")
            target.writestr("BUILD_INFO", "fixture-only\n")
        with self.assertRaisesRegex(ValueError, "CONTROL Package/Architecture"):
            proof.cache_receipt(config, cache)

    def test_proof_cli_has_no_upload_capability(self):
        output = self.root / "must-not-be-created"
        result = subprocess.run([sys.executable, "-B", str(PROOF_SPEC.origin), "probe",
                                 "--output", str(output), "--publish"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("unrecognized arguments: --publish", result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
