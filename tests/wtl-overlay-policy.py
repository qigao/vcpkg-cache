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
                 "atlribbon.h-wtl66.patch", "atlribbon.h-clang-std.patch",
                 "atlctrlw.h-clang-bounds.patch", "atlctrlx.h-clang-bounds.patch",
                 "appwizard_setup.js-vs2022.patch"):
        if not (PORT / name).is_file():
            errors.append("missing port input: " + name)
    if errors:
        return errors
    manifest = json.loads((PORT / "vcpkg.json").read_text("utf-8"))
    recipe = (PORT / "portfile.cmake").read_text("utf-8")
    if (manifest.get("name"), manifest.get("version"),
            manifest.get("port-version")) != ("wtl", "10.0.10320", 7):
        errors.append("WTL version identity changed")
    if manifest.get("dependencies") != []:
        errors.append("WTL must not install Microsoft ATL or a second ATL provider")
    if manifest.get("supports") != "windows & !xbox":
        errors.append("WTL target-platform contract changed")
    for fragment in (REVISION, SHA512, "vcpkg_download_distfile(",
                     "vcpkg_extract_source_archive(", "Include/", "Samples",
                     "AppWizard", "MS-PL.txt", "openatl-wtl-source.txt", "NO_REMOVE_ONE_LEVEL",
                     *("PATCHES", "atlmisc.h-bug329.patch", "atlribbon.h-wtl66.patch",
                        "atlribbon.h-clang-std.patch",
                        "atlctrlw.h-clang-bounds.patch",
                        "atlctrlx.h-clang-bounds.patch")):
        if fragment not in recipe:
            errors.append("WTL source/installation contract missing: " + fragment)
    # Clang standard parsing correction: four dependent-template calls,
    # plus a const-safe local DECIMAL copy. Never delete WTL public APIs.
    clang_patch = (PORT / "atlribbon.h-clang-std.patch").read_text("utf-8")
    if (clang_patch.count("-		return this->UI") != 2 or
            clang_patch.count("-			this->UI") != 2 or
            clang_patch.count("+		return this->template UI") != 2 or
            clang_patch.count("+			this->template UI") != 2 or
            "DECIMAL copy = {};" not in clang_patch or
            "VarI4FromDec(pDecimal != NULL ? &copy : NULL" not in clang_patch):
        errors.append("WTL Clang corrections must preserve original APIs and const DECIMAL")
    if any(token in clang_patch for token in ("class CServerAppModule", "CRegProperty", "CPrintDialogEx")):
        errors.append("WTL Clang patch must not modify public COM/registry APIs")
    for filename, expected, old, new in (
        ("atlctrlw.h-clang-bounds.patch", 3,
         "szString[pT->_nMaxMenuItemTextLength]",
         "szString[T::_nMaxMenuItemTextLength]"),
        ("atlctrlx.h-clang-bounds.patch", 1,
         "pszTemp[pT->m_cchCmpTextMax]",
         "pszTemp[T::m_cchCmpTextMax]"),
    ):
        source = (PORT / filename).read_text("utf-8")
        if (source.count(old) != expected or source.count(new) != expected or
                source.count("\n-") != expected or source.count("\n+") != expected + 1):
            errors.append("WTL Clang constant-bound correction changed: " + filename)
    if any(token in recipe for token in ("downloads.sourceforge.net",
                                       "vcpkg_from_sourceforge(", "file(REMOVE",
                                       "file(REMOVE_RECURSE", "FetchContent_Declare(")):
        errors.append("Second network provider or source deletion is prohibited")
    workflow = (ROOT / ".github/workflows/validate-wtl-overlay.yml").read_text("utf-8")
    if ("--only-binarycaching" not in workflow or
            "WTL_COLD_WARM_OK" not in workflow or
            "wtl10-overlay-warm" not in workflow):
        errors.append("Cold/warm read-only WTL ABI restore gate is mandatory")
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
          "wtl=10.0.10320#7 microsoft-atl=absent full-sources=installed")
