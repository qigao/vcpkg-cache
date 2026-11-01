#!/usr/bin/env python3
"""Fail-closed manual native PackagePublish admission for an explicitly named ABI.

The trusted operator must supply both package ID and its immutable full
version, not just choose a broad product set such as "wabt". The exact
packages.config is still derived only by pinned vcpkg, never guessed here.
"""
from __future__ import annotations

import argparse
import io
from pathlib import Path
import re
import xml.etree.ElementTree as ET


PRODUCTS = {
    "simde": "simde_x64-linux",
    "wabt": "wabt_x64-linux",
    "miniaudio-arm64": "miniaudio_arm64-linux",
}
IDENTITY = re.compile(r"[A-Za-z0-9_.+-]+\Z")
EXACT_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+-vcpkg[0-9a-f]{64}\Z")
MAX_PLAN_SIZE = 1_048_576


def verify(
    plan: Path, *, package_set: str,
    expected_id: str, expected_version: str,
) -> list[tuple[str, str]]:
    canonical_id = PRODUCTS.get(package_set)
    if not canonical_id:
        raise ValueError("unapproved native source package set")
    if expected_id != canonical_id or not IDENTITY.fullmatch(expected_id):
        raise ValueError("expected NuGet package ID does not match selected product set")
    if not EXACT_VERSION.fullmatch(expected_version):
        raise ValueError("expected full immutable NuGet ABI version is missing or malformed")
    if not plan.is_file() or plan.stat().st_size > MAX_PLAN_SIZE:
        raise ValueError("missing or unbounded canonical packages.config")
    root = ET.parse(plan).getroot()
    if root.tag != "packages" or root.attrib:
        raise ValueError("only canonical vcpkg packages.config plan is admissible")
    names = set()
    packages = []
    for node in root:
        if node.tag != "package" or set(node.attrib) != {"id", "version"}:
            raise ValueError("unexpected native NuGet package element")
        name, version = node.attrib["id"], node.attrib["version"]
        if not IDENTITY.fullmatch(name) or not EXACT_VERSION.fullmatch(version):
            raise ValueError("unqualified or floating native NuGet version")
        key = name.casefold()
        if key in names:
            raise ValueError("duplicate or ambiguous native NuGet package ID")
        names.add(key)
        packages.append((name, version))

    if not packages:
        raise ValueError("empty canonical native package plan")
    targets = [version for name, version in packages if name == expected_id]
    if targets != [expected_version]:
        raise ValueError(
            f"exact native publish target mismatch: expected "
            f"{expected_id}/{expected_version}, got {targets or 'absent'}"
        )
    return packages


def target_only_plan(
    source: Path, destination: Path, *, package_set: str,
    expected_id: str, expected_version: str, check: bool = False,
) -> None:
    """Derive the ONLY approved publish target from a real vcpkg ABI graph.

    The complete resolver plan remains SHA-attested, and only the explicitly
    selected exact ID/version is admitted to the privileged publisher.
    """
    if package_set != "miniaudio-arm64":
        raise ValueError("target-only publication is restricted to the ARM64 source package")
    verify(source, package_set=package_set, expected_id=expected_id,
           expected_version=expected_version)
    if source.resolve() == destination.resolve():
        raise ValueError("canonical source plan and target plan must be distinct")
    root = ET.Element("packages")
    ET.SubElement(root, "package", id=expected_id, version=expected_version)
    payload = io.BytesIO()
    ET.ElementTree(root).write(payload, encoding="utf-8", xml_declaration=True)
    native = payload.getvalue()
    if check:
        if (not destination.is_file() or destination.stat().st_size > MAX_PLAN_SIZE
                or destination.read_bytes() != native):
            raise ValueError("protected publish plan differs from source-derived exact target")
    else:
        if destination.exists():
            raise ValueError("target-only plan must not overwrite an existing file")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(native)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--package-set", required=True)
    parser.add_argument("--expected-id", required=True)
    parser.add_argument("--expected-version", required=True)
    targets = parser.add_mutually_exclusive_group()
    targets.add_argument("--write-target-plan", type=Path)
    targets.add_argument("--check-target-plan", type=Path)
    args = parser.parse_args()
    result = verify(
        args.plan, package_set=args.package_set,
        expected_id=args.expected_id,
        expected_version=args.expected_version,
    )
    if args.write_target_plan or args.check_target_plan:
        target_only_plan(
            args.plan, args.write_target_plan or args.check_target_plan,
            package_set=args.package_set, expected_id=args.expected_id,
            expected_version=args.expected_version,
            check=args.check_target_plan is not None,
        )
    print(f"exact_publish_target={args.expected_id}/{args.expected_version}", flush=True)
    print(f"exact_plan_package_count={len(result)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
