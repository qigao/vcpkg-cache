#!/usr/bin/env python3
"""Validate immutable, fail-closed Release compiler/obfuscation profiles.

This selector validates *policy*, not whether obfuscation actually ran.
A real release additionally needs CI-produced build/IR/native execution proofs.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

DEFAULT_CONTRACT = (
    Path(__file__).resolve().parents[2]
    / "compiler-contracts"
    / "release-obfuscation.json"
)
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
HOSTS = {
    "windows-x64", "windows-arm64", "linux-x64", "linux-arm64",
    "macos-x64", "macos-arm64",
}
TARGETS = {
    "windows-x86", "windows-x64", "windows-arm64",
    "linux-x64", "linux-arm64", "macos-x64", "macos-arm64",
}
BACKENDS = {
    "tinycc-builder": "obfus-h",
    "llvm-mingw": "obfuscator-llvm",
    "llvm-native": "obfuscator-llvm",
}


class PolicyError(ValueError):
    """An invalid or unqualified release must fail, not fall back."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PolicyError(message)


def load_contract(path: Path = DEFAULT_CONTRACT) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    validate_contract(data)
    return data


def asset_for_host(source: dict[str, Any], host: str) -> dict[str, Any] | None:
    candidates = [host]
    if host.startswith("macos-"):
        candidates.append("macos-universal")
    for asset in source.get("assets", []):
        if asset["host"] in candidates:
            return asset
    return None


def validate_contract(data: dict[str, Any]) -> None:
    require(data.get("schema_version") == 1, "unexpected compiler contract version")
    require(data.get("scope") == "first-party-native-release-targets",
            "compiler contract must not rewrite third-party dependencies")
    require(data.get("on_unqualified_release") == "fail", "release fallback is forbidden")
    require(data.get("on_unsupported_target") == "fail", "target fallback is forbidden")
    release = data.get("release_configs")
    baseline = data.get("baseline_configs")
    require(release == ["Release", "MinSizeRel"], "Release/MinSizeRel must stay protected")
    require(baseline == ["Debug", "RelWithDebInfo"], "Debug/RelWithDebInfo must stay baseline")
    sources = data.get("sources")
    require(isinstance(sources, dict), "missing immutable source locks")

    for name in ("tinycc-builder", "obfus-h", "llvm-mingw",
                 "llvm-native", "obfuscator-llvm"):
        require(name in sources, f"missing upstream source: {name}")
    for name, field in (
        ("tinycc-builder", "release_commit"),
        ("obfus-h", "source_commit"),
        ("llvm-mingw", "release_commit"),
        ("obfuscator-llvm", "source_commit"),
    ):
        require(bool(COMMIT.fullmatch(str(sources[name].get(field, "")))),
                f"{name}.{field} must be pinned to 40 lowercase hex digits")
    require(sources["llvm-mingw"].get("crt") == "ucrt",
            "llvm-mingw UCRT ABI must not alias MSVC or MSVCRT")
    require(sources["llvm-mingw"].get("llvm_version") == "23.1.4",
            "LLVM release compiler version changed; review plugin ABI")
    require(sources["obfuscator-llvm"].get("llvm_candidate_major") == 23,
            "obfuscator plugin ABI must be explicitly revisited for new LLVM major")
    require(sources["obfuscator-llvm"].get("load_flag") == "-fpass-plugin",
            "LLVM plugin must be loaded in compilation")
    pipeline = sources["obfuscator-llvm"].get("required_passes", {})
    require(isinstance(pipeline, dict) and
            bool(pipeline.get("LLVM_OBF_SCALAROPTIMIZERLATE_PASSES")),
            "LLVM obfuscator requires a nonempty, recorded real pass pipeline")
    require(sources["obfus-h"].get("supported_targets") ==
            ["windows-x86", "windows-x64"],
            "upstream obfus.h is only admitted for Windows x86/x64")
    tcc_opts = sources["obfus-h"].get("options", {})
    require(tcc_opts.get("OBFH_DISABLE_ANY_OBFUSCATION") == 0,
            "obfus.h release disabling is forbidden")
    require(tcc_opts.get("OBFH_FAKE_SIGNATURES") == 0,
            "do not introduce fake malware/packer signatures")

    for name in ("tinycc-builder", "llvm-mingw"):
        assets = sources[name].get("assets")
        require(isinstance(assets, list) and len(assets) > 0,
                f"{name} lacks download hash locks")
        seen_hosts = set()
        for asset in assets:
            host, filename, digest = (
                asset.get("host"), asset.get("name"), asset.get("sha256"))
            require(host in HOSTS or host == "macos-universal",
                    f"{name}: unrecognized host {host}")
            require(host not in seen_hosts, f"{name}: repeated host {host}")
            seen_hosts.add(host)
            require(isinstance(filename, str) and
                    (filename.endswith(".zip") or filename.endswith(".tar.xz")) and
                    "latest" not in filename.lower(),
                    f"{name}: expected immutable archive filename")
            require(bool(SHA256.fullmatch(str(digest))),
                    f"{name}: missing or malformed SHA256")

    ids = set()
    selectors = set()
    forbidden = {
        (item["compiler"], item["target"])
        for item in data.get("forbidden", [])
    }
    for profile in data.get("profiles", []):
        ident = profile.get("id")
        compiler = profile.get("compiler")
        obfuscator = profile.get("obfuscator")
        host = profile.get("host")
        target = profile.get("target")
        qualification = profile.get("qualification")
        evidence = profile.get("evidence")
        require(isinstance(ident, str) and ident and ident not in ids,
                f"duplicate/missing profile id: {ident}")
        ids.add(ident)
        require(compiler in BACKENDS and obfuscator == BACKENDS[compiler],
                f"{ident}: unsupported compiler-obfuscator pairing")
        require(host in HOSTS and target in TARGETS,
                f"{ident}: invalid host/target selector")
        selector = (compiler, host, target)
        require(selector not in selectors, f"{ident}: duplicate selector")
        selectors.add(selector)
        require((compiler, target) not in forbidden,
                f"{ident}: explicitly forbidden release target")
        if compiler == "tinycc-builder":
            require(target in ("windows-x86", "windows-x64"),
                    f"{ident}: obfus.h supports only Windows x86/x64")
        if compiler == "llvm-mingw":
            require(target.startswith("windows-"),
                    f"{ident}: llvm-mingw must target Windows")
        if compiler == "llvm-native":
            require(host == target, f"{ident}: native LLVM must match its host")
        if compiler != "llvm-native":
            require(asset_for_host(sources[compiler], host) is not None,
                    f"{ident}: compiler archive not pinned for host {host}")
        require(qualification in ("pending", "qualified"),
                f"{ident}: qualification must be explicit")
        require(isinstance(evidence, list), f"{ident}: evidence must be an array")
        if qualification == "qualified":
            require(compiler != "llvm-native" or
                    sources["llvm-native"].get("distribution") == "pinned",
                    f"{ident}: native LLVM distribution not immutable")
            required = set(data.get("required_evidence", {}).get(obfuscator, []))
            actual = set()
            for record in evidence:
                require(isinstance(record, dict), f"{ident}: invalid evidence record")
                kind = record.get("kind")
                url = record.get("url")
                revision = record.get("commit")
                require(kind in required and kind not in actual,
                        f"{ident}: unknown/duplicate evidence kind")
                require(isinstance(url, str) and
                        url.startswith("https://github.com/") and "/actions/runs/" in url,
                        f"{ident}: evidence must link to concrete GitHub Actions run")
                require(bool(COMMIT.fullmatch(str(revision))),
                        f"{ident}: evidence must identify an exact CI source commit")
                actual.add(kind)
            require(required and required == actual,
                    f"{ident}: missing release evidence {sorted(required - actual)}")
    require(ids, "at least one release profile is required")
    require(("tinycc-builder", "windows-arm64") in forbidden,
            "TinyCC/obfus.h ARM64 denial must be explicit")

    requirements = data.get("required_evidence", {})
    for obfuscator in BACKENDS.values():
        require(isinstance(requirements.get(obfuscator), list) and
                len(requirements[obfuscator]) >= 5,
                f"missing nontrivial proof requirements for {obfuscator}")


def select_profile(data: dict[str, Any], build_type: str, compiler: str,
                   host: str, target: str) -> dict[str, Any] | None:
    """Select a qualified profile; never fall back from Release to baseline."""
    validate_contract(data)
    allowed = data["release_configs"] + data["baseline_configs"]
    require(build_type in allowed, f"unknown build configuration {build_type}")
    if build_type in data["baseline_configs"]:
        return None
    require(compiler in BACKENDS, f"Release requires an admitted compiler, got {compiler}")
    require(host in HOSTS and target in TARGETS,
            f"unrecognized Release host/target {host} -> {target}")
    forbidden = {
        (item["compiler"], item["target"]): item["reason"]
        for item in data["forbidden"]
    }
    reason = forbidden.get((compiler, target))
    require(reason is None, f"Release denied: {reason}")
    matches = [
        p for p in data["profiles"]
        if (p["compiler"], p["host"], p["target"]) == (compiler, host, target)
    ]
    require(len(matches) == 1,
            f"no unique Release profile for {compiler} {host} -> {target}")
    profile = matches[0]
    require(profile["qualification"] == "qualified",
            f"Release profile {profile['id']} is not qualified; unprotected fallback prohibited")
    return profile


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--build-type")
    parser.add_argument("--compiler")
    parser.add_argument("--host")
    parser.add_argument("--target")
    args = parser.parse_args(argv)
    try:
        data = load_contract(args.contract)
        if args.validate_only:
            print(f"Release contract OK: {len(data['profiles'])} explicit candidate lanes")
            return 0
        if not args.build_type:
            raise PolicyError("--build-type is required unless --validate-only")
        if args.build_type in data["release_configs"]:
            if not all((args.compiler, args.host, args.target)):
                raise PolicyError("Release requires --compiler, --host and --target")
        profile = select_profile(
            data, args.build_type, args.compiler or "",
            args.host or "", args.target or "")
        if profile is None:
            print(f"{args.build_type}: baseline build (no obfuscation contract)")
        else:
            print(f"{args.build_type}: qualified {profile['id']} "
                  "(a real Release still requires emitted-code/CI receipt verification)")
        return 0
    except (PolicyError, OSError, ValueError, KeyError, TypeError) as exc:
        print(f"release compiler contract denied: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
