#!/usr/bin/env python3
"""Protect the single-source WTL port: vcpkg, immutable GitHub archive, no MS ATL.

The original WTL samples, headers, AppWizard and license must be installed,
not silently pared down to make an incomplete ATL implementation compile.
"""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
PORT = ROOT / "ports" / "wtl"
SHA512 = "086a6cf6a49a4318a8c519136ba6019ded7aa7f2c1d85f78c30b21183654537b3428a400a64fcdacba3a7a10a9ef05137b6f2119f59594da300d55f9ebfb1309"
REVISION = "065ef5597383c1231bd4892cf8e94331b29bdb97"


def check():
    errors = []
    for name in ("vcpkg.json", "portfile.cmake", "atlmisc.h-bug329.patch",
                 "atlribbon.h-wtl66.patch", "appwizard_setup.js-vs2022.patch"):
        if not (PORT / name).is_file():
            errors.append("missing port input: " + name)
    if errors:
        return errors
    manifest = json.loads((PORT / "vcpkg.json").read_text("utf-8"))
    recipe = (PORT / "portfile.cmake").read_text("utf-8")
    if (manifest.get("name"), manifest.get("version"),
            manifest.get("port-version")) != ("wtl", "10.0.10320", 6):
        errors.append("WTL version identity changed")
    if manifest.get("dependencies") != []:
        errors.append("WTL must not install Microsoft ATL or a second ATL provider")
    if manifest.get("supports") != "windows & !xbox":
        errors.append("WTL target-platform contract changed")
    for fragment in (REVISION, SHA512, "vcpkg_download_distfile(",
                     "vcpkg_extract_source_archive(", "Include/", "Samples",
                     "AppWizard", "MS-PL.txt", "openatl-wtl-source.txt",
                     *("PATCHES", "atlmisc.h-bug329.patch", "atlribbon.h-wtl66.patch")):
        if fragment not in recipe:
            errors.append("WTL source/installation contract missing: " + fragment)
    if any(token in recipe for token in ("downloads.sourceforge.net",
                                       "vcpkg_from_sourceforge(", "file(REMOVE",
                                       "file(REMOVE_RECURSE", "FetchContent_Declare(")):
        errors.append("Second network provider or source deletion is prohibited")
    if "atl" in [d if isinstance(d, str) else d.get("name")
                 for d in manifest.get("dependencies", [])]:
        errors.append("Forbidden Microsoft ATL dependency")
    return errors


if __name__ == "__main__":
    failures = check()
    if failures:
        for problem in failures:
            print("WTL_OVERLAY_FAIL " + problem, file=sys.stderr)
        raise SystemExit(1)
    print("WTL_OVERLAY_OK source=GitHub@pinned-hash "
          "wtl=10.0.10320#6 microsoft-atl=absent full-sources=installed")
