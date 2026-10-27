#!/usr/bin/env python3
"""Restore exact vcpkg ABI packages over curl GitHub NuGet V3; no Mono/NuGet."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def validate(config: Path, allow_empty: bool = False) -> int:
    root = ET.parse(config).getroot()
    if root.tag != "packages":
        raise ValueError("vcpkg emitted invalid packages.config")
    prefix = os.environ.get("X_VCPKG_NUGET_ID_PREFIX", "")
    if prefix and not re.fullmatch(r"[A-Za-z0-9_.+-]+", prefix):
        raise ValueError("invalid NuGet identity prefix")
    seen: set[tuple[str, str]] = set()
    for item in root:
        if item.tag != "package" or set(item.attrib) != {"id", "version"}:
            raise ValueError("invalid packages.config entry")
        ident = item.attrib["id"]
        version = item.attrib["version"]
        if not re.fullmatch(r"[A-Za-z0-9_.+-]+", ident):
            raise ValueError("invalid exact package ID")
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-vcpkg[0-9a-f]{64}", version):
            raise ValueError(f"missing canonical vcpkg ABI: {ident}/{version}")
        if prefix:
            canonical = prefix + "_"
            if not ident.startswith(canonical):
                if not ident.startswith(prefix):
                    raise ValueError(f"package ID does not use pinned prefix: {ident}")
                suffix = ident[len(prefix):]
                if not suffix:
                    raise ValueError("empty package suffix after prefix")
                ident = canonical + suffix
                item.attrib["id"] = ident
        key = (ident.lower(), version.lower())
        if key in seen:
            raise ValueError(f"duplicate ABI: {ident}/{version}")
        seen.add(key)
    if not seen and not allow_empty:
        raise ValueError("vcpkg did not resolve expected packages; refusing silent no-op")
    ET.ElementTree(root).write(config, encoding="utf-8", xml_declaration=True)
    return len(seen)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest-root", required=True, type=Path)
    p.add_argument("--triplet", required=True)
    p.add_argument("--host-triplet", required=True)
    p.add_argument("--feature", action="append", default=[],
                   help="Exact product-owned manifest feature (repeatable)")
    args = p.parse_args()
    for name in ("triplet", "host_triplet"):
        if not re.fullmatch(r"[A-Za-z0-9_.+-]+", getattr(args, name)):
            raise ValueError(f"invalid {name}")
    manifest = args.manifest_root.resolve()
    manifest_file = manifest / "vcpkg.json"
    if not manifest_file.is_file():
        raise ValueError(f"product-owned manifest is missing: {manifest}")
    manifest_data = json.loads(manifest_file.read_text(encoding="utf-8"))
    if not isinstance(manifest_data, dict):
        raise ValueError("invalid vcpkg manifest object")
    all_features = manifest_data.get("features", {})
    if not isinstance(all_features, dict):
        raise ValueError("vcpkg manifest features must be an object")
    for name in args.feature:
        if not re.fullmatch(r"[A-Za-z0-9-]+", name):
            raise ValueError(f"invalid vcpkg feature name: {name!r}")
        if name not in all_features:
            raise ValueError(f"undeclared product feature: {name!r}")
    if len(args.feature) != len(set(args.feature)):
        raise ValueError("duplicate feature requested")
    selected = manifest_data.get("dependencies", [])
    if not isinstance(selected, list):
        raise ValueError("manifest dependencies must be an array")
    # The full vcpkg resolver still owns transitive and platform-dependent
    # dependency selection; this admission check only distinguishes an
    # intentionally empty root graph from accidentally omitted features.
    selected_features = list(manifest_data.get("default-features", [])) + args.feature
    for feature in selected_features:
        payload = all_features.get(feature)
        if not isinstance(payload, dict):
            raise ValueError(f"invalid vcpkg feature metadata: {feature!r}")
        selected.extend(payload.get("dependencies", []))
    graph_intentionally_empty = len(selected) == 0
    root = Path(os.environ["VCPKG_ROOT"])
    vcpkg = root / ("vcpkg.exe" if os.name == "nt" else "vcpkg")
    if not vcpkg.is_file():
        raise ValueError("canonical vcpkg executable is missing")
    cache = Path(os.environ["VCPKG_BINARY_CACHE"]).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    preflight = Path(os.environ["RUNNER_TEMP"]) / "qigao-curl-vcpkg-abi"
    preflight.mkdir(parents=True, exist_ok=True)
    config = preflight / "packages.config"
    config.unlink(missing_ok=True)
    subprocess.run([
        str(vcpkg), "install",
        f"--x-manifest-root={manifest}",
        f"--x-install-root={preflight / 'installed'}",
        f"--triplet={args.triplet}",
        f"--host-triplet={args.host_triplet}",
        "--dry-run",
        *[f"--x-feature={name}" for name in args.feature],
        f"--x-write-nuget-packages-config={config}",
    ], cwd=manifest, check=True)
    if not config.is_file():
        raise ValueError("canonical vcpkg did not emit package/ABI references")
    count = validate(config, allow_empty=graph_intentionally_empty)
    if count == 0:
        print("vcpkg manifest has no dependencies or selected feature packages; no HTTP downloads required", flush=True)
        return 0
    print(f"Verified {count} canonical vcpkg package/ABI references", flush=True)
    subprocess.run([
        sys.executable, str(Path(__file__).with_name("github-packages.py")),
        "cache", str(config), str(cache)
    ], check=True)
    print(f"curl-only GitHub Packages cache populated: {cache}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
