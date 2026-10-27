#!/usr/bin/env python3
"""Restore exact vcpkg ABI packages over curl GitHub NuGet V3; no Mono/NuGet."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def validate(config: Path) -> int:
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
        if prefix and not ident.startswith(prefix + "."):
            ident = prefix + "." + ident
            item.attrib["id"] = ident
        key = (ident.lower(), version.lower())
        if key in seen:
            raise ValueError(f"duplicate ABI: {ident}/{version}")
        seen.add(key)
    if not seen:
        raise ValueError("empty canonical ABI set, refusing silent no-op")
    ET.ElementTree(root).write(config, encoding="utf-8", xml_declaration=True)
    return len(seen)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest-root", required=True, type=Path)
    p.add_argument("--triplet", required=True)
    p.add_argument("--host-triplet", required=True)
    args = p.parse_args()
    for name in ("triplet", "host_triplet"):
        if not re.fullmatch(r"[A-Za-z0-9_.+-]+", getattr(args, name)):
            raise ValueError(f"invalid {name}")
    manifest = args.manifest_root.resolve()
    if not (manifest / "vcpkg.json").is_file():
        raise ValueError(f"product-owned manifest is missing: {manifest}")
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
        f"--x-write-nuget-packages-config={config}",
    ], cwd=manifest, check=True)
    if not config.is_file():
        raise ValueError("canonical vcpkg did not emit package/ABI references")
    count = validate(config)
    print(f"Verified {count} canonical vcpkg package/ABI references", flush=True)
    subprocess.run([
        sys.executable, str(Path(__file__).with_name("github-packages.py")),
        "cache", str(config), str(cache)
    ], check=True)
    print(f"curl-only GitHub Packages cache populated: {cache}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
