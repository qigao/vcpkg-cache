#!/usr/bin/env python3
"""Offline, exact-ABI WABT source-producer admission; NEVER performs an HTTP PUT.

The requested ABI is pinned to the actual missing GitHub Packages native
archive reported by the clean-L1 consumer. This verifier will NOT silently
replace it with a different ABI calculated by another compiler/source tree.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import xml.etree.ElementTree as ET


REPO = Path(__file__).resolve().parents[2]
PUBLISHER = REPO / "scripts/publish-vcpkg-curl-cache.py"
ABI = re.compile(r"^[0-9a-f]{64}$")


def canonical_publisher():
    spec = importlib.util.spec_from_file_location("vcpkg_canonical_native_publisher", PUBLISHER)
    if spec is None or spec.loader is None:
        raise ValueError("canonical native curl publisher is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def qualify(
    packages_config: Path, files_cache: Path, output: Path, *,
    expected_wabt_abi: str, installed_tool: Path, publisher=None,
) -> list[tuple[str, str, str]]:
    """Validate the complete source package plan and byte-exact native roundtrip."""
    if not ABI.fullmatch(expected_wabt_abi):
        raise ValueError("expected WABT ABI must be exactly 64 lowercase hex digits")
    if not installed_tool.is_file() or not os.access(installed_tool, os.X_OK):
        raise ValueError("fresh source-installed WABT wast2json executable is missing")
    if output.exists() and any(output.iterdir()):
        raise ValueError("native NuGet output directory must start empty")
    if publisher is None:
        publisher = canonical_publisher()
    if packages_config.stat().st_size > 1_048_576:
        raise ValueError("exact ABI plan exceeds bounded metadata size")

    root = ET.parse(packages_config).getroot()
    if root.tag != "packages":
        raise ValueError("exact vcpkg plan must be a packages.config document")
    entries: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    wabt = []
    for node in root:
        if node.tag != "package" or set(node.attrib) != {"id", "version"}:
            raise ValueError("noncanonical exact vcpkg package plan")
        name, version = node.attrib["id"], node.attrib["version"]
        match = publisher.ABI_VERSION.fullmatch(version)
        if not publisher.IDENTITY.fullmatch(name) or match is None:
            raise ValueError("package ID or exact ABI version is not canonical")
        identity = (name.casefold(), version.casefold())
        if identity in seen:
            raise ValueError("duplicate immutable native package identity")
        seen.add(identity)
        abi = match[1]
        entries.append((name, version, abi))
        if name == "wabt_x64-linux":
            wabt.append((version, abi))

    if len(wabt) != 1:
        raise ValueError("expected exactly one source-built wabt_x64-linux ABI")
    wabt_version, wabt_abi = wabt[0]
    if wabt_version != f"1.0.42-vcpkg{expected_wabt_abi}" or wabt_abi != expected_wabt_abi:
        raise ValueError(
            f"source-built WABT ABI mismatch: calculated {wabt_version}; "
            f"published consumer requires 1.0.42-vcpkg{expected_wabt_abi}"
        )

    # Do not report a partial success when any required host/target ABI is
    # missing. Validate every source artifact before producing any NuGet ZIP.
    if not entries:
        raise ValueError("exact WABT source package plan was empty")
    for name, version, abi in entries:
        archive = files_cache / abi[:2] / (abi + ".zip")
        if not archive.is_file():
            raise ValueError(f"missing source-built exact files ABI: {name}/{version}")
        publisher.identify_source(archive, name, version)

    output.mkdir(parents=True, exist_ok=True)
    report = []
    for name, version, abi in entries:
        native = files_cache / abi[:2] / (abi + ".zip")
        nupkg = output / f"{name}.{version}.nupkg"
        publisher.build_nupkg(native, name, version, nupkg)
        digest = publisher.check_roundtrip(native, nupkg, name, version)
        if digest != publisher.entries_digest(native):
            raise ValueError(f"native NuGet roundtrip changed payload: {name}/{version}")
        print(
            f"exact_source_producer={name}/{version} "
            f"native_sha256={digest} nupkg_sha256={publisher.packages.sha256(nupkg)}",
            flush=True,
        )
        report.append((name, version, abi))

    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages-config", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--installed-tool", type=Path, required=True)
    parser.add_argument("--expected-wabt-abi", required=True)
    args = parser.parse_args()
    rows = qualify(
        args.packages_config, args.cache, args.output,
        expected_wabt_abi=args.expected_wabt_abi,
        installed_tool=args.installed_tool,
    )
    manifest = REPO / "cache-contracts/wabt-producer/vcpkg.json"
    print(f"source_manifest_sha256={hashlib.sha256(manifest.read_bytes()).hexdigest()}")
    print(f"exact_native_package_count={len(rows)}")
    print("remote_publish_attempted=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
