#!/usr/bin/env python3
"""Run the actual NuGet host payload; reject ABI requirements above the floor."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[2]
# Ubuntu 22.04 glibc and GCC 11 libstdc++ form the Linux x64 build floor.
# A hosted runner may also contain newer runtimes, so execution alone is not
# enough to detect an accidentally newer compiler or link dependency.
ABI_LIMITS = {"GLIBC": (2, 35), "GLIBCXX": (3, 4, 29), "CXXABI": (1, 3, 13)}
UNICODE_SHA256 = {
    "unicode_properties.re": "56b5f16e4e516a598125760ee7f4fae60a5db6727b8cf3dfb5f020152ef2aa21",
    "unicode_categories.re": "3d0a319806e42a7b476f9d474c104f7e734c42eeab8fb36b2b82591cd55b0689",
}
HOST_RIDS = ("linux-arm64", "linux-x64", "macos-arm64", "windows-x64")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def package_layout(archive):
    names = set(archive.namelist())
    rids = sorted({name.split("/")[1] for name in names
                   if name.startswith("tools/") and len(name.split("/")) > 2})
    if tuple(rids) != HOST_RIDS:
        raise ValueError(f"host RID set differs from the original published package: {rids}")
    for rid in rids:
        executable = "re2c.exe" if rid == "windows-x64" else "re2c"
        required = [f"tools/{rid}/bin/{executable}"]
        required += [f"tools/{rid}/share/re2c/stdlib/{name}" for name in
                     (*UNICODE_SHA256, "syntax/c")]
        for name in required:
            if name not in names:
                raise ValueError(f"missing package payload: {name}")
    return rids


def required_versions(text):
    result = {}
    names = re.findall(r"\bName:\s+(\S+)", text)
    for family, maximum in ABI_LIMITS.items():
        entries = [name for name in names if name.startswith(family + "_")]
        if not entries:
            raise ValueError(f"missing {family} version requirements in ELF report")
        parsed = []
        for name in entries:
            match = re.fullmatch(re.escape(family) + r"_(\d+(?:\.\d+)+)", name)
            if not match:
                raise ValueError(f"unrecognized ELF version requirement: {name}")
            version = tuple(int(part) for part in match[1].split("."))
            if version > maximum:
                floor = ".".join(str(part) for part in maximum)
                raise ValueError(f"{name} exceeds Linux x64 compatibility floor {family}_{floor}")
            parsed.append(version)
        result[family] = [".".join(str(part) for part in item)
                          for item in sorted(set(parsed))]
    return result


def checked(command):
    print("run: " + " ".join(str(item) for item in command), flush=True)
    result = subprocess.run(command, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, check=False,
                            env={**os.environ, "LC_ALL": "C"})
    print(result.stdout, end="", flush=True)
    result.check_returncode()
    return result.stdout


def generate_and_execute(root, work):
    exe = root / "bin/re2c"
    stdlib = root / "share/re2c/stdlib"
    hashes = {}
    for name, expected in UNICODE_SHA256.items():
        actual = hashlib.sha256((stdlib / name).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        if actual != expected:
            raise ValueError(f"packaged Unicode 17 input differs: {name}")
        hashes[name] = actual
    syntax = stdlib / "syntax/c"
    if not syntax.is_file():
        raise ValueError("packaged C syntax is missing")
    version = checked([str(exe), "--version"]).strip()
    if version != "re2c 4.6":
        raise ValueError(f"unexpected generator version: {version}")
    source = work / "unicode-host-smoke.c"
    binary = work / "unicode-host-smoke"
    checked([str(exe), "--lang", "c", "--syntax", "syntax/c",
             "--no-generation-date", "--encoding-policy", "fail", "-W", "-Werror",
             "-I", str(stdlib), "-o", str(source),
             str(ROOT / "packaging/re2c/unicode-host-smoke.re")])
    checked(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(binary)])
    smoke = checked([str(binary)]).strip()
    if smoke != "RE2C_UNICODE_HOST_SMOKE_OK utf8_cases=13 decimal_cases=4":
        raise ValueError("generated Unicode smoke did not complete")
    return {"re2c_version": version, "unicode_sha256": hashes,
            "generated_source_sha256": digest(source), "smoke": smoke}


def verify(package, version, work, expected_host):
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("this check requires a real Linux x64 host")
    os_release = platform.freedesktop_os_release()
    actual_host = os_release.get("ID", "") + "-" + os_release.get("VERSION_ID", "")
    if actual_host != expected_host:
        raise ValueError(f"expected {expected_host}, actually running on {actual_host}")
    # Reuse the canonical reader's path, symlink and duplicate-member checks.
    spec = importlib.util.spec_from_file_location("github_packages", ROOT / "scripts/github-packages.py")
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    with zipfile.ZipFile(package) as archive:
        reader.package_metadata(archive, "Qigao.Re2c.Binary", version)
        rids = package_layout(archive)
    work.mkdir(parents=True, exist_ok=False)
    reader.extract_package(package, work / "package")
    root = work / "package/tools/linux-x64"
    exe = root / "bin/re2c"
    exe.chmod(exe.stat().st_mode | 0o111)
    elf = checked(["readelf", "--version-info", "--wide", str(exe)])
    versions = required_versions(elf)
    report = {"package_version": version, "package_sha256": digest(package),
              "host_rids": rids,
              "host": platform.platform(), "os_release": os_release,
              "binary_sha256": digest(exe), "required_versions": versions}
    report.update(generate_and_execute(root, work))
    report["status"] = "passed"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--expected-host", choices=("ubuntu-22.04", "ubuntu-24.04"), required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    try:
        report = verify(args.package.resolve(), args.version, args.work.resolve(), args.expected_host)
    except Exception as error:
        report = {"status": "failed", "package_version": args.version,
                  "package_sha256": digest(args.package), "error": str(error)}
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        raise
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
