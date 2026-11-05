#!/usr/bin/env python3
"""Prepare pinned native Windows pkgconf without acquiring MSYS2."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import hashlib
import zipfile


VERSION = "3.0.7.post0"
# Native pkgconf binaries published by pypackaging-native/pkgconf-pypi.
# SHA256 pins cover both the wheel and its standalone executable. No pip or
# Python wrapper is installed. Select the HOST, independent of target triplet.
PACKAGES = {
    "x64": (
        "https://files.pythonhosted.org/packages/e2/53/37ee781984b17e16c9b09726c438a327b242721166213411623814b89ddf/pkgconf-3.0.7.post0-py3-none-win_amd64.whl",
        "e7906bb5ec1d0d074e397466075a8545f1c50cb11710768644f222ba8acebc7f",
        "11c7dfa127cd6a75de064c7702be5b5d8e7aca4c6dfb8043c0476f2543f227f7",
    ),
    "arm64": (
        "https://files.pythonhosted.org/packages/94/b7/8755f13caa6a1ceba992cabf6aec4684a9681457dc502925a9aeca0a7937/pkgconf-3.0.7.post0-py3-none-win_arm64.whl",
        "3716a2a2b2dca3466589b371e5bfa88bb5a4e84e4e7a3771ce14b112a0965f05",
        "4434ddb140c0c78af30ce4774bcabbdcff2607f65b5c4d4871751088c38d5d67",
    ),
}
MEMBER = "pkgconf/.bin/pkgconf.exe"

# Reuse the existing bounded, checksum-verified host-tool downloader.
_spec = importlib.util.spec_from_file_location(
    "qigao_host_download", Path(__file__).with_name("setup-compiler-toolchain.py"))
assert _spec and _spec.loader
downloads = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(downloads)


def host_arch(environment: dict[str, str]) -> str:
    raw = environment.get("PROCESSOR_ARCHITEW6432") or environment.get("PROCESSOR_ARCHITECTURE", "")
    arch = {"AMD64": "x64", "ARM64": "arm64"}.get(raw.upper())
    if arch is None:
        raise ValueError(f"unsupported Windows host architecture: {raw!r}")
    return arch


def prepare_pkgconf(temporary: Path, environment: dict[str, str] | None = None) -> dict[str, str]:
    environment = os.environ if environment is None else environment
    arch = host_arch(environment)
    url, archive_sha, executable_sha = PACKAGES[arch]
    temporary = temporary.resolve()
    root = temporary / f"qigao-pkgconf-{VERSION}-{arch}"
    executable = root / "bin/pkg-config.exe"
    if executable.exists():
        if downloads.sha256(executable) != executable_sha:
            raise ValueError("cached native pkg-config SHA256 mismatch")
    else:
        root.mkdir(parents=True, exist_ok=True)
        archive = root / url.rsplit("/", 1)[1]
        if archive.exists():
            if downloads.sha256(archive) != archive_sha:
                raise ValueError("cached native pkgconf archive SHA256 mismatch")
        else:
            downloads.verified_download(
                url, archive, archive_sha, 2 * 1024 * 1024,
                initial_hosts=("files.pythonhosted.org",),
                redirect_hosts=("files.pythonhosted.org",))
        # Read only the fixed executable entry; no archive paths are extracted.
        with zipfile.ZipFile(archive) as wheel:
            members = [info for info in wheel.infolist() if info.filename == MEMBER]
            if len(members) != 1 or not 0 < members[0].file_size <= 2 * 1024 * 1024:
                raise ValueError("native pkgconf executable missing, ambiguous or too large")
            content = wheel.read(members[0])
            if hashlib.sha256(content).hexdigest() != executable_sha:
                raise ValueError("native pkg-config executable SHA256 mismatch")
        executable.parent.mkdir(exist_ok=True)
        staged = executable.with_suffix(".tmp")
        staged.write_bytes(content)
        staged.replace(executable)
    keep = [name for name in environment.get("VCPKG_KEEP_ENV_VARS", "").split(";") if name]
    # vcpkg clears most Windows environment variables before invoking a port.
    # Preserve the native path explicitly, including for builtin triplets.
    keep = list(dict.fromkeys([*keep, "PKG_CONFIG", "QIGAO_PKGCONF_VERSION"]))
    return {
        "PKG_CONFIG": executable.as_posix(),
        "QIGAO_PKGCONF_VERSION": VERSION,
        "VCPKG_KEEP_ENV_VARS": ";".join(keep),
    }


def main() -> int:
    if os.name != "nt":
        raise ValueError("native Windows pkgconf setup requires Windows")
    values = prepare_pkgconf(Path(os.environ["RUNNER_TEMP"]))
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
        for key, value in values.items():
            if "\n" in value or "\r" in value:
                raise ValueError("newline in native pkgconf environment")
            stream.write(f"{key}={value}\n")
    print(f"Native Windows pkgconf {VERSION}: {values['PKG_CONFIG']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
