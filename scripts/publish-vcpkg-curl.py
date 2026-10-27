#!/usr/bin/env python3
"""Convert exact native vcpkg files-cache ABIs to NuGet archives and push with curl.

Default is an OFFLINE packaging/round-trip qualification, with no network writes.
Publishing additionally requires --publish and a trusted producer workflow.
Never install Mono, nuget.exe or a .NET SDK to publish vcpkg binary caches.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import os
from pathlib import Path
import re
import runpy
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
import zipfile

native = runpy.run_path(str(Path(__file__).with_name("github-packages.py")),
                        run_name="qigao_native_curl_client")
Curl = native["Curl"]
NugetFeed = native["NugetFeed"]
archive_members = native["archive_members"]
cache_package = native["cache_package"]
package_metadata = native["package_metadata"]
sha256 = native["sha256"]
VERSION = re.compile(r"([0-9]+)\.([0-9]+)\.([0-9]+)-vcpkg([0-9a-f]{64})\Z")
IDENTITY = re.compile(r"[A-Za-z0-9_.+-]+\Z")
MAX_PUBLISH_SIZE = 2_000_000_000


def requested_packages(config: Path):
    root = ET.parse(config).getroot()
    if root.tag != "packages":
        raise ValueError("only canonical vcpkg packages.config is supported")
    seen = set()
    for item in root:
        if item.tag != "package" or set(item.attrib) != {"id", "version"}:
            raise ValueError("unexpected vcpkg NuGet package reference")
        package_id, version = item.attrib["id"], item.attrib["version"]
        if not IDENTITY.fullmatch(package_id) or not VERSION.fullmatch(version):
            raise ValueError(f"not an exact vcpkg package ABI: {package_id}/{version}")
        key = (package_id.casefold(), version.casefold())
        if key in seen:
            raise ValueError(f"duplicate package reference: {package_id}/{version}")
        seen.add(key)
        yield package_id, version
    if not seen:
        raise ValueError("refusing to publish an empty ABI plan")


def control_identity(data: bytes):
    block = data.decode("utf-8").split("\n\n", 1)[0]
    fields = dict(line.split(": ", 1) for line in block.splitlines()
                  if ": " in line and not line.startswith(" "))
    return fields


def nuspec(package_id: str, version: str):
    ET.register_namespace("", "http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd")
    root = ET.Element("{http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd}package")
    meta = ET.SubElement(root, "{http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd}metadata")
    for key, value in (
        ("id", package_id), ("version", version), ("authors", "qigao"),
        ("description", "Immutable native vcpkg binary cache ABI; canonical source provenance in CONTROL and BUILD_INFO"),
    ):
        ET.SubElement(meta, "{http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd}" + key).text = value
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


CONTENT_TYPES = b'''<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="nuspec" ContentType="application/octet"/>
</Types>'''
RELATIONSHIPS = b'''<?xml version="1.0" encoding="utf-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="R1" Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/PACKAGE.nuspec"/>
</Relationships>'''


def pack_archive(files_cache: Path, package_id: str, version: str,
                 output: Path) -> Path:
    match = VERSION.fullmatch(version)
    if not IDENTITY.fullmatch(package_id) or match is None:
        raise ValueError("package upload requires an exact ID and vcpkg ABI")
    abi = match[4]
    source = files_cache / abi[:2] / (abi + ".zip")
    if not source.is_file():
        raise ValueError(f"missing exact local files cache ABI: {abi}")
    if output.exists():
        raise ValueError(f"refusing to overwrite existing producer package: {output}")
    with zipfile.ZipFile(source) as z:
        items = list(archive_members(z))
        names = {x.filename for x in items}
        if not {"CONTROL", "BUILD_INFO"}.issubset(names):
            raise ValueError("vcpkg cache lacks canonical CONTROL or BUILD_INFO")
        fields = control_identity(z.read("CONTROL"))
        ident = fields.get("Package", "") + "_" + fields.get("Architecture", "")
        prefix = os.environ.get("X_VCPKG_NUGET_ID_PREFIX", "")
        allowed = {ident, "vcpkg-cache_" + ident}
        if prefix:
            if not IDENTITY.fullmatch(prefix):
                raise ValueError("invalid vcpkg package identity prefix")
            allowed.add(prefix + "_" + ident)
        if package_id not in allowed or fields.get("Abi") != abi:
            raise ValueError("vcpkg package CONTROL identity or ABI mismatch")
        for name in names:
            low = name.casefold()
            if (low in ("[content_types].xml", ".signature.p7s") or
                low.startswith(("_rels/", "package/")) or
                low.endswith(".nuspec") and "/" not in low):
                raise ValueError(f"files cache includes reserved NuGet entry: {name}")
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as out:
                for entry in items:
                    out.writestr(copy.copy(entry), z.read(entry))
                out.writestr(f"{package_id}.nuspec", nuspec(package_id, version))
                out.writestr("[Content_Types].xml", CONTENT_TYPES)
                out.writestr("_rels/.rels", RELATIONSHIPS.replace(
                    b"PACKAGE.nuspec", f"{package_id}.nuspec".encode("utf-8")))
            if not output.is_file() or output.stat().st_size > MAX_PUBLISH_SIZE:
                raise ValueError("native NuGet archive missing or exceeds GitHub 2 GB bound")
            with zipfile.ZipFile(output) as check:
                list(archive_members(check))
                package_metadata(check, package_id, version)
            # The exact HTTP downloader will recover a binary-cache ZIP with
            # identical native payloads and validated CONTROL/BUILD_INFO.
            with tempfile.TemporaryDirectory() as temp:
                rebuilt = cache_package(output, package_id, version, temp)
                with zipfile.ZipFile(rebuilt) as duplicate:
                    if {x.filename: duplicate.read(x.filename)
                        for x in archive_members(duplicate)} != {
                        x.filename: z.read(x) for x in items
                    }:
                        raise ValueError("native package round-trip changed cached bytes")
            return output
        except BaseException:
            output.unlink(missing_ok=True)
            raise


def publisher_url(client: Curl) -> str:
    resources = client.json("https://nuget.pkg.github.com/qigao/index.json")["resources"]
    paths = [r["@id"] for r in resources
             if r.get("@type") == "PackagePublish/2.0.0"]
    if len(paths) != 1:
        raise ValueError("GitHub NuGet V3 index does not publish one PackagePublish/2.0.0 resource")
    url = paths[0]
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname != "nuget.pkg.github.com"
        or parsed.username or parsed.password or parsed.port not in (None, 443)
        or not (parsed.path == "/qigao" or parsed.path.startswith("/qigao/"))
        or parsed.query or parsed.fragment):
        raise ValueError("unsafe NuGet PackagePublish URL")
    return url


def push_new(client: Curl, url: str, archive: Path) -> str:
    if not archive.is_file() or archive.stat().st_size > MAX_PUBLISH_SIZE:
        raise ValueError("publisher requires a bounded existing .nupkg")
    path = archive.resolve().as_posix()
    if any(char in path for char in '"\r\n\\'):
        raise ValueError("unsafe NuGet publish source path")
    # The form upload and API-key follow the actual NuGet PackagePublish/2.0.0
    # resource. No authentication token appears on argv, disk, or CI logs.
    config = (f'url = "{url}"\n'
              f'user = "qigao:{client.token}"\n'
              f'header = "X-NuGet-ApiKey: {client.token}"\n'
              f'form = "package=@{path};type=application/octet-stream"\n')
    result = subprocess.run([
        "curl", "--disable", "--config", "-", "--silent", "--show-error",
        "--proto", "=https", "--max-time", "900", "--connect-timeout", "30",
        "--request", "PUT", "--write-out", "%{http_code}",
        "--output", os.devnull,
    ], input=config, text=True, stdout=subprocess.PIPE,
       stderr=subprocess.PIPE, check=False)
    status = result.stdout.strip()
    if result.returncode != 0 and status not in ("409",):
        raise ValueError(f"GitHub NuGet HTTP upload failed: status={status} exit={result.returncode}")
    if status not in ("201", "202", "409"):
        raise ValueError(f"GitHub NuGet upload rejected: status={status}")
    return status


def attest_publication(client: Curl, feed: NugetFeed, package_id: str,
                       version: str, source: Path, attempts: int = 6):
    digest = sha256(source)
    with tempfile.TemporaryDirectory() as directory:
        dest = Path(directory) / "remote.nupkg"
        for attempt in range(attempts):
            found = feed.package(package_id, version, dest, allow_not_found=True)
            if found:
                remote = sha256(dest)
                if remote != digest:
                    raise ValueError(f"Published GitHub Package ID/version has different SHA256: {package_id}/{version}")
                return digest
            if attempt + 1 < attempts:
                time.sleep(min(attempt + 1, 5))
    raise ValueError(f"NuGet registry did not expose published immutable package: {package_id}/{version}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages-config", required=True, type=Path)
    parser.add_argument("--cache", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--publish", action="store_true",
                        help="Opt in to authenticated remote writes; never enabled by tests")
    args = parser.parse_args()
    packages = list(requested_packages(args.packages_config))
    args.output.mkdir(parents=True, exist_ok=True)
    built = [((name, version), pack_archive(args.cache, name, version,
                 args.output / f"{name}.{version}.nupkg"))
             for name, version in packages]
    print(f"offline_native_nupkg_plan count={len(built)}", flush=True)
    if not args.publish:
        for (name, version), path in built:
            print(f"qualified={name}/{version} sha256={sha256(path)}", flush=True)
        return 0
    if os.environ.get("GITHUB_EVENT_NAME") not in ("workflow_dispatch", "push"):
        raise ValueError("native NuGet publishing forbidden from untrusted PR event")
    if os.environ.get("GITHUB_REPOSITORY") != "qigao/vcpkg-cache":
        raise ValueError("only the canonical cache owner may publish vcpkg ABI archives")
    if os.environ.get("GITHUB_REF") != "refs/heads/master":
        raise ValueError("native publishing requires the immutable master producer")
    client = Curl()
    feed = NugetFeed(client)
    url = publisher_url(client)
    for (name, version), path in built:
        status = push_new(client, url, path)
        digest = attest_publication(client, feed, name, version, path)
        print(f"published={name}/{version} status={status} sha256={digest}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
