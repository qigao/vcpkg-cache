#!/usr/bin/env python3
"""Reject Crypto/GmSSL implementations and package ownership in generic vcpkg-cache."""
from __future__ import annotations
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
FORBIDDEN_FILES=(
    "ports/gmssl",
    "versions/g-/gmssl.json",
    ".github/workflows/gmssl-x509-candidate.yml",
    ".github/workflows/validate-gmssl-port.yml",
    ".github/workflows/validate-gmssl-registry.yml",
)
def check() -> None:
    for name in FORBIDDEN_FILES:
        if (ROOT/name).exists():
            raise ValueError(f"obsolete Crypto/GmSSL source owner reappeared: {name}")
    manifest=json.loads((ROOT/"vcpkg.json").read_text(encoding="utf-8"))
    names=[v if isinstance(v,str) else v["name"] for v in manifest["dependencies"]]
    if "gmssl" in names:
        raise ValueError("vcpkg-cache must not warm a local GmSSL provider")
    baseline=json.loads((ROOT/"versions/baseline.json").read_text(encoding="utf-8"))
    if "gmssl" in baseline["default"]:
        raise ValueError("obsolete gmssl custom registry baseline reappeared")
    for path in (".github/workflows/warm-cache.yml",
                 ".github/workflows/validate-cache-contract.yml"):
        if "gmssl" in (ROOT/path).read_text(encoding="utf-8").lower():
            raise ValueError(f"old GmSSL implementation or dependency remains in {path}")
    print("PASS: generic vcpkg-cache contains zero active Crypto/GmSSL source, package or CI owners")
if __name__ == "__main__":
    try:
        check()
    except (ValueError, OSError, KeyError) as exc:
        print(f"FAILED Crypto/GmSSL ownership: {exc}",file=sys.stderr)
        sys.exit(1)
