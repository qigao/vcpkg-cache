"""Protect the concrete pack -> two host checks -> same-package publish graph."""
from pathlib import Path
import re
import unittest


WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/re2c-tools-package.yml"


def policy_errors(text):
    # These assertions deliberately accept only this workflow's explicit job
    # layout. They are not a general YAML parser; GitHub still validates YAML.
    jobs = {}
    for name in ("linux", "pack", "linux-compatibility", "publish"):
        match = re.search(r"^  " + re.escape(name) + r":\n(.*?)(?=^  [\w-]+:|\Z)",
                          text, flags=re.M | re.S)
        if not match:
            return [f"missing explicit {name} job"]
        jobs[name] = match[1]
    errors = []

    def require(job, line):
        if not re.search(r"^\s*" + re.escape(line) + r"\s*$", jobs[job], flags=re.M):
            errors.append(f"{job} must retain: {line}")

    require("linux", "runs-on: ubuntu-22.04")
    require("linux", "-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++")
    require("pack", "needs: [linux, linux-arm64, macos, windows]")
    require("linux-compatibility", "needs: pack")
    require("linux-compatibility", "os: [ubuntu-22.04, ubuntu-24.04]")
    require("linux-compatibility", "runs-on: ${{ matrix.os }}")
    require("linux-compatibility", "fail-fast: false")
    require("publish", "needs: [pack, linux-compatibility]")
    require("publish", "if: github.event_name == 'workflow_dispatch' && inputs.publish == true")
    for job in ("linux-compatibility", "publish"):
        require(job, "name: re2c-binary-nuget")
        require(job, "sha256sum --check dist/SHA256SUMS")
    if "packaging/re2c/verify_linux_package.py" not in jobs["linux-compatibility"]:
        errors.append("both hosts must execute the actual packed payload")
    if '--expected-host "${{ matrix.os }}"' not in jobs["linux-compatibility"]:
        errors.append("both jobs must verify the actual Ubuntu release")
    if '".github/actions/setup-re2c-tools/**"' in text:
        errors.append("reader pin changes must not rebuild immutable package versions")
    if "--skip-duplicate" in text:
        errors.append("a duplicate version must fail")
    if re.search(r"continue-on-error:\s*true", text):
        errors.append("package qualification failures cannot be ignored")
    if re.search(r"\b(?:dotnet pack|cmake --build)\b", jobs["publish"]):
        errors.append("publish cannot rebuild the tested artifact")
    if text.count("dotnet pack ") != 1:
        errors.append("the workflow must pack exactly once")
    if "dotnet nuget push " in jobs["pack"]:
        errors.append("pack cannot publish before compatibility jobs")
    return errors


class WorkflowTests(unittest.TestCase):
    def test_actual_workflow_requires_both_hosts_before_publishing(self):
        self.assertEqual(policy_errors(WORKFLOW.read_text()), [])

    def test_lost_host_or_dependency_is_rejected(self):
        text = WORKFLOW.read_text()
        for before, after in (
            ("needs: [pack, linux-compatibility]", "needs: [pack]"),
            ("os: [ubuntu-22.04, ubuntu-24.04]", "os: [ubuntu-24.04]"),
            ("if: github.event_name == 'workflow_dispatch' && inputs.publish == true", "if: always()"),
        ):
            with self.subTest(before=before):
                self.assertTrue(policy_errors(text.replace(before, after)))

    def test_rebuild_duplicate_skip_and_ignored_failure_are_rejected(self):
        text = WORKFLOW.read_text()
        for addition in ("dotnet pack another.csproj", "cmake --build another",
                         "dotnet nuget push another.nupkg --skip-duplicate",
                         "continue-on-error: true"):
            with self.subTest(addition=addition):
                self.assertTrue(policy_errors(text + "          " + addition + "\n"))

    def test_unchecked_artifact_is_rejected(self):
        text = WORKFLOW.read_text()
        self.assertTrue(policy_errors(text.replace("sha256sum --check dist/SHA256SUMS", "true")))


if __name__ == "__main__":
    unittest.main()
