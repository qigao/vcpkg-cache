#!/usr/bin/env python3
"""Qualify/publish exact vcpkg ABI ZIPs to GitHub NuGet V3 using curl only.

No Mono, nuget.exe, dotnet restore, or NuGet binary-source provider is run.
Publishing is an explicit opt-in. Never derive an ABI from a package name or
silently rebuild missing binary cache artifacts.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr
import zipfile


ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("qigao_github_packages", ROOT / "github-packages.py")
assert SPEC and SPEC.loader
packages = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packages)
ABI_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+-vcpkg([0-9a-f]{64})$")
IDENTITY = re.compile(r"^[A-Za-z0-9_.+-]+$")


def identify_source(archive: Path, package_id: str, version: str) -> str:
    match = ABI_VERSION.fullmatch(version)
    if not match or not IDENTITY.fullmatch(package_id):
        raise ValueError("publisher requires a canonical vcpkg NuGet ID and 64-hex ABI")
    abi = match[1]
    with zipfile.ZipFile(archive) as source:
        names = list(packages.archive_members(source))
        if not names or "CONTROL" not in source.namelist() or "BUILD_INFO" not in source.namelist():
            raise ValueError("vcpkg files cache ZIP must include CONTROL and BUILD_INFO")
        control = source.read("CONTROL").decode("utf-8").split("\n\n", 1)[0]
        values = {}
        for line in control.splitlines():
            if ": " in line and not line.startswith(" "):
                key, value = line.split(": ", 1)
                if key in values:
                    raise ValueError(f"duplicated CONTROL field: {key}")
                values[key] = value
        if values.get("Abi") != abi:
            raise ValueError("binary ZIP's CONTROL ABI differs from exact NuGet version")
        identity = values.get("Package", "") + "_" + values.get("Architecture", "")
        accepted = {identity, "vcpkg-cache_" + identity}
        prefix = os.getenv("X_VCPKG_NUGET_ID_PREFIX")
        if prefix:
            if not IDENTITY.fullmatch(prefix):
                raise ValueError("unsafe vcpkg NuGet prefix")
            accepted.add(prefix + "_" + identity)
        if package_id not in accepted:
            raise ValueError("vcpkg package ID does not match CONTROL Package/Architecture")
        if any(i.filename.lower().endswith(".nuspec") for i in names):
            raise ValueError("source binary cache ZIP must not contain NuGet metadata")
        if any(i.filename == "[Content_Types].xml" or i.filename.startswith("_rels/")
               for i in names):
            raise ValueError("source binary cache ZIP must not carry OPC metadata")
        if len(source.read("BUILD_INFO")) == 0:
            raise ValueError("vcpkg cache BUILD_INFO is empty")
    return abi


def entries_digest(archive: Path) -> str:
    """Payload equality independent of ZIP compression/timestamps/repacking."""
    digest = hashlib.sha256()
    with zipfile.ZipFile(archive) as source:
        entries = sorted(packages.archive_members(source), key=lambda x: x.filename)
        if not entries:
            raise ValueError("empty archive")
        for entry in entries:
            if entry.is_dir():
                continue
            data = source.read(entry.filename)
            encoded = entry.filename.encode("utf-8")
            digest.update(len(encoded).to_bytes(4, "big"))
            digest.update(encoded)
            digest.update(len(data).to_bytes(8, "big"))
            digest.update(data)
    return digest.hexdigest()


def metadata_entry(name: str) -> zipfile.ZipInfo:
    item = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    item.create_system = 3
    item.external_attr = 0o100644 << 16
    item.compress_type = zipfile.ZIP_DEFLATED
    return item


def build_nupkg(binary_zip: Path, package_id: str, version: str, destination: Path) -> None:
    identify_source(binary_zip, package_id, version)
    # NuGet .nupkg uses the OPC relationships/manifest convention. Contents
    # from the native files cache are copied byte-for-byte without relinking.
    manifest_name = f"{package_id}.nuspec"
    nuspec = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">\n'
        '<metadata><id>' + escape(package_id) + '</id><version>' + escape(version)
        + '</version><authors>qigao</authors>'
        '<description>Immutable native vcpkg package with exact compiler ABI</description>'
        '<repository type="git" url="https://github.com/qigao/vcpkg-cache" />'
        '</metadata></package>\n'
    )
    # OPC requires a MIME declaration for every unique file extension and an
    # explicit PartName override for extensionless CONTROL / BUILD_INFO.
    with zipfile.ZipFile(binary_zip) as original:
        members = sorted(packages.archive_members(original), key=lambda e: e.filename)
    types = {
        "rels": "application/vnd.openxmlformats-package.relationships+xml",
        "nuspec": "application/octet",
        "xml": "application/xml",
    }
    overrides = set()
    for member in members:
        if member.is_dir():
            continue
        basename = member.filename.rsplit("/", 1)[-1]
        extension = basename.rsplit(".", 1)[-1] if "." in basename and not basename.startswith(".") else ""
        if extension and re.fullmatch(r"[a-zA-Z0-9_-]+", extension):
            types.setdefault(extension.lower(), "application/octet-stream")
        else:
            overrides.add(member.filename)
    type_parts = [
        "<Default Extension=" + quoteattr(extension) + " ContentType="
        + quoteattr(mime) + "/>"
        for extension, mime in sorted(types.items())
    ]
    type_parts += [
        "<Override PartName=" + quoteattr("/" + name)
        + ' ContentType="application/octet-stream"/>'
        for name in sorted(overrides)
    ]
    types_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        + "".join(type_parts) + '</Types>'
    )
    relationships_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" '
        'Target="/' + escape(manifest_name) + '" Id="R0"/>'
        '</Relationships>'
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(binary_zip) as binary, zipfile.ZipFile(
        destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
    ) as out:
        for name, content in (
            ("[Content_Types].xml", types_xml),
            ("_rels/.rels", relationships_xml),
            (manifest_name, nuspec),
        ):
            out.writestr(metadata_entry(name), content.encode("utf-8"))
        for entry in sorted(packages.archive_members(binary), key=lambda e: e.filename):
            out.writestr(copy.copy(entry), binary.read(entry))
    with zipfile.ZipFile(destination) as candidate:
        packages.package_metadata(candidate, package_id, version)
        list(packages.archive_members(candidate))


def check_roundtrip(binary_zip: Path, nupkg: Path, package_id: str, version: str) -> str:
    original = entries_digest(binary_zip)
    with tempfile.TemporaryDirectory() as temp:
        roundtrip = packages.cache_package(nupkg, package_id, version, temp)
        reconstructed = entries_digest(roundtrip)
        if original != reconstructed:
            raise ValueError("NuGet archive roundtrip changed native vcpkg payload")
    return original


def resource(feed: packages.NugetFeed) -> str:
    resources = feed.client.json("https://nuget.pkg.github.com/qigao/index.json")["resources"]
    endpoints = []
    for record in resources:
        kind = record.get("@type")
        if kind == "PackagePublish/2.0.0" or (
            isinstance(kind, list) and "PackagePublish/2.0.0" in kind
        ):
            endpoints.append(record["@id"])
    if len(endpoints) != 1:
        raise ValueError("NuGet V3 registry must advertise exactly one PackagePublish resource")
    uri = urlsplit(endpoints[0])
    if (uri.scheme != "https" or uri.hostname != "nuget.pkg.github.com"
            or uri.username or uri.password or uri.port not in (None, 443)
            or not uri.path.startswith("/qigao/") or uri.query or uri.fragment):
        raise ValueError("untrusted GitHub Packages publish endpoint")
    return endpoints[0]


def upload(client: packages.Curl, endpoint: str, archive: Path) -> None:
    """NuGet PackagePublish/2.0.0 uses multipart PUT; no credential on argv."""
    encoded = base64.b64encode(f"qigao:{client.token}".encode()).decode()
    config = (f'header = "Authorization: Basic {encoded}"\n'
              f'header = "X-NuGet-ApiKey: {client.token}"\n')
    # No redirects and no automated retry of a PUT. A server interruption
    # must be reconciled with a subsequent package GET before retrying.
    with tempfile.TemporaryDirectory() as temp:
        response = Path(temp) / "response"
        command = [
            "curl", "--disable", "--config", "-", "--silent", "--show-error",
            "--proto", "=https", "--connect-timeout", "30", "--max-time", "900",
            "--request", "PUT",
            "--form", f"package=@{archive};type=application/octet-stream",
            "--write-out", "%{http_code}", "--output", str(response), endpoint,
        ]
        result = subprocess.run(command, input=config, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        status = result.stdout[-3:]
        if result.returncode != 0 or status not in ("201", "202"):
            raise ValueError(f"NuGet V3 publish rejected or ambiguous: HTTP {status}, curl={result.returncode}")
    print(f"NuGet V3 publisher accepted uploaded payload SHA256={packages.sha256(archive)}", flush=True)


def publish(feed: packages.NugetFeed, package_id: str, version: str,
            native_zip: Path, allow_write: bool) -> str:
    abi = identify_source(native_zip, package_id, version)
    with tempfile.TemporaryDirectory() as temporary:
        candidate = Path(temporary) / f"{package_id}.{version}.nupkg"
        build_nupkg(native_zip, package_id, version, candidate)
        expected = check_roundtrip(native_zip, candidate, package_id, version)
        existing = Path(temporary) / "existing.nupkg"
        if feed.package(package_id, version, existing, allow_not_found=True):
            # check_roundtrip itself rejects a mismatched payload before it
            # returns any digest. Preserve a specific immutable-conflict
            # diagnostic rather than misreporting a structurally valid,
            # differently built package as an OPC/ZIP conversion failure.
            try:
                received = check_roundtrip(native_zip, existing, package_id, version)
            except ValueError as exc:
                raise ValueError(
                    "immutable GitHub Package exists with DIFFERENT native ABI payload"
                ) from exc
            if received != expected:
                raise ValueError("immutable GitHub Package exists with DIFFERENT native ABI payload")
            print(f"already_published={package_id}/{version} sha256={expected}", flush=True)
            return "verified-existing"
        if not allow_write:
            print(f"publish_dry_run={package_id}/{version} abi={abi} payload_sha256={expected}", flush=True)
            return "dry-run"
        # Resolve the NuGet V3 service index; never guess the upload endpoint.
        upload(feed.client, resource(feed), candidate)
        # GitHub Packages publishing is eventually consistent. Every probe
        # checks the exact requested version and rejects wrong bytes.
        import time
        for attempt in range(6):
            if feed.package(package_id, version, existing, allow_not_found=True):
                verified = check_roundtrip(native_zip, existing, package_id, version)
                if verified != expected:
                    raise ValueError("published GitHub package differs from originating native ABI")
                print(f"published_verified={package_id}/{version} sha256={expected}", flush=True)
                return "published"
            if attempt != 5:
                time.sleep(3)
        raise ValueError("upload accepted but exact GitHub package was not verified (no false success)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages-config", type=Path, required=True,
                        help="vcpkg --x-write-nuget-packages-config exact ABI plan")
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--publish", action="store_true",
                        help="explicitly authorize upload; otherwise verify/dry-run")
    args = parser.parse_args()
    root = ET.parse(args.packages_config).getroot()
    if root.tag != "packages":
        raise ValueError("expected native vcpkg-generated packages.config")
    todo = []
    seen = set()
    for node in root:
        if node.tag != "package" or set(node.attrib) != {"id", "version"}:
            raise ValueError("unexpected native package entry")
        name, version = node.attrib["id"], node.attrib["version"]
        match = ABI_VERSION.fullmatch(version)
        if not match or not IDENTITY.fullmatch(name):
            raise ValueError("noncanonical package ID / immutable vcpkg version")
        identity = (name.lower(), version.lower())
        if identity in seen:
            raise ValueError("duplicate package/version cannot be published")
        seen.add(identity)
        abi = match[1]
        archive = args.cache / abi[:2] / f"{abi}.zip"
        if not archive.is_file():
            raise ValueError(f"native vcpkg cache artifact is absent for {name}/{version}")
        identify_source(archive, name, version)
        todo.append((name, version, archive))
    if not todo:
        raise ValueError("publisher requires a nonempty exact ABI package plan")
    feed = packages.NugetFeed(packages.Curl())
    counters = {"verified-existing": 0, "dry-run": 0, "published": 0}
    for name, version, archive in todo:
        counters[publish(feed, name, version, archive, args.publish)] += 1
    print(f"publish_summary total={len(todo)} verified={counters['verified-existing']} "
          f"dry_run={counters['dry-run']} uploaded={counters['published']}", flush=True)


if __name__ == "__main__":
    main()
