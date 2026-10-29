#!/usr/bin/env python3
"""Read-only qualification of Core's observed ARM64 dependency graph.

This has no upload operation. A 404 records unavailability to the current
workflow token, never proof that an immutable package was not published.
The separate fresh-runner binary-only job remains mandatory.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "cache-contracts/salts-core-arm64"
LOCK_SHA256 = "aa2bcd509ae4266813b7097048bfa5ef184fbb51c40874314684082b30b38b79"
TOOL_VERSION_SOURCE = (
    "https://github.com/microsoft/vcpkg-tool/blob/"
    "98d7cb0cf1f4686a3e43aa5672b6230c1d56bce8/src/vcpkg/tools.cpp#L1069-L1193")
SPEC = importlib.util.spec_from_file_location(
    "core_arm64_native_payload", ROOT / "scripts/publish-vcpkg-curl-cache.py")
assert SPEC and SPEC.loader
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "duplicate proof JSON key: " + key)
        value[key] = item
    return value


def load_contract(directory=CONTRACT):
    raw = (directory / "source-lock.json").read_bytes()
    require(hashlib.sha256(raw).hexdigest() == LOCK_SHA256,
            "Core ARM64 source lock differs from the reviewed exact inputs")
    lock = json.loads(raw, object_pairs_hook=unique_object)
    for name, expected in lock["product"]["files"].items():
        content = (directory / name).read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
        require(actual == expected, "Core manifest original bytes changed: " + name)
    return lock


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def verify_infrastructure(infrastructure):
    lock = load_contract()
    identity = lock["infrastructure"]
    require(run("git", "-C", str(infrastructure), "rev-parse", "HEAD") == identity["commit"],
            "ABI infrastructure is not the exact Core consumer pin")
    # Do not substitute repository-wide text-attribute cleanliness for the ABI
    # contract. Bind executable helpers by raw Git bytes and actual overlays by
    # the canonical computation that produced the consumer's cache identity.
    for name in ("setup-vcpkg-curl-cache.py", "cache-contract-revision.py",
                 "vcpkg-required-commits.py", "github-packages.py", "restore-manifest-cache.py"):
        relative = "scripts/" + name
        expected = subprocess.check_output(
            ["git", "-C", str(infrastructure), "show", identity["commit"] + ":" + relative])
        require((infrastructure / relative).read_bytes() == expected,
                "pinned infrastructure executable changed: " + relative)
    revision = run(sys.executable, str(infrastructure / "scripts/cache-contract-revision.py"),
                   str(infrastructure))
    require(revision == identity["contract_revision"], "actual infrastructure contract differs")
    return identity


def tree_bytes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}


def effective_vcpkg_environment(environment=None):
    env = dict(os.environ if environment is None else environment)
    for key in ("VCPKG_FORCE_SYSTEM_BINARIES", "VCPKG_FORCE_DOWNLOADED_BINARIES"):
        require(env.get(key) == "1", "original ARM64 bootstrap environment differs: " + key)
    # The pinned tool reports cached tools as version "0" when this variable
    # exists, even with FORCE_DOWNLOADED=1. Keep the same downloaded tools but
    # retain real version detection on every install invocation. Setting "0"
    # would not work: vcpkg checks variable presence, not its value.
    del env["VCPKG_FORCE_SYSTEM_BINARIES"]
    return env


def run_vcpkg_install(arguments, environment=None):
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    require(arguments[:1] == ["install"], "proof tool execution is limited to vcpkg install")
    env = effective_vcpkg_environment(environment)
    return subprocess.run([str(Path(env["VCPKG_ROOT"]) / "vcpkg"), *arguments],
                          env=env, check=False).returncode


def verify_inputs(infrastructure, environment=None):
    lock = load_contract()
    env = os.environ if environment is None else environment
    identity = verify_infrastructure(infrastructure)
    expected = {
        "RUNNER_OS": "Linux", "RUNNER_ARCH": "ARM64",
        "VCPKG_CACHE_CONTRACT_VERSION": identity["contract_version"],
        "VCPKG_CACHE_REVISION": identity["contract_revision"],
        "VCPKG_SCRIPTS_REVISION": identity["scripts_revision"],
        "VCPKG_TOOL_REVISION": identity["tool_revision"],
        "VCPKG_FORCE_SYSTEM_BINARIES": "1", "VCPKG_FORCE_DOWNLOADED_BINARIES": "1",
        "RE2C_PACKAGE_VERSION": lock["re2c"]["version"],
        "RE2C_PACKAGE_SHA256": lock["re2c"]["sha256"],
    }
    for key, value in expected.items():
        require(env.get(key) == value, "Core consumer tool environment differs: " + key)
    require(not env.get("X_VCPKG_NUGET_ID_PREFIX"), "Core consumer uses unprefixed package IDs")
    scripts = Path(env["VCPKG_ROOT"])
    require(run("git", "-C", str(scripts), "rev-parse", "HEAD") == identity["scripts_revision"],
            "actual vcpkg scripts differ from Core's fixed scripts")
    tool = run(str(scripts / "vcpkg"), "version").splitlines()[0]
    require(tool.removeprefix("vcpkg package management program version ") == identity["tool_revision"],
            "actual vcpkg executable version differs")
    assets = Path(env["VCPKG_CACHE_REPOSITORY_ROOT"])
    for variable, directory in (("VCPKG_OVERLAY_PORTS", "ports"),
                                ("VCPKG_OVERLAY_TRIPLETS", "triplets")):
        require(env.get(variable) == (assets / directory).as_posix(),
                "unexpected ABI overlay path: " + variable)
        require(tree_bytes(assets / directory) == tree_bytes(infrastructure / directory),
                "actual ABI overlay bytes differ: " + directory)
    effective = effective_vcpkg_environment(env)
    return {"scope": "read-only-source-proof", "product": lock["product"],
            "infrastructure": identity, "bootstrap_environment": expected,
            "effective_vcpkg_environment": {key: effective[key] for key in expected if key in effective},
            "tool_environment_correction": {
                "removed_variable": "VCPKG_FORCE_SYSTEM_BINARIES",
                "reason": "Preserve real versions of the same downloaded tools on repeated install invocations",
                "implementation_source": TOOL_VERSION_SOURCE,
                "observed_failure": "https://github.com/qigao/vcpkg-cache/actions/runs/40852469213/job/123375098434",
            },
            "cc": run("cc", "--version"), "cxx": run("c++", "--version"),
            "re2c": run(str(Path(env["RE2C_ROOT"]) / "bin/re2c"), "--version")}


def verify_plan(path):
    lock = load_contract()
    require(path.is_file() and path.stat().st_size <= 1_048_576,
            "missing or unbounded canonical packages.config")
    root = ET.parse(path).getroot()
    require(root.tag == "packages" and not root.attrib,
            "only vcpkg-generated packages.config is admissible")
    packages = {}
    seen = set()
    for node in root:
        require(node.tag == "package" and set(node.attrib) == {"id", "version"},
                "unexpected canonical plan entry")
        name, version = node.attrib["id"], node.attrib["version"]
        require(name.casefold() not in seen, "duplicate or ambiguous package ID")
        seen.add(name.casefold())
        packages[name] = version
    expected = lock["observed_package_versions"]
    require(set(packages) == set(expected),
            "Core ARM64 plan must contain the exact observed 14-package graph")
    for name, version in expected.items():
        require(packages[name] == version,
                f"Core ARM64 ABI mismatch for {name}: {packages[name]} != {version}")
    return packages


def probe(output, feed=None):
    """Collect GET-only observations; unavailability is not publication admission."""
    lock = load_contract()
    require(not output.exists(), "remote observation directory must be fresh")
    output.mkdir(parents=True)
    feed = feed or native.packages.NugetFeed(native.packages.Curl())
    results = []
    report = {"scope": "upstream-workflow-token-observation-only", "packages": results,
              "all_available": False,
              "unavailable_meaning": "HTTP 404: absent version or token access not granted; unresolved"}
    try:
        for name, version in lock["target_packages"].items():
            path = output / (name + ".nupkg")
            if not feed.package(name, version, path, allow_not_found=True):
                results.append({"id": name, "version": version,
                                "status": "unavailable_to_workflow_token_404"})
                continue
            archive = native.packages.cache_package(path, name, version, output / "downloaded-cache")
            native.identify_source(archive, name, version)
            results.append({"id": name, "version": version, "status": "available",
                            "nupkg_sha256": native.packages.sha256(path),
                            "payload_sha256": native.entries_digest(archive)})
        report["all_available"] = all(row["status"] == "available" for row in results)
    finally:
        write_json(output / "availability.json", report)
    return report


def cache_receipt(plan, cache, compare=None):
    lock = load_contract()
    packages = verify_plan(plan)
    artifacts = []
    expected_paths = set()
    for name, version in sorted(packages.items()):
        abi = version.rsplit("-vcpkg", 1)[1]
        archive = cache / abi[:2] / (abi + ".zip")
        require(not archive.is_symlink() and archive.resolve().is_relative_to(cache.resolve()),
                "cache artifact escaped its independent cache root")
        native.identify_source(archive, name, version)
        expected_paths.add(archive.resolve())
        artifacts.append({"id": name, "version": version,
                          "zip_sha256": native.packages.sha256(archive),
                          "payload_sha256": native.entries_digest(archive)})
    require({p.resolve() for p in cache.rglob("*.zip")} == expected_paths,
            "unplanned package in the bounded Core source cache")
    receipt = {"schema": 1, "scope": "cache-payload-proof-not-publication-admission",
               "producer_commit": run("git", "-C", str(ROOT), "rev-parse", "HEAD"),
               "workflow_run": os.environ.get("GITHUB_RUN_ID"), "lock_sha256": LOCK_SHA256,
               "product": lock["product"], "infrastructure": lock["infrastructure"],
               "packages": artifacts}
    if compare:
        source = json.loads(compare.read_bytes(), object_pairs_hook=unique_object)
        for key in ("schema", "scope", "producer_commit", "workflow_run", "lock_sha256",
                    "product", "infrastructure"):
            require(source.get(key) == receipt[key], "source proof identity differs: " + key)
        expected = {(row["id"], row["version"]): row for row in source["packages"]}
        require(len(expected) == len(source["packages"]) == len(artifacts),
                "source proof contains missing or duplicate package payloads")
        require(set(expected) == set(packages.items()), "source proof package graph differs")
        differences = []
        for row in artifacts:
            previous = expected[(row["id"], row["version"])]
            require(all(isinstance(previous.get(key), str) and
                        re.fullmatch(r"[0-9a-f]{64}", previous[key])
                        for key in ("payload_sha256", "zip_sha256")),
                    "source proof payload digest is missing or malformed")
            if previous["payload_sha256"] != row["payload_sha256"]:
                differences.append({"id": row["id"], "version": row["version"],
                                    "source_payload_sha256": previous["payload_sha256"],
                                    "readback_payload_sha256": row["payload_sha256"],
                                    "source_cache_zip_sha256": previous["zip_sha256"],
                                    "readback_cache_zip_sha256": row["zip_sha256"]})
        # Same ABI does not promise byte-reproducible rebuilds of an existing
        # package. Preserve differences as reproducibility diagnostics, distinct
        # from exact ABI availability. The privileged publisher separately keeps
        # its immutable-version payload conflict gate; this cannot approve it.
        receipt["source_payload_comparison"] = {
            "scope": "reproducibility-observation-not-publication-admission",
            "status": "different" if differences else "identical",
            "matching_package_count": len(artifacts) - len(differences),
            "different_packages": differences,
        }
    return receipt


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    item = commands.add_parser("infrastructure")
    item.add_argument("--infrastructure", type=Path, required=True)
    item = commands.add_parser("inputs")
    item.add_argument("--infrastructure", type=Path, required=True)
    item.add_argument("--output", type=Path, required=True)
    item = commands.add_parser("probe")
    item.add_argument("--output", type=Path, required=True)
    item = commands.add_parser("plan")
    item.add_argument("--plan", type=Path, required=True)
    item = commands.add_parser("vcpkg-install")
    item.add_argument("arguments", nargs=argparse.REMAINDER)
    item = commands.add_parser("cache")
    item.add_argument("--plan", type=Path, required=True)
    item.add_argument("--cache", type=Path, required=True)
    item.add_argument("--output", type=Path, required=True)
    item.add_argument("--compare", type=Path)
    args = parser.parse_args()
    if args.command == "vcpkg-install":
        raise SystemExit(run_vcpkg_install(args.arguments))
    elif args.command == "infrastructure":
        result = verify_infrastructure(args.infrastructure)
    elif args.command == "inputs":
        result = verify_inputs(args.infrastructure)
        write_json(args.output, result)
    elif args.command == "probe":
        result = probe(args.output)
    elif args.command == "plan":
        result = {"scope": "exact-source-plan-only", "packages": verify_plan(args.plan)}
    else:
        result = cache_receipt(args.plan, args.cache, args.compare)
        write_json(args.output, result)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
