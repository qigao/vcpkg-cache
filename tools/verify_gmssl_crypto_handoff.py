#!/usr/bin/env python3
"""Verify and export the frozen GmSSL 3.2.0#13 Crypto provider handoff.

No network, vcpkg invocation, source patch application, or port modification.
Every exported byte comes from the exact pinned Git blob recorded in the
current registry tree; the old vcpkg port remains unchanged until Crypto
itself passes independent qualification.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile


PORT_DIR = "ports/gmssl"
INVENTORY = "migrations/gmssl/ownership-manifest.json"
LICENSE = "migrations/gmssl/UPSTREAM-APACHE-2.0-LICENSE"
README = "migrations/gmssl/README.md"
PACKAGING = {"portfile.cmake", "vcpkg.json", "GmSSLConfig.cmake"}


def git(root: Path, *args: str) -> bytes:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *args], stderr=subprocess.PIPE
        )
    except subprocess.CalledProcessError as exc:
        raise ValueError(
            f"git {' '.join(args)} failed: {exc.stderr.decode(errors='replace')}"
        ) from exc


def blob_sha(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def classify(path: str) -> tuple[str, str]:
    p = PurePosixPath(path)
    if path.startswith("/") or ".." in p.parts or p.as_posix() != path:
        raise ValueError(f"unsafe source path: {path}")
    if path in PACKAGING:
        return "vcpkg-packaging", f"vcpkg-cache/ports/gmssl/{path}"
    if path.startswith("tests/"):
        return "provider-conformance", "providers/gmssl/tests/" + path[6:]
    if path.endswith((".c", ".h")):
        return "provider-source-backport", "providers/gmssl/patches/" + path
    if path.endswith((".cmake", ".patch")):
        return "upstream-source-patch", "providers/gmssl/patches/" + path
    raise ValueError(f"unclassified GmSSL port file: {path}")


def tracked_port_blobs(root: Path) -> dict[str, str]:
    entries = git(root, "ls-tree", "-r", "-z", "HEAD:" + PORT_DIR)
    result: dict[str, str] = {}
    for line in entries.split(b"\0"):
        if not line:
            continue
        header, raw_path = line.split(b"\t", 1)
        mode, kind, sha = header.decode().split()
        if kind != "blob" or mode not in ("100644", "100755"):
            raise ValueError(f"unexpected Git tree object: {line[:110]!r}")
        path = raw_path.decode("utf-8")
        if path in result:
            raise ValueError(f"duplicate tracked port file: {path}")
        result[path] = sha
    return result


def load_json_at_head(root: Path, path: str) -> dict:
    return json.loads(git(root, "show", f"HEAD:{path}").decode("utf-8"))


def validate(root: Path) -> tuple[dict, dict[str, str]]:
    manifest = load_json_at_head(root, INVENTORY)
    source = manifest["source"]
    if manifest["schema_version"] != 1:
        raise ValueError("unrecognized handoff manifest schema")
    if manifest["handoff_status"] != "STAGED_PENDING_STANDALONE_CRYPTO_REPOSITORY":
        raise ValueError("handoff must not claim completed Crypto ownership")
    port_tree = git(root, "rev-parse", "HEAD:" + PORT_DIR).decode().strip()
    if port_tree != source["port_git_tree"]:
        raise ValueError(f"versioned GmSSL port changed: {port_tree}")
    tracked = tracked_port_blobs(root)
    rows = manifest["files"]
    if len(rows) != len(tracked):
        raise ValueError(f"incomplete inventory: {len(rows)} entries, {len(tracked)} blobs")
    unique: dict[str, str] = {}
    targets: set[str] = set()
    counts: dict[str, int] = {}
    for row in rows:
        path = row["path"]
        if path in unique:
            raise ValueError(f"duplicated manifest file: {path}")
        expected_group, expected_target = classify(path)
        if row["owner_group"] != expected_group or row["target"] != expected_target:
            raise ValueError(f"incorrect owner classification or target: {path}")
        if row["git_blob_sha"] != tracked.get(path):
            raise ValueError(f"source blob identity mismatch: {path}")
        if row["target"] in targets:
            raise ValueError(f"duplicate proposed Crypto destination: {row['target']}")
        targets.add(row["target"])
        unique[path] = row["git_blob_sha"]
        counts[expected_group] = counts.get(expected_group, 0) + 1
    if set(unique) != set(tracked):
        raise ValueError("GmSSL port contains untracked or missing inventory entries")
    if counts != manifest["counts"]:
        raise ValueError(f"inventory group counts changed: {counts}")
    if counts != {
        "vcpkg-packaging": 3,
        "provider-conformance": 39,
        "provider-source-backport": 13,
        "upstream-source-patch": 40,
    }:
        raise ValueError(f"baseline source/port/test grouping drift: {counts}")
    port = load_json_at_head(root, PORT_DIR + "/vcpkg.json")
    if (port["name"], port["version"], int(port["port-version"])) != (
        "gmssl", source["version"], source["port_version"]
    ):
        raise ValueError("GmSSL port version drift")
    baseline = load_json_at_head(root, "versions/baseline.json")["default"]["gmssl"]
    if (baseline["baseline"], baseline["port-version"]) != (
        source["version"], source["port_version"]
    ):
        raise ValueError("GmSSL registry baseline drift")
    versions = load_json_at_head(root, "versions/g-/gmssl.json")["versions"]
    matching = [
        r for r in versions
        if r.get("version") == source["version"]
        and r.get("port-version", 0) == source["port_version"]
    ]
    if len(matching) != 1 or matching[0]["git-tree"] != port_tree:
        raise ValueError("GmSSL exact port-version Git Tree not registered")
    portfile = git(root, "cat-file", "blob", unique["portfile.cmake"]).decode()
    if source["upstream_git_url"] not in portfile:
        raise ValueError("GmSSL pinned upstream URL mismatch")
    pins = re.findall(r"(?m)^\s*REF\s+([0-9a-f]{40})\s*$", portfile)
    if pins != [source["upstream_commit"]]:
        raise ValueError(f"GmSSL exact upstream source pin mismatch: {pins}")
    for fragment in ("add_library(gmssl STATIC", "vcpkg_cmake_install()"):
        if fragment not in portfile:
            raise ValueError(f"lost GmSSL static package build contract: {fragment}")
    includes = re.findall(
        r'include\("\$\{CMAKE_CURRENT_LIST_DIR\}/([^"]+\.cmake)"\)',
        portfile,
    )
    source_modules = sorted(
        p for p in unique if p.endswith(".cmake") and p not in PACKAGING
    )
    if sorted(includes) != source_modules:
        raise ValueError("orphaned/missing/duplicated upstream patch modules")
    for path in unique:
        if path.endswith(".patch") and path not in portfile:
            raise ValueError(f"unreferenced GmSSL patch: {path}")
    license_data = git(root, "show", f"HEAD:{LICENSE}")
    if not license_data.startswith(b"                                 Apache License"):
        raise ValueError("missing original upstream GmSSL Apache-2.0 license")
    if blob_sha(license_data) != source["upstream_license_git_blob_sha"]:
        raise ValueError("upstream source LICENSE differs from pinned GmSSL revision")
    print(
        "PASS: exact GmSSL "
        f"{source['version']}#{source['port_version']} "
        f"port-tree={port_tree}, {len(unique)} files, "
        f"{len(unique) - counts['vcpkg-packaging']} Crypto import candidates"
    )
    return manifest, unique


def deterministic_tar(items: dict[str, bytes]) -> bytes:
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for path in sorted(items):
            p = PurePosixPath(path)
            if path.startswith("/") or ".." in p.parts or p.as_posix() != path:
                raise ValueError(f"unsafe export path: {path}")
            data = items[path]
            info = tarfile.TarInfo(path)
            info.size = len(data)
            info.mtime = 0
            info.mode = 0o644
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            tar.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", filename="", mtime=0) as gz:
        gz.write(raw.getvalue())
    return compressed.getvalue()


def export(root: Path, manifest: dict, blobs: dict[str, str]) -> bytes:
    payload: dict[str, bytes] = {}
    for row in manifest["files"]:
        if row["owner_group"] == "vcpkg-packaging":
            continue  # Keep these files in vcpkg-cache, not in Crypto.
        body = git(root, "cat-file", "blob", blobs[row["path"]])
        if blob_sha(body) != row["git_blob_sha"]:
            raise ValueError(f"provider blob content changed: {row['path']}")
        payload[row["target"]] = body
    payload["providers/gmssl/LICENSE"] = git(root, "show", f"HEAD:{LICENSE}")
    payload["providers/gmssl/README.md"] = git(root, "show", f"HEAD:{README}")
    payload["providers/gmssl/provenance/ownership-manifest.json"] = (
        git(root, "show", f"HEAD:{INVENTORY}")
    )
    if len(payload) != 95:  # 92 nonpackaging sources + license + readme + manifest
        raise ValueError(f"incomplete Crypto handoff bundle: {len(payload)} entries")
    return deterministic_tar(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--export", type=Path, default=None)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest, blobs = validate(root)
    result = {
        "classification": "PRE-CRYPTO-REPO_SOURCE_HANDOFF_NOT_RELEASE",
        "source": manifest["source"],
        "counts": manifest["counts"],
        "port_tree_unchanged": True,
        "legacy_port_release_unchanged": True,
    }
    if args.export is not None:
        package = export(root, manifest, blobs)
        args.export.parent.mkdir(parents=True, exist_ok=True)
        args.export.write_bytes(package)
        result["bundle_sha256"] = hashlib.sha256(package).hexdigest()
        result["bundle_bytes"] = len(package)
        result["bundle_entries"] = 95
        print(f"Crypto import bundle SHA256: {result['bundle_sha256']}")
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError) as exc:
        print(f"FAIL GmSSL Crypto handoff: {exc}", file=sys.stderr)
        sys.exit(1)
