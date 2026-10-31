#!/usr/bin/env python3
"""Install SHA256-pinned Windows llvm-mingw and TinyCC packages; no Clang probes.

Linux/macOS use the runner's own Clang through setup-llvm-native/action.yml.
The source archive integrity check below is a download safety requirement,
NOT a compiler version, IR, ABI, executable or obfuscation test.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

LOCK = Path(__file__).resolve().parents[1] / "compiler-contracts/release-obfuscation.json"
TARGETS = {
    "x86": ("i686-w64-mingw32", "x86"),
    "x64": ("x86_64-w64-mingw32", "AMD64"),
    "armv7": ("armv7-w64-mingw32", "ARM"),
    "arm64": ("aarch64-w64-mingw32", "ARM64"),
}
HOST_ARCH = {"X64": "x64", "ARM64": "arm64"}
HOST_OS = {"Windows": "windows", "Linux": "linux", "macOS": "macos"}
MAX_ARCHIVE = 750 * 1024 * 1024
MAX_EXTRACTED = 12 * 1024 * 1024 * 1024
MAX_FILES = 100_000
HEADER_MAX = 5 * 1024 * 1024

class AdmissionError(ValueError):
    pass

def ensure(ok: bool, message: str) -> None:
    if not ok:
        raise AdmissionError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verified_download(url: str, destination: Path, expected_sha256: str, limit: int) -> None:
    ensure(bool(re.fullmatch(r"[0-9a-f]{64}", expected_sha256)), "missing source SHA256")
    parsed = urllib.parse.urlsplit(url)
    ensure(parsed.scheme == "https" and parsed.hostname in ("github.com", "raw.githubusercontent.com")
           and not parsed.username and not parsed.password and parsed.port in (None, 443),
           "untrusted initial compiler download URL")
    destination.parent.mkdir(parents=True, exist_ok=True)
    last_exc: Exception | None = None
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "qigao-vcpkg-cache-compiler-setup/1"})
            with urllib.request.urlopen(request, timeout=60) as response:
                final = urllib.parse.urlsplit(response.geturl())
                ensure(final.scheme == "https" and final.hostname in (
                    "github.com", "raw.githubusercontent.com",
                    "release-assets.githubusercontent.com", "objects.githubusercontent.com",
                    "github-releases.githubusercontent.com"),
                    "untrusted compiler download redirect")
                length = 0
                with destination.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        length += len(chunk)
                        ensure(length <= limit, "compiler download exceeds the size bound")
                        output.write(chunk)
            ensure(length > 0, "empty compiler download")
            ensure(sha256(destination) == expected_sha256,
                   "compiler download SHA256 mismatch: no fallback allowed")
            return
        except (OSError, ValueError) as exc:
            last_exc = exc
            destination.unlink(missing_ok=True)
            # A corrupt or malicious archive is not a transient connection error.
            if isinstance(exc, AdmissionError):
                break
            if attempt < 2:
                time.sleep(attempt + 1)
    raise AdmissionError(f"verified source download failed: {last_exc}")


def safe_path(name: str) -> tuple[str, ...]:
    ensure(bool(name) and not name.startswith(("/", "\\")) and "\\" not in name and
           "\x00" not in name, "unsafe absolute/backslash archive entry")
    parts = name.rstrip("/").split("/")
    ensure(bool(parts) and all(p not in ("", ".", "..") and
           ":" not in p and not p.endswith((" ", ".")) for p in parts),
           f"unsafe archive member: {name}")
    return tuple(parts)


def validate_members(members: list[tuple[str, bool, int]]) -> None:
    ensure(0 < len(members) <= MAX_FILES, "archive has no members or too many members")
    seen: dict[str, bool] = {}
    total = 0
    for name, is_directory, size in members:
        parts = safe_path(name)
        key = "/".join(parts).casefold()
        ensure(key not in seen, f"colliding archive entry: {name}")
        seen[key] = is_directory
        ensure(0 <= size <= MAX_EXTRACTED, "archive member too large")
        total += size
        ensure(total <= MAX_EXTRACTED, "archive uncompressed size exceeded")
        for i in range(1, len(parts)):
            parent = "/".join(parts[:i]).casefold()
            ensure(seen.get(parent, True), f"archive file used as parent: {name}")
    # O(number of path components), not O(number of archive members squared).
    # An archive may list child files before the (invalid) parent file.
    for key in seen:
        parts = key.split("/")
        for i in range(1, len(parts)):
            parent = "/".join(parts[:i])
            ensure(seen.get(parent, True), f"archive file has children: {parent}")


def safe_extract(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as zf:
            descriptors = []
            for entry in zf.infolist():
                mode = entry.external_attr >> 16
                ftype = stat.S_IFMT(mode)
                ensure(ftype in (0, stat.S_IFREG, stat.S_IFDIR), "zip links/devices forbidden")
                descriptors.append((entry.filename, entry.is_dir(), entry.file_size))
            validate_members(descriptors)
            for entry in zf.infolist():
                path = destination.joinpath(*safe_path(entry.filename))
                if entry.is_dir():
                    path.mkdir(parents=True, exist_ok=True)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with zf.open(entry) as source, path.open("xb") as output:
                        shutil.copyfileobj(source, output)
    elif archive.name.endswith(".tar.xz"):
        with tarfile.open(archive, "r:xz") as tf:
            members = tf.getmembers()
            descriptors = []
            for member in members:
                ensure(member.isfile() or member.isdir() or member.issym(),
                       "tar hardlinks/devices/special files forbidden")
                if member.issym():
                    ensure(member.linkname and not member.linkname.startswith(("/", "\\")) and
                           "\\" not in member.linkname,
                           "tar symlink must be relative")
                    resolved = posixpath.normpath(posixpath.join(
                        posixpath.dirname(member.name), member.linkname))
                    ensure(resolved not in ("", ".", "..") and
                           not resolved.startswith("../") and
                           not posixpath.isabs(resolved),
                           "tar symlink escapes toolchain root")
                descriptors.append((member.name, member.isdir(), member.size if member.isfile() else 0))
            validate_members(descriptors)
            # Python 3.12+ extraction filter also validates transitive links and
            # refuses unsafe owners, permissions, devices and path traversal.
            tf.extractall(destination, filter="data")
    else:
        raise AdmissionError("unsupported locked toolchain archive format")


def archive_root(stage: Path, compiler: str) -> Path:
    for candidate in [stage, *(x for x in stage.iterdir() if x.is_dir())]:
        if compiler == "tinycc-builder" and (candidate / "tcc.exe").exists():
            return candidate
        if compiler == "llvm-mingw" and (candidate / "bin").is_dir():
            return candidate
    raise AdmissionError("archive lacks expected toolchain directory")

def tool_paths(root: Path, compiler: str, target: str, host: str) -> dict[str, str]:
    if compiler == "tinycc-builder":
        name = {"x86": "i386-win32-tcc.exe",
                "x64": "tcc.exe", "arm64": "arm64-win32-tcc.exe"}[target]
        return {"cc": str(root / name)}
    prefix = TARGETS[target][0]
    ext = ".exe" if host.startswith("windows-") else ""
    binary = root / "bin"
    return {
        "cc": str(binary / (prefix + "-clang" + ext)),
        "cxx": str(binary / (prefix + "-clang++" + ext)),
        "ar": str(binary / (prefix + "-ar" + ext)),
        "ranlib": str(binary / (prefix + "-ranlib" + ext)),
        "rc": str(binary / (prefix + "-windres" + ext)),
    }

def cmake_toolchain(root: Path, target: str, paths: dict[str, str]) -> Path:
    lines = [
        "# Windows llvm-mingw / TinyCC path configuration. No compiler probes.",
        "set(CMAKE_SYSTEM_NAME Windows)",
        "set(CMAKE_SYSTEM_PROCESSOR " + TARGETS[target][1] + ")",
    ]
    for cmake_name, key in (
        ("CMAKE_C_COMPILER", "cc"), ("CMAKE_CXX_COMPILER", "cxx"),
        ("CMAKE_AR", "ar"), ("CMAKE_RANLIB", "ranlib"),
        ("CMAKE_RC_COMPILER", "rc"),
    ):
        if key in paths:
            value = paths[key].replace("\\", "/")
            ensure('"' not in value and "\n" not in value, "invalid CMake path")
            lines.append(f'set({cmake_name} "{value}")')
    output = root / "qigao-toolchain.cmake"
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return output

def append_github(path: str | None, entries: dict[str, str] | list[str]) -> None:
    if not path:
        return
    with Path(path).open("a", encoding="utf-8", newline="\n") as stream:
        if isinstance(entries, dict):
            for key, value in entries.items():
                ensure("\n" not in key + value and "\r" not in key + value,
                       "invalid action output")
                stream.write(f"{key}={value}\n")
        else:
            for value in entries:
                ensure("\n" not in value and "\r" not in value,
                       "invalid action PATH")
                stream.write(value + "\n")

def install(args: argparse.Namespace) -> dict[str, str]:
    data = json.loads(LOCK.read_text(encoding="utf-8"))
    ensure(args.compiler in ("llvm-mingw", "tinycc-builder"),
           "only Windows llvm-mingw and TinyCC use archive installer")
    ensure(args.target in TARGETS, "unsupported Windows CPU")
    ensure(args.runner_os in HOST_OS and args.runner_arch in HOST_ARCH,
           "unsupported runner")
    if args.compiler == "tinycc-builder":
        ensure(args.target != "armv7", "TinyCC ARMv7 kit unavailable")
        ensure(args.runner_os == "Windows" and args.runner_arch == "X64",
               "TinyCC setup requires Windows x64 host")
        ensure(args.build_type not in ("Release", "MinSizeRel", "RelWithDebInfo"),
               "TinyCC is not the protected Release compiler")
    source = data["sources"][args.compiler]
    tag = source["release_tag"]
    ensure(not args.version or args.version == tag,
           "Windows release archive tag differs from the selected llvm-mingw kit")
    host = HOST_OS[args.runner_os] + "-" + HOST_ARCH[args.runner_arch]
    assets = [a for a in source["assets"] if a["host"] == host or
              (host.startswith("macos-") and a["host"] == "macos-universal")]
    ensure(len(assets) == 1, "no Windows toolchain package for this host")
    item = assets[0]
    dest = args.destination.absolute()
    ensure(not dest.exists(), "toolchain destination must be fresh")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".qigao-toolchain-", dir=dest.parent) as temp:
        work = Path(temp)
        archive = work / item["name"]
        url = (f"https://github.com/{source['repository']}/releases/download/"
               f"{tag}/{item['name']}")
        verified_download(url, archive, item["sha256"], MAX_ARCHIVE)
        extracted = work / "extracted"
        safe_extract(archive, extracted)
        kit = archive_root(extracted, args.compiler)
        root = work / "installed"
        shutil.copytree(kit, root, symlinks=True)
        header = ""
        if args.compiler == "tinycc-builder":
            h = data["sources"]["obfus-h"]
            hdir = root / "share" / "obfus.h" / "include"
            headerpath = hdir / "obfus.h"
            url = (f"https://raw.githubusercontent.com/{h['repository']}/"
                   f"{h['source_commit']}/{h['header_path']}")
            verified_download(url, headerpath, h["sha256"], HEADER_MAX)
            header = str(dest / "share" / "obfus.h" / "include" / "obfus.h")
        paths = tool_paths(root, args.compiler, args.target, host)
        cmake = cmake_toolchain(root, args.target, paths)
        cmake.write_text(
            cmake.read_text(encoding="utf-8").replace(
                root.as_posix(), dest.as_posix()), encoding="utf-8")
        (root / "qigao-toolchain-source.json").write_text(json.dumps({
            "compiler": args.compiler, "host": host, "target": args.target,
            "tag": tag, "archive_sha256": item["sha256"],
        }, indent=2) + "\n", encoding="utf-8")
        root.rename(dest)
    installed = tool_paths(dest, args.compiler, args.target, host)
    outputs = {
        "root": str(dest), "cc": installed["cc"], "cxx": installed.get("cxx", ""),
        "ar": installed.get("ar", ""), "rc": installed.get("rc", ""),
        "toolchain-file": str(dest / "qigao-toolchain.cmake"),
        "target-triple": TARGETS[args.target][0],
        "version": tag, "archive-sha256": item["sha256"],
        "obfus-header": header,
        "obfus-include": str(Path(header).parent) if header else "",
    }
    append_github(args.github_output, outputs)
    env_name = "LLVM_MINGW" if args.compiler == "llvm-mingw" else "TINYCC"
    append_github(args.github_env, {
        env_name + "_ROOT": str(dest),
        env_name + "_CC": installed["cc"],
        env_name + "_TOOLCHAIN_FILE": outputs["toolchain-file"],
        "QIGAO_COMPILER_TOOLCHAIN_FILE": outputs["toolchain-file"],
        **({env_name + "_CXX": installed["cxx"]} if "cxx" in installed
           else {"TINYCC_OBFUS_INCLUDE": outputs["obfus-include"]}),
    })
    append_github(args.github_path, [
        str(dest / "bin" if args.compiler == "llvm-mingw" else dest)])
    return outputs

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True,
                        choices=("llvm-mingw", "tinycc-builder"))
    parser.add_argument("--version", default="")
    parser.add_argument("--target", required=True, choices=tuple(TARGETS))
    parser.add_argument("--build-type", default="toolchain-only")
    parser.add_argument("--runner-os", required=True, choices=tuple(HOST_OS))
    parser.add_argument("--runner-arch", required=True, choices=tuple(HOST_ARCH))
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--github-output")
    parser.add_argument("--github-env")
    parser.add_argument("--github-path")
    args = parser.parse_args()
    try:
        print(json.dumps(install(args), sort_keys=True))
        return 0
    except (AdmissionError, OSError, ValueError, KeyError) as exc:
        print("TOOLCHAIN_SETUP_FAILED: " + str(exc), file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
