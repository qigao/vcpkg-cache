#!/usr/bin/env python3
"""Build a paired Lemon/lempar host package; all network transport uses shared curl."""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import tempfile
import time
from xml.sax.saxutils import escape, quoteattr
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LOCK = json.loads((HERE / "source-lock.json").read_text(encoding="utf-8"))
RIDS = ("linux-x64", "linux-arm64", "macos-x64", "macos-arm64", "windows-x64", "windows-arm64")


def helper(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


native = helper("lemon_native_restore", ROOT / "scripts/restore-native-dependency.py")
transport = helper("lemon_curl_publisher", ROOT / "scripts/publish-vcpkg-curl-cache.py")


def ensure(ok, message):
    if not ok:
        raise ValueError(message)


def executable(rid):
    ensure(rid in RIDS, "unsupported Lemon host RID")
    return "lemon.exe" if rid.startswith("windows-") else "lemon"


def binary_host(path, rid):
    data = path.read_bytes()
    machine = None
    if rid.startswith("linux-") and data[:6] == b"\x7fELF\x02\x01" and len(data) >= 20:
        machine = {62: "x64", 183: "arm64"}.get(struct.unpack_from("<H", data, 18)[0])
    elif rid.startswith("windows-") and data[:2] == b"MZ" and len(data) >= 64:
        offset = struct.unpack_from("<I", data, 60)[0]
        if offset + 6 <= len(data) and data[offset:offset+4] == b"PE\x00\x00":
            machine = {0x8664: "x64", 0xAA64: "arm64"}.get(struct.unpack_from("<H", data, offset+4)[0])
    elif rid.startswith("macos-") and data[:4] == b"\xcf\xfa\xed\xfe" and len(data) >= 8:
        machine = {0x01000007: "x64", 0x0100000C: "arm64"}.get(struct.unpack_from("<I", data, 4)[0])
    ensure(machine == rid.rsplit("-", 1)[1], f"binary format/architecture does not match {rid}")


def source_pair(directory):
    for name, digest in LOCK["files"].items():
        path = directory / name
        ensure(path.is_file() and native.packages.sha256(path) == digest, f"locked source mismatch: {name}")


def fetch(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for name, digest in LOCK["files"].items():
        path = directory / name
        if path.exists():
            ensure(native.packages.sha256(path) == digest, f"existing source differs: {name}")
        else:
            url = f"https://raw.githubusercontent.com/{LOCK['repository']}/{LOCK['commit']}/tool/{name}"
            native.archives.verified_download(url, path, digest, limit=2 * 1024 * 1024)
    source_pair(directory)


def manifest(rid, binary):
    return {"schema": 1, "package_id": LOCK["package_id"], "package_version": LOCK["package_version"],
            "rid": rid, "sqlite_version": LOCK["sqlite_version"], "source_commit": LOCK["commit"],
            "lemon_source_sha256": LOCK["files"]["lemon.c"],
            "template_sha256": LOCK["files"]["lempar.c"], "executable_sha256": native.packages.sha256(binary)}


def stage(source, build, rid, output):
    source_pair(source)
    binary = build / executable(rid)
    binary_host(binary, rid)
    root = output / "tools" / rid
    ensure(not root.exists(), "host staging directory must be fresh")
    (root / "bin").mkdir(parents=True)
    (root / "share/lemon").mkdir(parents=True)
    shutil.copyfile(binary, root / "bin" / executable(rid))
    (root / "bin" / executable(rid)).chmod(0o755)
    shutil.copyfile(source / "lempar.c", root / "share/lemon/lempar.c")
    (root / "share/lemon/source.json").write_text(json.dumps(manifest(rid, binary), indent=2) + "\n", encoding="utf-8")
    validate_root(root, rid)


def validate_root(root, rid):
    binary = root / "bin" / executable(rid)
    template = root / "share/lemon/lempar.c"
    ensure(binary.is_file() and template.is_file(), f"missing executable/template for {rid}")
    binary_host(binary, rid)
    ensure(native.packages.sha256(template) == LOCK["files"]["lempar.c"], f"mixed Lemon template for {rid}")
    metadata = json.loads((root / "share/lemon/source.json").read_text(encoding="utf-8"))
    ensure(metadata == manifest(rid, binary), f"source/binary pair metadata differs for {rid}")


def pack(root, destination):
    expected = {f"tools/{rid}/{suffix}" for rid in RIDS for suffix in
                (f"bin/{executable(rid)}", "share/lemon/lempar.c", "share/lemon/source.json")}
    actual = set()
    for path in root.rglob("*"):
        ensure(not path.is_symlink(), "symlink in staged Lemon package")
        if path.is_file():
            actual.add(path.relative_to(root).as_posix())
    ensure(actual == expected, "package must contain exactly all six host executable/template/source triples")
    for rid in RIDS:
        validate_root(root / "tools" / rid, rid)
    identity, version = LOCK["package_id"], LOCK["package_version"]
    nuspec = f"{identity}.nuspec"
    entries = {name: (root / name).read_bytes() for name in sorted(expected)}
    entries["LICENSE.txt"] = (HERE / "LICENSE.txt").read_bytes()
    entries[nuspec] = (
        '<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd"><metadata>'
        f'<id>{identity}</id><version>{version}</version><authors>qigao</authors>'
        '<description>Paired SQLite Lemon parser generator and lempar.c host tools</description>'
        '<license type="file">LICENSE.txt</license>'
        '<repository type="git" url="https://github.com/qigao/vcpkg-cache"/>'
        '</metadata></package>').encode()
    entries["_rels/.rels"] = (
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" '
        f'Target="/{escape(nuspec)}" Id="R0"/></Relationships>').encode()
    extensions = {"rels": "application/vnd.openxmlformats-package.relationships+xml", "nuspec": "application/octet"}
    for name in entries:
        if "." in Path(name).name:
            extensions.setdefault(Path(name).suffix[1:], "application/octet-stream")
    types = ''.join(f'<Default Extension={quoteattr(ext)} ContentType={quoteattr(mime)}/>' for ext, mime in sorted(extensions.items()))
    types += ''.join(f'<Override PartName="/{name}" ContentType="application/octet-stream"/>' for name in sorted(expected) if name.endswith("/bin/lemon"))
    entries["[Content_Types].xml"] = ('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' + types + '</Types>').encode()
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / f"{identity}.{version}.nupkg"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for name, data in sorted(entries.items()):
            item = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            item.create_system = 3
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = (stat.S_IFREG | (0o755 if "/bin/" in name else 0o644)) << 16
            zipped.writestr(item, data)
    digest = native.packages.sha256(archive)
    lock = {"schema": 1, "source": {"kind": "package", "feed": "https://nuget.pkg.github.com/qigao/index.json",
            "id": identity, "version": version}, "sha256": digest}
    (destination / "lemon.lock.json").write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
    (destination / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    print(json.dumps(lock, indent=2))
    return archive


def verify_archive(archive, lock_path):
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    expected = {"kind": "package", "feed": "https://nuget.pkg.github.com/qigao/index.json",
                "id": LOCK["package_id"], "version": LOCK["package_version"]}
    ensure(lock.get("schema") == 1 and lock.get("source") == expected, "unexpected Lemon package lock")
    ensure(native.packages.sha256(archive) == lock.get("sha256"), "Lemon nupkg SHA-256 mismatch")
    with zipfile.ZipFile(archive) as zipped:
        native.packages.package_metadata(zipped, LOCK["package_id"], LOCK["package_version"])
    with tempfile.TemporaryDirectory() as temporary:
        extracted = Path(temporary) / "package"
        native.archives.safe_extract(archive, extracted)
        for rid in RIDS:
            validate_root(extracted / "tools" / rid, rid)


def publish(archive, lock):
    ensure(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch" and
           os.environ.get("GITHUB_REF") == "refs/heads/master" and
           os.environ.get("GITHUB_REPOSITORY") == "qigao/vcpkg-cache",
           "publishing requires trusted manual master workflow")
    verify_archive(archive, lock)
    client = native.packages.Curl()
    feed = native.packages.NugetFeed(client)
    identity, version = LOCK["package_id"], LOCK["package_version"]
    digest = native.packages.sha256(archive)
    with tempfile.TemporaryDirectory() as temporary:
        received = Path(temporary) / "received.nupkg"
        if feed.package(identity, version, received, allow_not_found=True):
            ensure(native.packages.sha256(received) == digest, "immutable Lemon package already exists with different bytes")
            return
        transport.upload(client, transport.resource(feed), archive)
        for attempt in range(6):
            if feed.package(identity, version, received, allow_not_found=True):
                ensure(native.packages.sha256(received) == digest, "published Lemon package differs from tested archive")
                print(f"published_verified={identity}/{version} sha256={digest}")
                return
            if attempt < 5:
                time.sleep(3)
        raise ValueError("upload accepted but exact Lemon package could not be read back")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    fetch_args = commands.add_parser("fetch")
    fetch_args.add_argument("--source", required=True, type=Path)
    stage_args = commands.add_parser("stage")
    for name in ("source", "build", "output"):
        stage_args.add_argument("--" + name, required=True, type=Path)
    stage_args.add_argument("--rid", required=True, choices=RIDS)
    pack_args = commands.add_parser("pack")
    pack_args.add_argument("--root", required=True, type=Path)
    pack_args.add_argument("--output", required=True, type=Path)
    for name in ("verify", "publish"):
        command = commands.add_parser(name)
        command.add_argument("--archive", required=True, type=Path)
        command.add_argument("--lock", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "fetch": fetch(args.source)
    elif args.command == "stage": stage(args.source, args.build, args.rid, args.output)
    elif args.command == "pack": pack(args.root, args.output)
    elif args.command == "verify": verify_archive(args.archive, args.lock)
    else: publish(args.archive, args.lock)


if __name__ == "__main__":
    main()
