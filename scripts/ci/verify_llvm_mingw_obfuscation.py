#!/usr/bin/env python3
"""Validate a pinned host LLVM pass against the real llvm-mingw compiler.

This is a compiler/IR/native *preflight*, not product Release qualification.
A product must separately compile every protected target and run target-native
ABI, exception, CFG and end-to-end tests. There is no fallback compiler/pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys

LOCK = Path(__file__).resolve().parents[2] / "compiler-contracts/release-obfuscation.json"
MACHINES = {"windows-x64": 0x8664, "windows-arm64": 0xAA64}
TRIPLES = {"windows-x64": "x86_64-w64-mingw32",
           "windows-arm64": "aarch64-w64-mingw32"}
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
SEED = re.compile(r"(?:0x)?[0-9A-Fa-f]{32}\Z")
PROBE = r"""#include <stdio.h>
#include <stdint.h>
__attribute__((noinline)) static uint32_t obf_probe(uint32_t x) {
    uint32_t a = x ^ UINT32_C(0x9e3779b9);
    for (unsigned i = 0; i != 13; ++i) {
        if (a & 1u)
            a = (a ^ (a << 7)) + UINT32_C(0x45d9f3b);
        else
            a = (a << 5) ^ (a >> 3) ^ UINT32_C(0x7f4a7c15);
        switch ((a >> 4) & 3u) {
        case 0: a ^= i * 97u; break;
        case 1: a += i * 67u; break;
        case 2: a = (a << 9) | (a >> 23); break;
        default: a ^= UINT32_C(0x31415926); break;
        }
    }
    return a;
}
int main(void) {
    uint64_t result = UINT64_C(0xcbf29ce484222325);
    for (uint32_t i = 0; i != 257; ++i) {
        result ^= obf_probe(i * 12347u);
        result *= UINT64_C(0x100000001b3);
    }
    printf("%llu\n", (unsigned long long)result);
    return 0;
}
"""


class GateError(ValueError):
    pass


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise GateError(reason)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for block in iter(lambda: fp.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def run(argv: list[str], *, cwd: Path, env: dict[str, str]) -> str:
    p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True,
                       text=True, errors="replace", timeout=120)
    require(p.returncode == 0,
            f"command failed with {p.returncode} ({Path(argv[0]).name}): "
            f"{p.stderr[-1800:]}")
    return p.stdout


def pe_machine(path: Path) -> int:
    with path.open("rb") as fp:
        header = fp.read(64)
        require(len(header) == 64 and header[:2] == b"MZ",
                "expected real MZ/PE artifact")
        ptr = struct.unpack_from("<I", header, 0x3c)[0]
        require(64 <= ptr < 16 << 20, "invalid PE pointer")
        fp.seek(ptr)
        nt = fp.read(6)
    require(len(nt) == 6 and nt[:4] == b"PE\0\0", "not a PE")
    return struct.unpack_from("<H", nt, 4)[0]


def function_body(ir: str) -> str:
    match = re.search(r"(?ms)^define\b[^\n]*@obf_probe\([^)]*\)[^\n]*\{\n(.*?)^\}", ir)
    require(match is not None, "compiler eliminated or renamed protected function")
    return match.group(1)


def check_pin(contract: dict, host: str, plugin: Path) -> dict:
    source = contract["sources"]["obfuscator-llvm"]
    matches = [p for p in source["host_plugin_assets"] if p["host"] == host]
    require(len(matches) == 1,
            f"Release blocked: no unique pinned obfuscator-llvm binary for {host}")
    pin = matches[0]
    require(pin["source_commit"] == source["source_commit"] and
            pin["llvm_version"] == contract["sources"]["llvm-mingw"]["llvm_version"],
            "host LLVM plugin source/ABI identity does not match locked compiler")
    require(plugin.is_absolute() and plugin.is_file(),
            "plugin must be an existing absolute host binary path")
    require(plugin.name == pin["name"], "host plugin basename differs from locked artifact")
    expected_extension = (".dll" if host.startswith("windows-") else
                          ".dylib" if host.startswith("macos-") else ".so")
    require(plugin.suffix.lower() == expected_extension,
            "plugin binary is not for the host OS")
    require(bool(SHA256.fullmatch(str(pin["sha256"]))) and sha(plugin) == pin["sha256"],
            "host obfuscator plugin SHA256 mismatch (no substitution)")
    return pin


def verify(args: argparse.Namespace) -> dict:
    contract = json.loads(LOCK.read_text(encoding="utf-8"))
    require(contract["state"] == "design-candidate-not-release-qualified",
            "unexpected source lock state")
    release = contract["windows_protected_release"]
    require(args.build_type in contract["release_configs"] and
            args.target in release["targets"] and
            release["compiler"] == "llvm-mingw",
            "Windows Release requires the selected llvm-mingw compiler profile")
    require(args.host in ("windows-x64", "windows-arm64", "linux-x64",
                           "linux-arm64", "macos-x64", "macos-arm64"),
            "unknown plugin host")
    require(args.compiler.is_absolute() and args.compiler.is_file(),
            "compiler must be the installed absolute llvm-mingw clang")
    require(SEED.fullmatch(args.seed) is not None, "LLVM obfuscator seed must be 16 bytes hex")
    require(not args.output.exists(), "proof output directory must be fresh")
    pin = check_pin(contract, args.host, args.plugin)
    clang_version = run([str(args.compiler), "--version"],
                        cwd=LOCK.parent, env=os.environ.copy())
    required_version = contract["sources"]["llvm-mingw"]["llvm_version"]
    require(re.search(r"\bclang version " + re.escape(required_version) + r"\b",
                      clang_version) is not None,
            "actual llvm-mingw clang version differs from pinned plugin ABI")
    source = contract["sources"]["obfuscator-llvm"]
    pipeline = source["required_passes"]
    require(pipeline.get("LLVM_OBF_SCALAROPTIMIZERLATE_PASSES"),
            "LLVM pass pipeline missing from pinned lock")
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("LLVM_OBF_"):
            del env[key]
    env.update({k: v for k, v in pipeline.items()})
    env["LLVM_OBF_SEED"] = args.seed
    args.output.mkdir(parents=True)
    src = args.output / "obfuscation_gate.c"
    src.write_text(PROBE, encoding="utf-8")
    basic = [str(args.compiler), "-std=c11", "-O2", "-fno-lto",
             "-Werror", str(src)]
    load = [f"-fpass-plugin={args.plugin}"]
    baseline_ir = args.output / "baseline.ll"
    protected_ir = args.output / "protected.ll"
    baseline_exe = args.output / "baseline.exe"
    protected_exe = args.output / "protected.exe"
    run(basic + ["-S", "-emit-llvm", "-o", str(baseline_ir)],
        cwd=args.output, env=env)
    run(basic + load + ["-S", "-emit-llvm", "-o", str(protected_ir)],
        cwd=args.output, env=env)
    normal_body = function_body(baseline_ir.read_text(encoding="utf-8"))
    changed_body = function_body(protected_ir.read_text(encoding="utf-8"))
    require(normal_body != changed_body,
            "obfuscator DLL loaded but protected function IR did not change")
    obj = args.output / "protected-ir.obj"
    run([str(args.compiler), "-O2", "-x", "ir", "-c",
         str(protected_ir), "-o", str(obj)], cwd=args.output, env=env)
    require(obj.is_file() and obj.stat().st_size > 0,
            "protected IR compilation/verification produced no COFF")
    run(basic + ["-o", str(baseline_exe)], cwd=args.output, env=env)
    run(basic + load + ["-o", str(protected_exe)],
        cwd=args.output, env=env)
    for exe in (baseline_exe, protected_exe):
        require(pe_machine(exe) == MACHINES[args.target],
                f"wrong target PE machine: {exe.name}")
    require(sha(baseline_exe) != sha(protected_exe),
            "baseline and protected binaries are byte-identical")
    native = (args.host == args.target)
    require(not args.require_native or native,
            "native runtime was requested on a cross-compiler host")
    runtime = None
    if native:
        baseline_output = run([str(baseline_exe)], cwd=args.output, env=env)
        protected_output = run([str(protected_exe)], cwd=args.output, env=env)
        require(baseline_output and baseline_output == protected_output,
                "native baseline/protected semantic parity failed")
        runtime = baseline_output.strip()
    receipt = {
        "status": "compiler-plugin-preflight-only",
        "release_qualified": False,
        "target_native_execution": native,
        "host": args.host, "target": args.target, "target_triple": TRIPLES[args.target],
        "build_type": args.build_type,
        "clang_version": required_version,
        "compiler_sha256": sha(args.compiler),
        "compiler_archive_sha256": next(
            (a["sha256"] for a in contract["sources"]["llvm-mingw"]["assets"]
             if a["host"] == args.host), None),
        "obfuscator_source_commit": source["source_commit"],
        "host_plugin_sha256": pin["sha256"], "host_plugin_name": pin["name"],
        "pass_pipeline": pipeline, "seed": args.seed,
        "source_sha256": sha(src),
        "baseline_ir_function_sha256": hashlib.sha256(normal_body.encode()).hexdigest(),
        "protected_ir_function_sha256": hashlib.sha256(changed_body.encode()).hexdigest(),
        "protected_ir_verified": True,
        "pe_machine": f"{MACHINES[args.target]:04x}",
        "baseline_pe_sha256": sha(baseline_exe),
        "protected_pe_sha256": sha(protected_exe),
        "native_parity_result": runtime,
    }
    (args.output / "obfuscation-preflight.json").write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return receipt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--plugin", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--target", choices=tuple(MACHINES), required=True)
    parser.add_argument("--build-type", choices=("Release", "MinSizeRel",
                                                  "RelWithDebInfo"), required=True)
    parser.add_argument("--seed", default="0xA04252B187478C00A40BC6D81D1A8A52")
    parser.add_argument("--require-native", action="store_true")
    args = parser.parse_args(argv)
    try:
        receipt = verify(args)
        print("LLVM_MINGW_OBFUSCATOR_PREFLIGHT_PASS: " +
              json.dumps(receipt, sort_keys=True))
        return 0
    except (GateError, OSError, ValueError, KeyError,
            subprocess.TimeoutExpired) as exc:
        print(f"LLVM_MINGW_OBFUSCATOR_PREFLIGHT_RED: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
