#!/usr/bin/env python3
"""Install exact, SHA256-locked compiler archives for qigao composite Actions.

This is a *compiler setup*, not a Release obfuscation certification. Release
admission requires a separate build/IR/actual-runtime proof (issue #243).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

LOCK = Path(__file__).resolve().parents[1] / "compiler-contracts/release-obfuscation.json"
TARGETS = {
    "x86": ("i686-w64-mingw32", 0x014C, "x86"),
    "x64": ("x86_64-w64-mingw32", 0x8664, "AMD64"),
    "armv7": ("armv7-w64-mingw32", 0x01C4, "ARM"),
    "arm64": ("aarch64-w64-mingw32", 0xAA64, "ARM64"),
}
RELEASE = {"Release", "MinSizeRel", "RelWithDebInfo"}
HOST_ARCH = {"X64": "x64", "ARM64": "arm64"}
HOST_OS = {"Windows": "windows", "Linux": "linux", "macOS": "macos"}
MAX_ARCHIVE = 750 * 1024 * 1024
MAX_EXTRACTED = 5 * 1024 * 1024 * 1024
MAX_FILES = 100_000
HEADER_MAX = 5 * 1024 * 1024


class AdmissionError(ValueError):
    """Fail closed on unsupported host, target, or source identity."""


def ensure(test: bool, message: str) -> None:
    if not test:
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


def find_toolchain_root(staging: Path, compiler: str) -> Path:
    candidates = [staging]
    candidates.extend(p for p in staging.iterdir() if p.is_dir())
    for candidate in candidates:
        if compiler == "tinycc-builder" and (candidate / "tcc.exe").is_file():
            return candidate
        if compiler == "llvm-mingw" and (candidate / "bin").is_dir() and (
            (candidate / "bin" / "clang").exists() or
            (candidate / "bin" / "clang.exe").exists() or
            any((candidate / "bin").glob("x86_64-w64-mingw32-clang*"))
        ):
            return candidate
    raise AdmissionError(f"archive does not contain expected {compiler} compiler layout")


def pe_machine(executable: Path) -> int:
    with executable.open("rb") as f:
        header = f.read(64)
        ensure(len(header) == 64 and header[:2] == b"MZ", "missing PE/MZ executable")
        offset = struct.unpack_from("<I", header, 0x3C)[0]
        ensure(64 <= offset < 16 * 1024 * 1024, "invalid PE header offset")
        f.seek(offset)
        pe = f.read(6)
    ensure(len(pe) == 6 and pe[:4] == b"PE\x00\x00", "invalid PE signature")
    return struct.unpack_from("<H", pe, 4)[0]


def run(command: list[str], *, cwd: Path, timeout: int = 90) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, encoding="utf-8", errors="replace",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        raise AdmissionError(f"toolchain execution failed ({result.returncode}): "
                             f"{Path(command[0]).name}: {result.stderr[-1600:]}")
    return result


def compiler_paths(root: Path, compiler: str, target: str, host: str) -> dict[str, str]:
    ext = ".exe" if host.startswith("windows-") else ""
    if compiler == "llvm-mingw":
        triple = TARGETS[target][0]
        bin_dir = root / "bin"
        names = {
            "cc": f"{triple}-clang{ext}",
            "cxx": f"{triple}-clang++{ext}",
            "ar": f"{triple}-ar{ext}",
            "ranlib": f"{triple}-ranlib{ext}",
            "rc": f"{triple}-windres{ext}",
        }
        paths = {k: str(bin_dir / v) for k, v in names.items()}
    else:
        names = {"x86": "i386-win32-tcc.exe", "x64": "tcc.exe",
                 "arm64": "arm64-win32-tcc.exe"}
        paths = {"cc": str(root / names[target])}
    for key in ("cc", "cxx") if compiler == "llvm-mingw" else ("cc",):
        ensure(Path(paths[key]).is_file(), f"compiler executable missing: {paths[key]}")
    return paths


def generated_cmake(root: Path, compiler: str, target: str, paths: dict[str, str]) -> Path:
    cmake = root / "qigao-toolchain.cmake"
    architecture = TARGETS[target][2]
    lines = [
        "# Generated by qigao/vcpkg-cache. Installed compiler is SHA256-locked.",
        "set(CMAKE_SYSTEM_NAME Windows)",
        f"set(CMAKE_SYSTEM_PROCESSOR {architecture})",
    ]
    for cmake_var, key in (
        ("CMAKE_C_COMPILER", "cc"), ("CMAKE_CXX_COMPILER", "cxx"),
        ("CMAKE_AR", "ar"), ("CMAKE_RANLIB", "ranlib"), ("CMAKE_RC_COMPILER", "rc")
    ):
        if key in paths and Path(paths[key]).is_file():
            # CMake paths use forward slashes even for Windows native paths.
            value = Path(paths[key]).as_posix().replace("\\", "/")
            ensure('"' not in value and "\n" not in value, "unsafe CMake path")
            lines.append(f'set({cmake_var} "{value}")')
    if compiler == "tinycc-builder":
        lines.append("# C-only compiler: CMake C++ is intentionally not supplied.")
    cmake.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return cmake


def smoke_compiler(root: Path, compiler: str, target: str, host: str,
                   paths: dict[str, str], expected_llvm: str, verify_smoke: bool) -> str:
    scratch = root / ".qigao-smoke"
    scratch.mkdir(exist_ok=False)
    try:
        compiler_bin = paths["cc"]
        if compiler == "llvm-mingw":
            version = run([compiler_bin, "--version"], cwd=scratch, timeout=30).stdout
            ensure(re.search(r"\bclang version " + re.escape(expected_llvm) + r"\b", version) is not None,
                   f"unexpected clang version: {version[:160]}")
        else:
            version_cmd = run([compiler_bin, "-v"], cwd=scratch, timeout=30)
            version = version_cmd.stdout + version_cmd.stderr
            ensure("tcc" in version.lower(), "TinyCC identity check failed")
        if not verify_smoke:
            return "compiler-identity-only"
        src = scratch / "smoke.c"
        exe = scratch / "smoke.exe"
        src.write_text("int main(void) { return 0; }\n", encoding="ascii")
        run([compiler_bin, str(src), "-o", str(exe)], cwd=scratch)
        ensure(pe_machine(exe) == TARGETS[target][1],
               f"wrong PE machine for target {target}")
        native = ((host == "windows-x64" and target in ("x64", "x86")) or
                  (host == "windows-arm64" and target == "arm64"))
        if native:
            run([str(exe)], cwd=scratch, timeout=30)
            return "native-execution"
        return "cross-compile-pe-machine"
    finally:
        shutil.rmtree(scratch)


def github_append(filename: str | None, entries: dict[str, str] | list[str]) -> None:
    if not filename:
        return
    with Path(filename).open("a", encoding="utf-8", newline="\n") as f:
        if isinstance(entries, dict):
            for key, value in entries.items():
                ensure("\n" not in key + value and "\r" not in key + value,
                       "invalid GitHub Actions output value")
                f.write(f"{key}={value}\n")
        else:
            for entry in entries:
                ensure("\n" not in entry and "\r" not in entry, "invalid GitHub Actions PATH")
                f.write(entry + "\n")


def install(args: argparse.Namespace) -> dict[str, str]:
    lock = json.loads(args.contract.read_text(encoding="utf-8"))
    ensure(lock.get("schema_version") == 1 and
           lock.get("state") == "design-candidate-not-release-qualified",
           "expected reviewed compiler source-lock contract")
    ensure(args.compiler in ("llvm-mingw", "tinycc-builder"), "unsupported compiler")
    ensure(args.runner_os in HOST_OS and args.runner_arch in HOST_ARCH,
           "unsupported runner OS or architecture")
    host = f"{HOST_OS[args.runner_os]}-{HOST_ARCH[args.runner_arch]}"
    ensure(args.target in TARGETS, "unknown Windows target architecture")
    if args.compiler == "tinycc-builder":
        ensure(host == "windows-x64", "TinyCC-builder currently supports Windows x64 host only")
        ensure(args.target in ("x86", "x64", "arm64"), "unsupported TinyCC target")
    # Setup is permitted for ordinary development/smoke; it must never
    # advertise that an unqualified release can use a non-obfuscated compiler.
    ensure(args.build_type in ("toolchain-only", "Debug", *RELEASE),
           "unknown build configuration")
    ensure(args.build_type not in RELEASE,
           f"{args.compiler} {args.build_type} Release profile unqualified; "
           "no unprotected release fallback")
    source = lock["sources"][args.compiler]
    expected_tag = source["release_tag"]
    ensure(not args.version or args.version == expected_tag,
           f"version override must match immutable lock {expected_tag}")
    assets = [a for a in source["assets"] if a["host"] == host or
              (host.startswith("macos-") and a["host"] == "macos-universal")]
    ensure(len(assets) == 1, f"no locked {args.compiler} asset for {host}")
    asset = assets[0]
    destination = args.destination.resolve()
    ensure(not destination.exists() and not destination.is_symlink(),
           "compiler destination must be fresh, never reuse stale binaries")
    destination.parent.mkdir(parents=True, exist_ok=True)
    ensure(os.access(destination.parent, os.W_OK), "compiler install directory is not writable")

    with tempfile.TemporaryDirectory(prefix=".qigao-compiler-", dir=destination.parent) as temp:
        workspace = Path(temp)
        archive = workspace / asset["name"]
        url = (f"https://github.com/{source['repository']}/releases/download/"
               f"{expected_tag}/{asset['name']}")
        verified_download(url, archive, asset["sha256"], MAX_ARCHIVE)
        extracted = workspace / "extracted"
        safe_extract(archive, extracted)
        payload = find_toolchain_root(extracted, args.compiler)
        root = workspace / "installed"
        shutil.copytree(payload, root, symlinks=True)

        obfus_header = None
        if args.compiler == "tinycc-builder":
            protected = lock["sources"]["obfus-h"]
            header_sha = protected.get("sha256")
            ensure(bool(header_sha), "obfus.h source SHA256 must be locked")
            header = root / "share" / "obfus.h" / "include" / "obfus.h"
            url = (f"https://raw.githubusercontent.com/{protected['repository']}/"
                   f"{protected['source_commit']}/{protected['header_path']}")
            verified_download(url, header, header_sha, HEADER_MAX)
            obfus_header = header
        paths = compiler_paths(root, args.compiler, args.target, host)
        cmake = generated_cmake(root, args.compiler, args.target, paths)
        # The final action output must never point back into the temporary
        # staging directory after atomic installation.
        cmake.write_text(
            cmake.read_text(encoding="utf-8").replace(
                root.as_posix(), destination.as_posix()),
            encoding="utf-8")
        smoke = smoke_compiler(root, args.compiler, args.target, host, paths,
                               lock["sources"].get("llvm-mingw", {}).get("llvm_version", ""),
                               args.verify_smoke)
        report = {
            "compiler": args.compiler,
            "host": host,
            "target": args.target,
            "target_triple": TARGETS[args.target][0],
            "archive": asset["name"],
            "archive_sha256": asset["sha256"],
            "source_commit": source["release_commit"],
            "version": expected_tag,
            "smoke": smoke,
            "release_qualified": False,
            "obfuscator_source": (lock["sources"]["obfus-h"]["source_commit"]
                                  if obfus_header else None),
            "obfuscator_sha256": (lock["sources"]["obfus-h"]["sha256"]
                                  if obfus_header else None),
        }
        (root / "qigao-compiler-install.json").write_text(
            json.dumps(report, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        # Move only after all verification; relocate only the trusted staged prefix.
        root.rename(destination)

    final_paths = compiler_paths(destination, args.compiler, args.target, host)
    outputs = {
        "root": str(destination),
        "cc": final_paths["cc"],
        "cxx": final_paths.get("cxx", ""),
        "ar": final_paths.get("ar", ""),
        "rc": final_paths.get("rc", ""),
        "toolchain-file": str(destination / "qigao-toolchain.cmake"),
        "target-triple": TARGETS[args.target][0],
        "version": expected_tag,
        "archive-sha256": asset["sha256"],
        "smoke": smoke,
        "release-qualified": "false",
        "obfuscator-installed": "true" if args.compiler == "tinycc-builder" else "false",
        "obfus-header": str(destination / "share" / "obfus.h" / "include" / "obfus.h")
                        if args.compiler == "tinycc-builder" else "",
        "obfus-include": str(destination / "share" / "obfus.h" / "include")
                         if args.compiler == "tinycc-builder" else "",
    }
    github_append(args.github_output, outputs)
    prefix = destination / "bin" if args.compiler == "llvm-mingw" else destination
    github_append(args.github_path, [str(prefix)])
    env_prefix = "LLVM_MINGW" if args.compiler == "llvm-mingw" else "TINYCC"
    github_append(args.github_env, {
        f"{env_prefix}_ROOT": str(destination),
        f"{env_prefix}_CC": final_paths["cc"],
        f"{env_prefix}_TOOLCHAIN_FILE": outputs["toolchain-file"],
        "QIGAO_COMPILER_TOOLCHAIN_FILE": outputs["toolchain-file"],
        **({"LLVM_MINGW_CXX": final_paths["cxx"]} if args.compiler == "llvm-mingw"
           else {"TINYCC_OBFUS_HEADER": outputs["obfus-header"],
                 "TINYCC_OBFUS_INCLUDE": outputs["obfus-include"]}),
    })
    return outputs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, choices=("llvm-mingw", "tinycc-builder"))
    parser.add_argument("--version", default="")
    parser.add_argument("--target", required=True, choices=tuple(TARGETS))
    parser.add_argument("--runner-os", required=True, choices=tuple(HOST_OS))
    parser.add_argument("--runner-arch", required=True, choices=tuple(HOST_ARCH))
    parser.add_argument("--build-type", default="toolchain-only")
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--verify-smoke", action="store_true")
    parser.add_argument("--contract", type=Path, default=LOCK,
                        help="internal/test only; composite Actions always use canonical lock")
    parser.add_argument("--github-output")
    parser.add_argument("--github-path")
    parser.add_argument("--github-env")
    args = parser.parse_args(argv)
    try:
        result = install(args)
    except (AdmissionError, OSError, ValueError, KeyError, RuntimeError,
            subprocess.TimeoutExpired, tarfile.TarError, zipfile.BadZipFile) as exc:
        print(f"compiler setup denied: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({k: v for k, v in result.items()
                      if k not in ("cc", "cxx", "ar", "rc", "obfus-header", "obfus-include")},
                     sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
