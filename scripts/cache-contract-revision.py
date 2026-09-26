#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import pathlib
import sys


def contract_files(root: pathlib.Path) -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for directory in ("ports", "versions", "manifests"):
        path = root / directory
        if path.is_dir():
            files.extend(p for p in path.rglob("*") if p.is_file())

    for relative in (
        ".gitattributes",
        ".github/actions/setup-vcpkg-cache/action.yml",
        "cache-contract-version.txt",
        "cmake/QigaoVcpkgToolchain.cmake",
        "scripts/cache-contract-revision.py",
        "scripts/vcpkg-required-commits.py",
        "vcpkg.json",
        "vcpkg-tool-version.txt",
        "vcpkg-scripts-revision.txt",
    ):
        path = root / relative
        if path.is_file():
            files.append(path)

    return sorted(
        set(files),
        key=lambda p: p.relative_to(root).as_posix(),
    )


def calculate(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in contract_files(root):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(relative)
        digest.update(b"\0")
        data = path.read_bytes().replace(b"\r\n", b"\n")
        digest.update(data)
        digest.update(b"\0")
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: cache-contract-revision.py <repository-root>")
    root = pathlib.Path(sys.argv[1]).resolve()
    print(calculate(root))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
