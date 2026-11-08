#!/usr/bin/env python3
"""Bootstrap the canonical shared vcpkg cache using curl-only file restoration."""
from __future__ import annotations

import importlib.util
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


# Windows' upstream bootstrap invokes tls12-download.exe. Keep the same
# released executable identity, using the shared curl downloader instead.
# Digests: https://api.github.com/repos/microsoft/vcpkg-tool/releases/tags/2026-07-27
WINDOWS_TOOL_VERSION = "2026-07-27-98d7cb0cf1f4686a3e43aa5672b6230c1d56bce8"
WINDOWS_TOOL_TAG = "2026-07-27"
WINDOWS_TOOL_ASSETS = {
    "X64": ("vcpkg.exe", "13b8175e99a884c5ad34249218754b45541a1a63f216e92603aee57a285ac741"),
    "ARM64": ("vcpkg-arm64.exe", "5e8d7acd0f3049411ad1eacd3af2a946014ed430c27010e384ee1289a8e98cbc"),
}
_spec = importlib.util.spec_from_file_location(
    "qigao_vcpkg_tool_download", Path(__file__).with_name("setup-compiler-toolchain.py"))
assert _spec and _spec.loader
downloads = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(downloads)


def bootstrap_windows_tool(root: Path, expected_version: str, host_arch: str) -> None:
    if expected_version != WINDOWS_TOOL_VERSION:
        raise ValueError("Windows vcpkg tool SHA256 lock does not match the canonical version")
    if host_arch not in WINDOWS_TOOL_ASSETS:
        raise ValueError(f"unsupported Windows vcpkg host architecture: {host_arch!r}")
    metadata = (root / "scripts/vcpkg-tool-metadata.txt").read_text(encoding="utf-8")
    tags = re.findall(r"^VCPKG_TOOL_RELEASE_TAG=([^\r\n]+)$", metadata, re.MULTILINE)
    if tags != [WINDOWS_TOOL_TAG]:
        raise ValueError("pinned vcpkg scripts disagree with the Windows tool release lock")
    asset, digest = WINDOWS_TOOL_ASSETS[host_arch]
    downloads.verified_download(
        f"https://github.com/microsoft/vcpkg-tool/releases/download/{WINDOWS_TOOL_TAG}/{asset}",
        root / "vcpkg.exe", digest, 16 * 1024 * 1024,
    )
    (root / "vcpkg.disable-metrics").touch()


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, text=True, cwd=cwd).strip()


def append_env(values: dict[str, str]) -> None:
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        for key, value in values.items():
            if "\n" in value or "\r" in value:
                raise ValueError(f"newline in environment value: {key}")
            output.write(f"{key}={value}\n")


def append_outputs(values: dict[str, str]) -> None:
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in values.items():
            if "\n" in value or "\r" in value:
                raise ValueError(f"newline in output value: {key}")
            output.write(f"{key}={value}\n")


def require_native_curl_owner(infrastructure: Path) -> None:
    """Validate the active curl-only transport, not the deprecated Mono action.

    The old action can be deleted after consumer/producer migration without
    becoming an accidental runtime dependency of the new native transport.
    """
    required = (
        ".github/actions/setup-vcpkg-curl-cache/action.yml",
        "scripts/github-packages.py",
        "scripts/restore-manifest-cache.py",
        "scripts/setup-vcpkg-curl-cache.py",
        "scripts/windows_pkgconf.py",
        "scripts/setup-compiler-toolchain.py",
    )
    for name in required:
        if not (infrastructure / name).is_file():
            raise ValueError(f"incomplete canonical curl-only cache checkout: {name}")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: setup-vcpkg-curl-cache.py <shared-cache-checkout>")

    infrastructure = Path(sys.argv[1]).resolve()
    workspace = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    temporary = Path(os.environ["RUNNER_TEMP"]).resolve()
    # Unix bootstrap consumes this configured path before any port is built.
    source_downloads = Path(os.environ.get("VCPKG_DOWNLOADS") or (workspace / "build/vcpkg-downloads")).resolve()
    source_downloads.mkdir(parents=True, exist_ok=True)
    require_native_curl_owner(infrastructure)

    scripts = (infrastructure / "vcpkg-scripts-revision.txt").read_text().strip()
    expected_tool_version = (infrastructure / "vcpkg-tool-version.txt").read_text().strip()
    contract = (infrastructure / "cache-contract-version.txt").read_text().strip()
    revision = run(
        sys.executable,
        str(infrastructure / "scripts/cache-contract-revision.py"),
        str(infrastructure),
    )
    if (not re.fullmatch(r"[0-9a-f]{40}", scripts)
            or not re.fullmatch(r"[0-9a-f]{64}", revision)
            or not contract.isdigit()
            or not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z.-]*", expected_tool_version)):
        raise ValueError("invalid canonical vcpkg cache identity")

    root = temporary / f"qigao-vcpkg-{scripts}"
    if root.exists():
        raise ValueError(f"expected a fresh vcpkg directory: {root}")
    root.mkdir()
    run("git", "-C", str(root), "init")
    run("git", "-C", str(root), "remote", "add", "origin",
        "https://github.com/microsoft/vcpkg.git")

    fetched = False
    for attempt in range(1, 4):
        result = subprocess.run(
            ["git", "-c", "protocol.version=2", "-C", str(root),
             "fetch", "--no-tags", "origin", scripts],
            check=False,
        )
        if result.returncode == 0:
            checkout = subprocess.run(
                ["git", "-C", str(root), "checkout", "--detach", "FETCH_HEAD"],
                check=False,
            )
            if checkout.returncode == 0:
                fetched = True
                break
        if attempt < 3:
            time.sleep(attempt * 2)
    if not fetched:
        raise RuntimeError("failed to fetch the exact vcpkg scripts revision after 3 attempts")

    baselines = run(
        sys.executable,
        str(infrastructure / "scripts/vcpkg-required-commits.py"),
        str(infrastructure),
        str(workspace),
    )
    for baseline in baselines.splitlines():
        if not re.fullmatch(r"[0-9a-f]{40}", baseline):
            raise ValueError("invalid vcpkg baseline")
        exists = subprocess.run(
            ["git", "-C", str(root), "cat-file", "-e", baseline + "^{commit}"],
            capture_output=True,
        )
        if exists.returncode:
            fetched_baseline = False
            for attempt in range(1, 4):
                result = subprocess.run(
                    ["git", "-c", "protocol.version=2", "-C", str(root),
                     "fetch", "--no-tags", "origin", baseline],
                    check=False,
                )
                if result.returncode == 0:
                    fetched_baseline = True
                    break
                if attempt < 3:
                    time.sleep(attempt * 2)
            if not fetched_baseline:
                raise RuntimeError(f"failed to fetch required vcpkg baseline {baseline}")
        run("git", "-C", str(root), "cat-file", "-e",
            baseline + ":versions/baseline.json")

    if (run("git", "-C", str(root), "rev-parse", "HEAD") != scripts
            or run("git", "-C", str(root), "rev-parse", "--is-shallow-repository") != "false"):
        raise ValueError("canonical vcpkg scripts/history mismatch")
    promisor = subprocess.run(
        ["git", "-C", str(root), "config", "--get", "remote.origin.promisor"],
        text=True, capture_output=True, check=False,
    )
    partial_filter = subprocess.run(
        ["git", "-C", str(root), "config", "--get", "remote.origin.partialclonefilter"],
        text=True, capture_output=True, check=False,
    )
    if promisor.returncode == 0 and promisor.stdout.strip() == "true":
        raise ValueError("canonical vcpkg checkout must not use a promisor remote")
    if partial_filter.returncode == 0 and partial_filter.stdout.strip():
        raise ValueError("canonical vcpkg checkout must not use a partial-clone filter")

    if os.name == "nt":
        bootstrap_windows_tool(root, expected_tool_version, os.environ.get("RUNNER_ARCH", ""))
    else:
        if os.environ.get("RUNNER_OS") == "Linux" and os.environ.get("RUNNER_ARCH") == "ARM64":
            # Preserve the shared cache producer's ARM64 tool-selection contract.
            # The binary cache itself is files-only, so enabling downloaded host
            # tools cannot reintroduce NuGet/Mono as a package transport.
            os.environ["VCPKG_FORCE_SYSTEM_BINARIES"] = "1"
            os.environ["VCPKG_FORCE_DOWNLOADED_BINARIES"] = "1"
            append_env({
                "VCPKG_FORCE_SYSTEM_BINARIES": "1",
                "VCPKG_FORCE_DOWNLOADED_BINARIES": "1",
            })
        bootstrap = ["sh", str(root / "bootstrap-vcpkg.sh"), "-disableMetrics"]
        subprocess.run(bootstrap, cwd=root, check=True)

    exe = root / ("vcpkg.exe" if os.name == "nt" else "vcpkg")
    version = run(str(exe), "version").splitlines()[0]
    version = version.removeprefix("vcpkg package management program version ")
    if version != expected_tool_version:
        raise ValueError(f"canonical vcpkg tool mismatch: {version} != {expected_tool_version}")

    assets = temporary / f"qigao-vcpkg-contract-v{contract}-{revision}"
    if assets.exists():
        shutil.rmtree(assets)
    assets.mkdir()
    for directory in ("ports", "triplets"):
        shutil.copytree(infrastructure / directory, assets / directory)
    (assets / "cmake").mkdir()
    shutil.copy2(
        infrastructure / "cmake/QigaoVcpkgToolchain.cmake",
        assets / "cmake/QigaoVcpkgToolchain.cmake",
    )

    cache = Path(os.environ.get("VCPKG_BINARY_CACHE") or (workspace / "build/vcpkg-binary-cache")).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    # These are unchanged upstream distribution bytes, not an alternate port.
    # vcpkg independently checks its pinned SHA-512 before using this cache.
    lua_name = "lua-5.4.8.tar.gz"
    lua_sha256 = "4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae"
    lua_source = infrastructure / "packaging/sources" / lua_name
    if hashlib.sha256(lua_source.read_bytes()).hexdigest() != lua_sha256:
        raise ValueError("pinned upstream Lua source cache digest mismatch")
    lua_cached = source_downloads / lua_name
    if lua_cached.exists():
        if hashlib.sha256(lua_cached.read_bytes()).hexdigest() != lua_sha256:
            raise ValueError("existing Lua download cache has a different digest")
    else:
        shutil.copyfile(lua_source, lua_cached)
    values = {
        "VCPKG_ROOT": root.as_posix(),
        "VCPKG_TOOL_REVISION": expected_tool_version,
        "VCPKG_SCRIPTS_REVISION": scripts,
        "VCPKG_CACHE_CONTRACT_VERSION": contract,
        "VCPKG_CACHE_REVISION": revision,
        "VCPKG_CACHE_REPOSITORY_ROOT": assets.as_posix(),
        "VCPKG_OVERLAY_PORTS": (assets / "ports").as_posix(),
        "VCPKG_OVERLAY_TRIPLETS": (assets / "triplets").as_posix(),
        "QIGAO_VCPKG_TOOLCHAIN_FILE": (assets / "cmake/QigaoVcpkgToolchain.cmake").as_posix(),
        "QIGAO_VCPKG_WINDOWS_TRIPLET": "qigao-x64-windows-llvm-mingw",
        "QIGAO_VCPKG_WINDOWS_HOST_TRIPLET": "qigao-x64-windows-llvm-mingw",
        "VCPKG_BINARY_CACHE": cache.as_posix(),
        "VCPKG_DOWNLOADS": source_downloads.as_posix(),
        "VCPKG_BINARY_SOURCES": f"clear;files,{cache.as_posix()},readwrite",
        "VCPKG_NUGET_REPOSITORY": "https://github.com/qigao/vcpkg-cache",
    }
    if "LLVM_NATIVE_CC" in os.environ:
        values.update(CC=os.environ["LLVM_NATIVE_CC"], CXX=os.environ["LLVM_NATIVE_CXX"])
    if os.name == "nt":
        from windows_pkgconf import prepare_pkgconf
        values.update(prepare_pkgconf(temporary))
    append_env(values)
    append_outputs({
        "contract_version": contract,
        "cache_revision": revision,
        "tool_revision": expected_tool_version,
        "scripts_revision": scripts,
        "toolchain_file": values["QIGAO_VCPKG_TOOLCHAIN_FILE"],
    })
    print(
        f"Configured curl-only binary cache: contract=v{contract} revision={revision} "
        f"vcpkg={expected_tool_version} scripts={scripts}"
    )
    print("VCPKG_BINARY_SOURCES uses only the local read/write files provider; no NuGet executable or Mono.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

