#!/usr/bin/env python3
"""Read GitHub Package NuGet V3 archives with authenticated curl; no Mono."""
from __future__ import annotations

import argparse
import copy
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import quote, urlsplit
import xml.etree.ElementTree as ET
import zipfile


class Curl:
    def __init__(self):
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if not token or any(c in token for c in '\r\n"\\'):
            raise ValueError("a valid GH_TOKEN or GITHUB_TOKEN is required")
        self.token = token

    def download(self, url, destination, accept="application/json", allow_not_found=False):
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or parsed.hostname not in
                {"api.github.com", "nuget.pkg.github.com"} or parsed.username or
                parsed.password or parsed.port not in (None, 443)):
            raise ValueError("untrusted GitHub download endpoint")
        if parsed.hostname == "nuget.pkg.github.com":
            encoded = base64.b64encode(f"qigao:{self.token}".encode()).decode()
            authorization = f"Basic {encoded}"
        else:
            authorization = f"Bearer {self.token}"
        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
            partial = Path(temporary) / "download"
            # Keep credentials off argv and disk. curl does not forward Authorization
            # to a different redirect host; credentials are never forwarded across redirects.
            config = f'header = "Authorization: {authorization}"\n'
            command = [
                "curl", "--disable", "--config", "-", "--fail", "--silent", "--show-error",
                "--location", "--proto", "=https", "--proto-redir", "=https",
                "--connect-timeout", "30", "--max-time", "900", "--retry", "3",
                "--write-out", "%{http_code}",
                "--header", f"Accept: {accept}", "--output", str(partial), url,
            ]
            result = subprocess.run(
                command, input=config, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, check=False)
            code = result.stdout[-3:] if len(result.stdout) >= 3 else ""
            if result.returncode != 0:
                if partial.exists():
                    partial.unlink()
                if allow_not_found and code == "404":
                    print(f"cache_miss={url}", flush=True)
                    return False
                if result.stderr:
                    print(result.stderr, file=sys.stderr, end="")
                raise subprocess.CalledProcessError(
                    result.returncode, command, output=result.stdout, stderr=result.stderr)
            if code and code[0] not in "23":
                if partial.exists():
                    partial.unlink()
                raise ValueError(f"unexpected GitHub HTTP status {code}")
            partial.replace(destination)
            return True

    def json(self, url):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "response.json"
            self.download(url, path)
            return json.loads(path.read_text(encoding="utf-8"))


def sha256(path):
    with Path(path).open("rb") as source:
        digest = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
        return digest.hexdigest()


def release_asset(client, repository, tag, asset, destination):
    if not re.fullmatch(r"(?:qigao/[A-Za-z0-9_.-]+|PowerShell/PowerShell)", repository):
        raise ValueError("invalid release repository")
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?", tag):
        raise ValueError("an exact release tag is required")
    release = client.json(f"https://api.github.com/repos/{repository}/releases/tags/{quote(tag)}")
    if release.get("draft") is not False or not release.get("published_at") or release.get("tag_name") != tag:
        raise ValueError("release is unpublished or has a different tag")
    matches = [item for item in release.get("assets", []) if item.get("name") == asset]
    if len(matches) != 1:
        raise ValueError(f"missing or ambiguous release asset: {repository}@{tag}/{asset}")
    item = matches[0]
    client.download(item["url"], destination, "application/octet-stream")
    digest = item.get("digest")
    if digest and digest != "sha256:" + sha256(destination):
        Path(destination).unlink()
        raise ValueError("GitHub Release asset digest mismatch")


def package_metadata(archive, package_id, version):
    specifications = [name for name in archive.namelist() if "/" not in name and name.lower().endswith(".nuspec")]
    if len(specifications) != 1:
        raise ValueError("package must contain one root nuspec")
    root = ET.fromstring(archive.read(specifications[0]))
    metadata = next((e for e in root if e.tag.rsplit("}", 1)[-1] == "metadata"), None)
    values = {} if metadata is None else {e.tag.rsplit("}", 1)[-1]: e.text for e in metadata}
    if (values.get("id", "").lower() != package_id.lower() or
            values.get("version", "").lower() != version.lower()):
        raise ValueError(f"NuGet identity mismatch: expected {package_id}/{version}")


def archive_members(archive):
    seen = set()
    for entry in archive.infolist():
        name = entry.filename
        path = PurePosixPath(name)
        if ("\\" in name or ":" in name or path.is_absolute() or
                any(p in ("", ".", "..") for p in name.rstrip("/").split("/")) or
                name.casefold().rstrip("/") in seen):
            raise ValueError(f"unsafe or duplicate archive entry: {name}")
        seen.add(name.casefold().rstrip("/"))
        if stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError(f"symlink archive entry is unsupported: {name}")
        yield entry


def nuget_semver_key(value):
    """Comparable key for the controlled GitHub Packages SemVer 2 feed."""
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?", value)
    if not match:
        raise ValueError(f"unsupported NuGet version syntax: {value!r}")
    base = tuple(int(match.group(i)) for i in range(1, 4))
    prerelease = match.group(4)
    if prerelease is None:
        return base + (1, ())
    identifiers = []
    for item in prerelease.split("."):
        if not item:
            raise ValueError(f"empty prerelease identifier: {value!r}")
        identifiers.append((0, int(item)) if item.isascii() and item.isdigit()
                           else (1, item.casefold()))
    return base + (0, tuple(identifiers))


class NugetFeed:
    def __init__(self, client):
        self.client = client
        resources = client.json("https://nuget.pkg.github.com/qigao/index.json")["resources"]
        addresses = [r["@id"] for r in resources if r.get("@type") == "PackageBaseAddress/3.0.0"]
        if len(addresses) != 1:
            raise ValueError("GitHub feed must advertise one PackageBaseAddress/3.0.0")
        self.base = addresses[0].rstrip("/")

    def package(self, package_id, version, destination, allow_not_found=False):
        for value in (package_id, version):
            if not re.fullmatch(r"[A-Za-z0-9_.+-]+", value):
                raise ValueError("invalid NuGet identity")
        identity, selected = package_id.lower(), version.lower()
        url = f"{self.base}/{identity}/{selected}/{identity}.{selected}.nupkg"
        if allow_not_found:
            downloaded = self.client.download(
                url, destination, "application/octet-stream",
                allow_not_found=True)
        else:
            downloaded = self.client.download(url, destination, "application/octet-stream")
        if downloaded is False:
            return False
        with zipfile.ZipFile(destination) as archive:
            list(archive_members(archive))
            package_metadata(archive, package_id, version)
        print(f"package={package_id} version={version} sha256={sha256(destination)}", flush=True)
        return True

    def versions(self, package_id):
        if not re.fullmatch(r"[A-Za-z0-9_.+-]+", package_id):
            raise ValueError("invalid NuGet package identity")
        data = self.client.json(f"{self.base}/{package_id.lower()}/index.json")
        versions = data.get("versions")
        if not isinstance(versions, list) or not versions or not all(isinstance(v, str) for v in versions):
            raise ValueError("GitHub feed returned no usable package versions")
        lowered = [v.lower() for v in versions]
        if len(lowered) != len(set(lowered)):
            raise ValueError("GitHub feed returned duplicate package versions")
        return versions

    def latest_stable(self, package_id):
        stable = [v for v in self.versions(package_id)
                  if re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?", v)]
        if not stable:
            raise ValueError(f"no stable GitHub Packages version exists for {package_id}")
        return max(stable, key=lambda v: tuple(int(n) for n in v.split(".")) + (0,) * (4-len(v.split("."))))

    def floating(self, package_id, requirement, destination, version_file):
        if requirement != "2.3.0-*":
            raise ValueError("only the audited literal 2.3.0-* floating requirement is supported")
        candidates = [v for v in self.versions(package_id)
                      if re.fullmatch(r"2\.3\.0-[0-9A-Za-z.-]+", v)]
        if not candidates:
            raise ValueError("GitHub feed has no 2.3.0 prerelease candidates")
        selected = max(candidates, key=nuget_semver_key)
        self.package(package_id, selected, destination)
        Path(version_file).write_text(selected + "\n", encoding="utf-8")
        print(f"floating_requirement={requirement} resolved={selected}", flush=True)
        return selected


def executable_payload(data):
    return (
        data.startswith(b"#!") or
        data.startswith(b"\x7fELF") or
        data.startswith(b"MZ") or
        data[:4] in {
            b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
            b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
            b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
        }
    )


def archive_entry_for_files_cache(entry, data):
    out = copy.copy(entry)
    mode = out.external_attr >> 16
    executable = bool(mode & 0o111) or executable_payload(data[:8])
    if executable and not entry.is_dir():
        permissions = (mode & 0o777) if mode else 0o644
        out.create_system = 3
        out.external_attr = (stat.S_IFREG | permissions | 0o111) << 16
    return out


def cache_package(nupkg, package_id, version, cache):
    match = re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-vcpkg([0-9a-f]{64})", version)
    if not match:
        raise ValueError("expected vcpkg-generated version with exact ABI")
    abi = match[1]
    destination = Path(cache) / abi[:2] / f"{abi}.zip"
    with zipfile.ZipFile(nupkg) as source:
        members = list(archive_members(source))
        package_metadata(source, package_id, version)
        core = source.read("CONTROL").decode().split("\n\n", 1)[0]
        fields = dict(line.split(": ", 1) for line in core.splitlines() if ": " in line and not line.startswith(" "))
        identity = fields.get("Package", "") + "_" + fields.get("Architecture", "")
        allowed_ids = {identity, "vcpkg-cache_" + identity}
        configured_prefix = os.environ.get("X_VCPKG_NUGET_ID_PREFIX", "")
        if configured_prefix:
            if not re.fullmatch(r"[A-Za-z0-9_.+-]+", configured_prefix):
                raise ValueError("invalid configured vcpkg NuGet prefix")
            allowed_ids.add(configured_prefix + "_" + identity)
        if fields.get("Abi") != abi or package_id not in allowed_ids:
            raise ValueError("vcpkg CONTROL identity/ABI mismatch")
        if "BUILD_INFO" not in source.namelist():
            raise ValueError("vcpkg package lacks BUILD_INFO")
        if fields.get("Package") == "gmssl" and not fields.get("Architecture", "").endswith("-ios"):
            tool_names = {"tools/gmssl/gmssl", "tools/gmssl/gmssl.exe"}
            if not tool_names.intersection(source.namelist()):
                raise ValueError("desktop GmSSL cache package lacks the required gmssl tool")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
            output = Path(temporary) / "payload.zip"
            with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as target:
                for entry in members:
                    name = entry.filename.lower()
                    if (name == "[content_types].xml" or name == ".signature.p7s" or
                            name.endswith(".nuspec") and "/" not in name or
                            name.startswith(("_rels/", "package/"))):
                        continue
                    data = source.read(entry)
                    target_entry = archive_entry_for_files_cache(entry, data)
                    target.writestr(target_entry, data)
            output.replace(destination)
    return destination


def extract_package(nupkg, destination):
    with zipfile.ZipFile(nupkg) as archive:
        members = list(archive_members(archive))
        for entry in members:
            archive.extract(entry, destination)
            mode = entry.external_attr >> 16
            if mode and not entry.is_dir():
                (Path(destination) / entry.filename).chmod(mode & 0o777)


def reject_missing_exact_archive(feed, package_id, version):
    """Classify an actual archive HTTP 404 with the SAME authenticated feed.

    NuGet package-download 404 may mean an unlisted immutable ABI, a
    registry visibility/authorization failure, or an inconsistency between
    advertised version metadata and the archive endpoint. Neither case
    permits a source rebuild, substitute ABI, second credential, or a silent
    success. Probe only the single failed package's version metadata; never
    query every package or introduce a separate CI preflight.
    """
    try:
        visible_versions = feed.versions(package_id)
    except Exception as error:
        raise ValueError(
            f"exact NuGet archive returned HTTP 404: {package_id}/{version}; "
            "the same credential also could not read its NuGet V3 version "
            "index. Package visibility/Actions access or registry availability "
            "is unverified; do not assume the immutable ABI was unpublished"
        ) from error
    if version.lower() in {value.lower() for value in visible_versions}:
        raise ValueError(
            f"exact NuGet archive returned HTTP 404: {package_id}/{version}, "
            "but the SAME authenticated feed advertises this precise version. "
            "The registry's archive delivery or package read authorization "
            "is inconsistent; never rebuild or switch ABI"
        )
    raise ValueError(
        f"exact NuGet archive returned HTTP 404: {package_id}/{version}, "
        "and the SAME credential's NuGet V3 package index does not list that "
        "version. Verify immutable package publication AND Actions package "
        "access; 404 alone does not distinguish removal from denied access"
    )


def restore_cache(feed, config, cache):
    root = ET.parse(config).getroot()
    if root.tag != "packages":
        raise ValueError("invalid vcpkg packages.config")
    total = restored = misses = 0
    with tempfile.TemporaryDirectory() as temporary:
        for item in root:
            if item.tag != "package":
                raise ValueError("unexpected packages.config element")
            total += 1
            package_id, version = item.attrib["id"], item.attrib["version"]
            path = Path(temporary) / "package.nupkg"
            if not feed.package(package_id, version, path, allow_not_found=True):
                # Stop at the first exact miss. Historically all 15 packages
                # were reported missing when one workflow GITHUB_TOKEN could
                # not read ANY archives; that is not evidence of 15 deleted
                # immutable packages. Keep the same token and no fallback.
                reject_missing_exact_archive(feed, package_id, version)
            cache_package(path, package_id, version, cache)
            restored += 1
    print(
        f"cache_restore_summary total={total} restored={restored} misses={misses}",
        flush=True)
    return restored, misses


RE2C_HOSTS = {
    ("Linux", "X64"): "linux-x64", ("Linux", "ARM64"): "linux-arm64",
    ("macOS", "X64"): "macos-x64", ("macOS", "ARM64"): "macos-arm64",
    ("Windows", "X64"): "windows-x64",
}


def exact_re2c_version(value):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise ValueError("re2c requires an exact three-component package version")
    return value


def exact_re2c_sha256(value):
    if not re.fullmatch(r"[0-9a-fA-F]{64}", value):
        raise ValueError("re2c requires the exact package SHA-256 (64 hexadecimal digits)")
    return value.lower()


def re2c_package_members(archive, version, rid):
    """Preflight the entire package before creating or executing any payload."""
    members = list(archive_members(archive))
    files = {}
    for entry in members:
        name = entry.filename.rstrip("/")
        parts = name.split("/")
        mode = stat.S_IFMT(entry.external_attr >> 16)
        if (entry.orig_filename != entry.filename or
                any(any(ord(c) < 32 or c in '<>"|?*' for c in part) or part.endswith((".", " ")) or
                    PureWindowsPath(part).is_reserved() for part in parts) or
                mode not in (0, stat.S_IFREG, stat.S_IFDIR) or
                mode == stat.S_IFDIR and not entry.is_dir() or
                mode == stat.S_IFREG and entry.is_dir()):
            raise ValueError(f"unsafe re2c package member: {entry.filename}")
        if not entry.is_dir():
            files[name] = entry
    file_names = {name.casefold() for name in files}
    for entry in members:
        if any(str(parent).casefold() in file_names
               for parent in PurePosixPath(entry.filename.rstrip("/")).parents):
            raise ValueError(f"file used as re2c package directory: {entry.filename}")

    specs = [name for name in files if "/" not in name and name.lower().endswith(".nuspec")]
    if len(specs) != 1:
        raise ValueError("re2c package must contain one regular root nuspec")
    root = ET.fromstring(archive.read(specs[0]))
    metadata = [e for e in root if e.tag.rsplit("}", 1)[-1] == "metadata"]
    if root.tag.rsplit("}", 1)[-1] != "package" or len(metadata) != 1:
        raise ValueError("ambiguous re2c NuGet metadata")
    for key, expected in (("id", "Qigao.Re2c.Binary"), ("version", version)):
        values = [e for e in metadata[0] if e.tag.rsplit("}", 1)[-1] == key]
        if (len(values) != 1 or len(values[0]) or
                (values[0].text or "").lower() != expected.lower()):
            raise ValueError(f"re2c NuGet identity mismatch: expected {key}={expected}")

    payload_rids = {PurePosixPath(name).parts[1] for name in files
                    if name.startswith("tools/") and len(PurePosixPath(name).parts) > 2}
    if not payload_rids <= set(RE2C_HOSTS.values()):
        raise ValueError("re2c package contains an unrecognized host payload")
    # Validate all included host payloads, and require the selected host. A
    # missing RID must not select another architecture or a system executable.
    for host in payload_rids | {rid}:
        binary = "re2c.exe" if host == "windows-x64" else "re2c"
        for suffix in (f"bin/{binary}", "share/re2c/stdlib/syntax/c",
                       "share/re2c/stdlib/unicode_categories.re",
                       "share/re2c/stdlib/unicode_properties.re"):
            required = f"tools/{host}/{suffix}"
            if required not in files or files[required].file_size == 0:
                raise ValueError(f"missing re2c package file: {required}")
    return members


def restore_re2c(feed, destination, version, expected_sha256):
    version = exact_re2c_version(version)
    expected_sha256 = exact_re2c_sha256(expected_sha256)
    host = (os.environ.get("RUNNER_OS"), os.environ.get("RUNNER_ARCH"))
    if host not in RE2C_HOSTS:
        raise ValueError(f"unsupported re2c runner host: {host}")
    rid = RE2C_HOSTS[host]
    destination = Path(destination).absolute()
    if any(c in destination.as_posix() for c in "\r\n"):
        raise ValueError("invalid re2c destination for environment export")
    if destination.exists() or destination.is_symlink():
        raise ValueError("re2c destination must not already exist")
    environment = os.environ["GITHUB_ENV"]
    search_path = os.environ["GITHUB_PATH"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="verified-re2c-", dir=destination.parent) as temporary:
        stage = Path(temporary)
        nupkg = stage / "re2c.nupkg"
        identity = "qigao.re2c.binary"
        # Download the exact identity without consulting any version list. The
        # digest is checked BEFORE parsing metadata or extracting ZIP members.
        url = f"{feed.base}/{identity}/{version}/{identity}.{version}.nupkg"
        feed.client.download(url, nupkg, "application/octet-stream")
        if sha256(nupkg) != expected_sha256:
            raise ValueError("re2c package SHA-256 mismatch")
        with zipfile.ZipFile(nupkg) as archive:
            members = re2c_package_members(archive, version, rid)
            for entry in members:
                archive.extract(entry, stage / "package")
                mode = entry.external_attr >> 16
                if mode and not entry.is_dir():
                    (stage / "package" / entry.filename).chmod(mode & 0o777)
        staged_root = stage / "package" / "tools" / rid
        exe = staged_root / "bin" / ("re2c.exe" if rid == "windows-x64" else "re2c")
        exe.chmod(exe.stat().st_mode | 0o111)
        subprocess.run([str(exe), "--version"], check=True)
        # No destination publication or environment change on verification or
        # execution failure; stale files cannot satisfy required payload checks.
        stage.rename(destination)
    root = destination / "package" / "tools" / rid
    with open(environment, "a", encoding="utf-8") as output:
        output.write(f"RE2C_ROOT={root.as_posix()}\nRE2C_PACKAGE_VERSION={version}\n"
                     f"RE2C_PACKAGE_SHA256={expected_sha256}\n")
    with open(search_path, "a", encoding="utf-8") as output:
        output.write(f"{(root / 'bin').as_posix()}\n")
    print(f"package=Qigao.Re2c.Binary version={version} sha256={expected_sha256}", flush=True)


def restore_windows_powershell(client, destination):
    # Shared cache warm run 38989476938 used runner image 20261007.264.1.
    # vcpkg includes PowerShell's version in every Windows port ABI; the newer
    # hosted image's 7.6.7 cannot consume the packages built with 7.6.6.
    version = "7.6.6"
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / "powershell.zip"
    release_asset(client, "PowerShell/PowerShell", f"v{version}",
                  f"PowerShell-{version}-win-x64.zip", archive)
    expected_digest = "02fe458be20493fbdf43f61ea20610b811ee6c738ab1676c61b9cfcd1a33c860"
    if sha256(archive) != expected_digest:
        raise ValueError("pinned Windows cache PowerShell archive digest mismatch")
    extract_package(archive, destination / "package")
    root = destination / "package"
    actual = subprocess.check_output([str(root / "pwsh.exe"), "-NoLogo", "-NoProfile",
                                      "-Command", "$PSVersionTable.PSVersion.ToString()"], text=True).strip()
    if actual != version:
        raise ValueError("Windows cache PowerShell version mismatch")
    with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as output:
        output.write(root.as_posix() + "\n")
    print(f"Windows cache PowerShell={version} sha256={sha256(archive)}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    release = commands.add_parser("release")
    for name in ("repository", "tag", "asset", "destination"):
        release.add_argument(name)
    cache = commands.add_parser("cache")
    cache.add_argument("config")
    cache.add_argument("destination")
    package = commands.add_parser("package")
    package.add_argument("package_id")
    package.add_argument("version")
    package.add_argument("destination")
    latest = commands.add_parser("latest")
    latest.add_argument("package_id")
    latest.add_argument("destination")
    latest.add_argument("version_file")
    floating = commands.add_parser("floating")
    floating.add_argument("package_id")
    floating.add_argument("requirement")
    floating.add_argument("destination")
    floating.add_argument("version_file")
    extract = commands.add_parser("extract")
    extract.add_argument("archive")
    extract.add_argument("destination")
    re2c = commands.add_parser("re2c")
    re2c.add_argument("destination")
    re2c.add_argument("--version", required=True, type=exact_re2c_version)
    re2c.add_argument("--sha256", required=True, type=exact_re2c_sha256)
    powershell = commands.add_parser("windows-powershell")
    powershell.add_argument("destination")
    args = parser.parse_args()
    if args.command == "extract":
        extract_package(args.archive, args.destination)
        return
    client = Curl()
    if args.command == "release":
        release_asset(client, args.repository, args.tag, args.asset, args.destination)
    elif args.command == "cache":
        restored, misses = restore_cache(NugetFeed(client), args.config, args.destination)
        if misses:
            raise ValueError(f"{misses} exact GitHub Packages cache artifacts were unavailable; no NuGet/Mono or ABI fallback")
    elif args.command == "package":
        NugetFeed(client).package(args.package_id, args.version, args.destination)
    elif args.command == "floating":
        NugetFeed(client).floating(
            args.package_id, args.requirement, args.destination, args.version_file)
    elif args.command == "latest":
        feed = NugetFeed(client)
        version = feed.latest_stable(args.package_id)
        feed.package(args.package_id, version, args.destination)
        Path(args.version_file).write_text(version + "\n", encoding="utf-8")
        print(f"latest_stable={args.package_id}/{version}", flush=True)
    elif args.command == "re2c":
        restore_re2c(NugetFeed(client), args.destination, args.version, args.sha256)
    else:
        restore_windows_powershell(client, args.destination)


if __name__ == "__main__":
    main()
