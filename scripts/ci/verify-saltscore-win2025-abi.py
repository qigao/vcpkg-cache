#!/usr/bin/env python3
"""Verify one exact SaltsCore Windows2025 x64-windows native ABI closure.

Source-build provenance and publish/read-back are separate workflow jobs.
Never derive a package ABI from its port version or silently allow fallback.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "cache-contracts/saltscore-win2025/expected-abi.json"
FROZEN_FIXTURE_BLOB = "4368ee20b560fee71866ef1be910f8ec7f6a67d6"
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
NATIVE_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+-vcpkg([0-9a-f]{64})\Z")
NATIVE_ID = re.compile(r"[a-z0-9-]+_x64-windows\Z")


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for block in iter(lambda: fp.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def contract(path: Path = FIXTURE) -> dict:
    raw = path.read_bytes().replace(b"\r\n", b"\n")
    if blob_sha(raw) != FROZEN_FIXTURE_BLOB:
        raise ValueError("SaltsCore 9-package expected ABI fixture altered")
    obj = json.loads(raw)
    if obj.get("schema_version") != 1:
        raise ValueError("unexpected ABI contract schema")
    if obj.get("source", {}).get("repository") != "qigao/salts-core":
        raise ValueError("unexpected source repository")
    if obj.get("cache", {}).get("repository") != "qigao/vcpkg-cache":
        raise ValueError("unexpected cache repository")
    if obj["source"]["feature"] != "cnet":
        raise ValueError("unexpected feature")
    if obj["target"] != {
        "runner": "windows-2025", "triplet": "x64-windows",
        "host_triplet": "x64-windows", "vs_version": "18.11.1",
        "vctools_version": "14.51.36231"
    }:
        raise ValueError("wrong native compiler/triplet")
    packages = obj.get("packages", [])
    if len(packages) != 9 or len({p["id"] for p in packages}) != 9:
        raise ValueError("require all nine unique original Windows package IDs")
    if any(not NATIVE_ID.fullmatch(p["id"]) or
           not NATIVE_VERSION.fullmatch(p["version"]) for p in packages):
        raise ValueError("invalid native package ID/ABI")
    if (obj["cache"].get("contract_version") != "8" or
            obj["cache"].get("source_commit") !=
            "7bb5b556a001bc82d2922a04a718e986a7f47f54"):
        raise ValueError("changed canonical source cache contract")
    return obj


def validate_plan(path: Path, expected: dict) -> list[tuple[str, str]]:
    if not path.is_file() or path.stat().st_size > 1_048_576:
        raise ValueError("missing/unbounded vcpkg-generated ABI plan")
    root = ET.parse(path).getroot()
    if root.tag != "packages" or root.attrib:
        raise ValueError("expected canonical packages.config")
    items: list[tuple[str, str]] = []
    for node in root:
        if node.tag != "package" or set(node.attrib) != {"id", "version"}:
            raise ValueError("invalid package entry in canonical plan")
        k, v = node.attrib["id"], node.attrib["version"]
        if not NATIVE_ID.fullmatch(k) or not NATIVE_VERSION.fullmatch(v):
            raise ValueError("invalid package ID or unqualified ABI version")
        items.append((k, v))
    source = [(p["id"], p["version"]) for p in expected["packages"]]
    if len(items) != 9 or len(set(items)) != 9 or sorted(items) != sorted(source):
        raise ValueError("Windows ABI plan differs from exact 9-package consumer evidence")
    return sorted(items)


def verify_product_source(source: Path, expected: dict) -> None:
    original = expected["source"]
    if not (source / ".git").exists():
        raise ValueError("exact SaltsCore source checkout missing")
    actual_sha = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
    ).strip()
    if actual_sha != original["commit"]:
        raise ValueError("SaltsCore checkout HEAD differs from admitted consumer")
    for name, required in (
        ("vcpkg.json", original["manifest_blob"]),
        ("vcpkg-configuration.json", original["registry_blob"]),
    ):
        if blob_sha((source / name).read_bytes().replace(b"\r\n", b"\n")) != required:
            raise ValueError(f"source manifest/registry changed: {name}")


def read_native_zip(archive: Path, package_id: str, version: str) -> str:
    abi = NATIVE_VERSION.fullmatch(version)
    if not abi or not archive.is_file() or archive.stat().st_size > 2_000_000_000:
        raise ValueError("missing or oversized exact native ABI ZIP")
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        if (len(set(x.lower() for x in names)) != len(names)
                or any(".." in x.split("/") or x.startswith("/") or "\\" in x
                       for x in names)):
            raise ValueError("unsafe/duplicate native archive member")
        for required in ("CONTROL", "BUILD_INFO"):
            if required not in names or z.getinfo(required).file_size > 1048576:
                raise ValueError(f"missing/unbounded {required}")
        control = z.read("CONTROL").decode("utf-8").split("\n\n", 1)[0]
        info = {}
        for line in control.splitlines():
            if ": " in line and not line.startswith(" "):
                k, v = line.split(": ", 1)
                if k in info:
                    raise ValueError("duplicated native CONTROL field")
                info[k] = v
        if (info.get("Abi") != abi.group(1) or
                info.get("Package") + "_" + info.get("Architecture", "") != package_id
                or not z.read("BUILD_INFO")):
            raise ValueError("native ZIP CONTROL/BUILD_INFO mismatches original ABI")
    return abi.group(1)


def exact_archives(cache: Path, entries: list[tuple[str, str]]) -> dict[str, str]:
    expected_paths = set()
    evidence = {}
    for package_id, version in entries:
        abi = NATIVE_VERSION.fullmatch(version).group(1)
        rel = f"cache/{abi[:2]}/{abi}.zip"
        archive = cache / abi[:2] / f"{abi}.zip"
        read_native_zip(archive, package_id, version)
        expected_paths.add(rel)
        evidence[rel] = sha256(archive)
    actual_paths = {
        "cache/" + p.relative_to(cache).as_posix()
        for p in cache.rglob("*.zip")
    }
    if actual_paths != expected_paths:
        raise ValueError("native source cache has missing/extra ABI archives")
    return evidence


def stage_attestation(stage: Path, expected: dict, cache_master: str) -> dict:
    if not HEX40.fullmatch(cache_master):
        raise ValueError("exact cache master SHA required")
    plan = stage / "packages.config"
    entries = validate_plan(plan, expected)
    evidence = exact_archives(stage / "cache", entries)
    evidence["packages.config"] = sha256(plan)
    data = {
        "format": "saltscore-cnet-win2025-abi-v1",
        "source_sha": expected["source"]["commit"],
        "cache_master_sha": cache_master,
        "fixture_git_blob": FROZEN_FIXTURE_BLOB,
        "cache_contract_revision": expected["cache"]["revision"],
        "vcpkg_scripts": expected["cache"]["vcpkg_scripts"],
        "vcpkg_tool": expected["cache"]["vcpkg_tool"],
        "runner": expected["target"]["runner"],
        "triplet": expected["target"]["triplet"],
        "native_abi_ids": [x[0] for x in entries],
        "files": evidence,
    }
    return data


def attest(stage: Path, cache_master: str) -> None:
    expected = contract()
    proof = stage_attestation(stage, expected, cache_master)
    destination = stage / "source-proof.json"
    if destination.exists():
        raise ValueError("source provenance must not be overwritten")
    destination.write_text(json.dumps(proof, sort_keys=True, indent=2) + "\n")
    print("PASS: nine exact source-built ABIs, CONTROL/BUILD_INFO and immutable checksums")


def verify(stage: Path, cache_master: str) -> None:
    proof_path = stage / "source-proof.json"
    if not proof_path.is_file() or proof_path.stat().st_size > 65536:
        raise ValueError("missing/unbounded source provenance")
    original = json.loads(proof_path.read_text())
    actual = stage_attestation(stage, contract(), cache_master)
    if original != actual:
        raise ValueError("staged native ABI archive/provenance was modified")
    print("PASS: all nine staged Windows ABI native ZIPs and source proof intact")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    p = parser.add_mutually_exclusive_group(required=True)
    p.add_argument("--plan", type=Path)
    p.add_argument("--attest", type=Path)
    p.add_argument("--verify", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--cache-master", default="")
    args = parser.parse_args()
    expected = contract()
    if args.plan:
        validate_plan(args.plan, expected)
        if args.source:
            verify_product_source(args.source, expected)
        print("PASS: exactly 9 original Windows native package IDs and ABI hashes")
    elif args.attest:
        attest(args.attest, args.cache_master)
    else:
        verify(args.verify, args.cache_master)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
