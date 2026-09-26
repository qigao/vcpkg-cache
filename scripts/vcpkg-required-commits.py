#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import sys


SHA40 = re.compile(r"^[0-9a-fA-F]{40}$")
SKIP_DIRS = {
    ".git",
    ".github",
    ".cache",
    "build",
    "dist",
    "external",
    "node_modules",
    "out",
    "stage",
    "vcpkg_installed",
}


def manifests(root: pathlib.Path):
    direct = root / "vcpkg.json"
    if direct.is_file():
        yield direct

    for path in root.rglob("vcpkg.json"):
        if path == direct:
            continue
        try:
            relative = path.relative_to(root)
        except ValueError:
            continue
        if any(part in SKIP_DIRS for part in relative.parts[:-1]):
            continue
        yield path


def collect(roots: list[pathlib.Path]) -> list[str]:
    baselines: set[str] = set()
    seen: set[pathlib.Path] = set()

    for root in roots:
        root = root.resolve()
        if root in seen or not root.is_dir():
            continue
        seen.add(root)
        for manifest in manifests(root):
            try:
                data = json.loads(manifest.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                continue
            baseline = data.get("builtin-baseline")
            if isinstance(baseline, str) and SHA40.fullmatch(baseline):
                baselines.add(baseline.lower())

    return sorted(baselines)


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit("usage: vcpkg-required-commits.py <root> [<root> ...]")
    roots = [pathlib.Path(arg) for arg in sys.argv[1:]]
    for baseline in collect(roots):
        print(baseline)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
