#!/usr/bin/env python3
"""Download common producer inputs once, before the platform matrix starts."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


bootstrap = module("producer_bootstrap", "setup-vcpkg-curl-cache.py")
downloads = bootstrap.downloads
pkgconf = module("producer_pkgconf", "windows_pkgconf.py")


def fetch(url, destination, digest, algorithm="sha256", *, hosts=None):
    source = urlsplit(url)
    print(f"Prepare {source.hostname}{source.path}", flush=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        with destination.open("rb") as stream:
            actual = hashlib.file_digest(stream, algorithm).hexdigest()
        if actual != digest:
            raise ValueError(f"cached preparation input digest mismatch: {destination.name}")
    else:
        options = {"hash_algorithm": algorithm}
        if hosts:
            options.update(initial_hosts=hosts, redirect_hosts=hosts)
        downloads.verified_download(url, destination, digest, downloads.MAX_ARCHIVE, **options)
    return destination


def main():
    if os.environ.get("QIGAO_PREPARED_INPUTS"):
        raise ValueError("the preparation job must own external downloads")
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    selected = json.loads(os.environ["PRODUCER_MATRIX"])["include"]
    source = json.loads(subprocess.check_output(
        [sys.executable, str(ROOT / "scripts/setup-vcpkg-curl-cache.py"),
         str(ROOT), "--source-only"], text=True))
    vcpkg = Path(source["root"])
    blobs = output / "blobs"
    ports = output / "port-downloads"
    ports.mkdir(exist_ok=True)
    unix_hosts = {("Linux", "X64")}  # Preparation uses the pinned Linux tool.
    windows_hosts = set()
    mingw_hosts = set()
    cli_keys = {"Linux-x64"}
    for row in selected:
        platform = row["platform"]
        if platform.startswith("windows-"):
            arch = "ARM64" if platform == "windows-arm64" else "X64"
            windows_hosts.add(arch)
            cli_keys.add("Windows-arm64" if arch == "ARM64" else "Windows-x64")
            if platform != "windows-msvc-x64":
                mingw_hosts.add("windows-arm64" if arch == "ARM64" else "windows-x64")
        elif platform.startswith("macos-"):
            arch = "ARM64" if platform == "macos-arm64" else "X64"
            unix_hosts.add(("macOS", arch))
            cli_keys.add("Darwin-arm64" if arch == "ARM64" else "Darwin-x64")
        elif platform == "linux-arm64":
            unix_hosts.add(("Linux", "ARM64"))
            cli_keys.add("Linux-arm64")
    for host_os, host_arch in sorted(unix_hosts):
        url, digest = bootstrap.unix_tool_asset(vcpkg, host_os, host_arch)
        fetch(url, blobs / digest, digest, "sha512")
    for arch in sorted(windows_hosts):
        asset, digest = bootstrap.WINDOWS_TOOL_ASSETS[arch]
        fetch(f"https://github.com/microsoft/vcpkg-tool/releases/download/{bootstrap.WINDOWS_TOOL_TAG}/{asset}",
              blobs / digest, digest)
        url, digest, _ = pkgconf.PACKAGES["arm64" if arch == "ARM64" else "x64"]
        fetch(url, blobs / digest, digest, hosts=("files.pythonhosted.org",))
    contract = json.loads((ROOT / "compiler-contracts/release-obfuscation.json").read_text())
    compiler = contract["sources"]["llvm-mingw"]
    for asset in compiler["assets"]:
        if asset["host"] in mingw_hosts:
            fetch(f"https://github.com/{compiler['repository']}/releases/download/{compiler['release_tag']}/{asset['name']}",
                  blobs / asset["sha256"], asset["sha256"])
    catalog = json.loads((ROOT / "ports/tree-sitter-cli/sources.json").read_text())
    for asset in [catalog["license"], *[catalog["binaries"][key] for key in sorted(cli_keys)]]:
        fetch(asset["url"], ports / asset["filename"], asset["sha512"], "sha512")
    tool_hosts = {
        ("linux" if host_os == "Linux" else "osx", "arm64" if arch == "ARM64" else "x64")
        for host_os, arch in unix_hosts
    }
    tool_hosts.update(("windows", "arm64" if arch == "ARM64" else "x64")
                      for arch in windows_hosts)
    tools = json.loads((vcpkg / "scripts/vcpkg-tools.json").read_text())["tools"]
    for tool in tools:
        arch = tool.get("arch", "").replace("amd64", "x64")
        selected_host = ((tool["os"], arch) in tool_hosts if arch else
                         any(host_os == tool["os"] for host_os, _ in tool_hosts))
        if (tool["name"] in {"cmake", "ninja", "7zip", "7zr", "python3"}
                and selected_host):
            host = urlsplit(tool["url"]).hostname
            fetch(tool["url"], blobs / tool["sha512"], tool["sha512"], "sha512",
                  hosts=(host, "github.com", "release-assets.githubusercontent.com",
                         "objects.githubusercontent.com", "github-releases.githubusercontent.com"))
    if windows_hosts:
        # Read the pinned upstream NASM recipe's declared mirror and checksum.
        # No duplicate NASM version or build recipe is maintained here.
        nasm = (vcpkg / "scripts/cmake/vcpkg_find_acquire_program(NASM).cmake").read_text()
        version = re.search(r"set\(program_version ([^)]+)\)", nasm).group(1)
        filename = re.search(r'set\(download_filename "([^"]+)"\)', nasm).group(1)
        url = re.search(r'"(https://vcpkg.github.io/assets/nasm/[^"]+)"', nasm).group(1)
        digest = re.search(r"set\(download_sha512 ([0-9a-f]{128})\)", nasm).group(1)
        filename = filename.replace("${program_version}", version)
        url = url.replace("${program_version}", version)
        fetch(url, ports / filename, digest, "sha512", hosts=("vcpkg.github.io", "vcpkg.io"))

    # Use vcpkg's existing reference manifest, not a second dependency graph.
    # --only-downloads never compiles ports; architecture-specific builds remain
    # in their matrix jobs. Their source cache starts from this common input.
    url, digest = bootstrap.unix_tool_asset(vcpkg, "Linux", "X64")
    shutil.copyfile(blobs / digest, vcpkg / "vcpkg")
    (vcpkg / "vcpkg").chmod(0o755)
    (vcpkg / "vcpkg.disable-metrics").touch()
    environment = dict(os.environ, VCPKG_DOWNLOADS=ports.as_posix(),
                       VCPKG_BINARY_SOURCES="clear",
                       VCPKG_OVERLAY_PORTS=(ROOT / "ports").as_posix(),
                       VCPKG_OVERLAY_TRIPLETS=(ROOT / "triplets").as_posix())
    bootstrap.seed_lua_source(ROOT, ports)
    subprocess.run([str(vcpkg / "vcpkg"), "install", "--only-downloads",
                    "--triplet=x64-linux", "--host-triplet=x64-linux",
                    f"--x-manifest-root={ROOT}",
                    f"--x-install-root={Path(os.environ['RUNNER_TEMP']) / 'producer-download-plan'}"],
                   env=environment, check=True)
    bootstrap.run("git", "-C", str(vcpkg), "update-ref", "refs/heads/qigao-scripts", source["scripts_revision"])
    for baseline in source["baselines"]:
        bootstrap.run("git", "-C", str(vcpkg), "update-ref", f"refs/heads/qigao-baseline-{baseline}", baseline)
    artifact = output / "artifact"
    artifact.mkdir()
    shutil.copytree(blobs, artifact / "blobs")
    # Transfer raw archives only; extracted Linux tools stay in the Linux
    # preparation cache and can never become another OS's host tools.
    for path in ports.iterdir():
        if path.is_file() and path.stat().st_size:
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha512").hexdigest()
            target = artifact / "blobs" / digest
            if not target.exists():
                shutil.copyfile(path, target)
    bundle = artifact / "vcpkg.bundle"
    bootstrap.run("git", "-C", str(vcpkg), "bundle", "create", str(bundle), "--all")
    receipt = {
        "source_sha": bootstrap.run("git", "-C", str(ROOT), "rev-parse", "HEAD"),
        "scripts_revision": source["scripts_revision"],
        "cache_revision": source["cache_revision"],
        "bundle_sha256": downloads.sha256(bundle),
        "platforms": [row["platform"] for row in selected],
    }
    (artifact / "manifest.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared shared inputs for {len(selected)} platform jobs")


if __name__ == "__main__":
    main()
