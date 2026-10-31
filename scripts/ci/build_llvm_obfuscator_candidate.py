#!/usr/bin/env python3
"""Build real eshard/obfuscator-llvm against SHA-pinned official LLVM/Clang.

Compiler and plugin are both HOST binaries. This intentionally never marks
a product Release qualified and never installs a fallback obfuscator.
Use the existing native LLVM action first to obtain the immutable compiler.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "compiler-contracts" / "release-obfuscation.json"
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
HOST_EXTENSION = {"linux": ".so", "macos": ".dylib", "windows": ".dll"}


class CandidateError(RuntimeError):
    """Fail closed before publishing an unqualified plugin."""


def require(ok: bool, msg: str) -> None:
    if not ok:
        raise CandidateError(msg)


def checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as inp:
        for part in iter(lambda: inp.read(1024 * 1024), b""):
            digest.update(part)
    return digest.hexdigest()


def command(argv: list[str], cwd: Path, env: dict[str, str],
            timeout: int = 900) -> str:
    result = subprocess.run(argv, cwd=cwd, env=env, text=True,
                            errors="replace", capture_output=True,
                            timeout=timeout)
    # CMake emits many actual configure errors on STDOUT (even with
    # stderr empty); preserve both streams so CI reveals the first real RED.
    require(result.returncode == 0,
            "source-build action failed: " + Path(argv[0]).name +
            " (" + str(result.returncode) + ")\n"
            + "STDOUT:\n" + result.stdout[-8000:]
            + "\nSTDERR:\n" + result.stderr[-8000:])
    return result.stdout.strip()


def clean_within(child: Path, parent: Path) -> bool:
    try:
        child.resolve(strict=False).relative_to(parent.resolve(strict=True))
    except (ValueError, OSError):
        return False
    return True


def validate_inputs(args: argparse.Namespace) -> tuple[dict, dict, Path, dict]:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    source = lock["sources"]["obfuscator-llvm"]
    llvm = lock["sources"]["llvm-native"]
    require(bool(HEX40.fullmatch(source["source_commit"])),
            "obfuscator-llvm source must be immutable Git commit")
    require(args.host in {"linux-x64", "linux-arm64", "macos-arm64"},
            "no approved native host/plugin build profile for this CPU")
    runner18 = getattr(args, "runner_llvm18_candidate", False)
    if runner18:
        entry = llvm.get("runner_candidates", {}).get("macos-arm64", {})
        require(args.host == args.target == "macos-arm64" and
                entry.get("distribution") == "homebrew-preinstalled-candidate-only" and
                entry.get("formula") == "llvm@18" and
                entry.get("llvm_version") == "18.1.8" and
                entry.get("release_qualified") is False,
                "runner LLVM 18 is only a macOS ARM64 non-Release candidate")
        require(args.llvm_root.is_absolute() and args.llvm_root.is_dir(),
                "runner LLVM 18 candidate requires existing absolute Homebrew root")
        root = args.llvm_root.resolve()
        installed_prefix = Path(command(["brew", "--prefix", "llvm@18"],
                                        ROOT, os.environ.copy())).resolve()
        require(installed_prefix == root,
                "runner LLVM root is not the installed llvm@18 Homebrew prefix")
        for name in ("clang", "clang++", "llvm-config", "llvm-ar"):
            require((root / "bin" / name).is_file(),
                    "runner llvm@18 is missing required upstream LLVM tool " + name)
        require(args.output.is_absolute() and not args.output.exists(),
                "candidate build output must be a fresh absolute path")
        return source, {"llvm_version": "18.1.8",
                        "source_commit": None,
                        "runner_candidate_only": True}, root, {"sha256": None}
    assets = [a for a in llvm["assets"] if a["host"] == args.host]
    require(llvm["distribution"] == "pinned" and len(assets) == 1 and
            llvm["llvm_version"] == "23.1.4" and
            source["llvm_candidate_major"] == 23,
            "native LLVM archive/LLVM plugin version is not locked")
    require(args.llvm_root.is_absolute() and args.llvm_root.is_dir(),
            "LLVM root must be existing absolute pinned installation")
    root = args.llvm_root.resolve()
    receipt = root / "qigao-compiler-install.json"
    require(receipt.is_file(), "native LLVM setup provenance is missing")
    origin = json.loads(receipt.read_text(encoding="utf-8"))
    require(origin.get("compiler") == "llvm-native" and
            origin.get("host") == args.host and
            origin.get("archive_sha256") == assets[0]["sha256"] and
            origin.get("source_commit") == llvm["source_commit"] and
            origin.get("version") == llvm["source_tag"] and
            origin.get("release_qualified") is False and
            origin.get("smoke") == "native-execution",
            "not the exact verified host LLVM installer output")
    for name in ("clang", "clang++", "llvm-config"):
        require((root / "bin" / name).is_file(),
                "selected LLVM distribution has no " + name)
    require(args.output.is_absolute() and not args.output.exists(),
            "candidate build output must be a fresh absolute path")
    require(args.host == args.target,
            "candidate compiler/plugin must be proven on the actual host")
    return source, llvm, root, assets[0]


def pinned_host_build_environment(host: str, root: Path) -> dict[str, str]:
    build_env = os.environ.copy()
    if host.startswith("linux-"):
        lib = str(root / "lib")
        build_env["LD_LIBRARY_PATH"] = lib + (
            ":" + build_env["LD_LIBRARY_PATH"]
            if build_env.get("LD_LIBRARY_PATH") else "")
    elif host.startswith("macos-"):
        # Do not globally prepend the official LLVM /lib directory to dyld's
        # library search. Its bundled libc++.1.0.dylib shadows the macOS
        # runtime and breaks llvm-config (___cxa_guard_release missing).
        # The actual installed tool's @rpath and the pinned Xcode SDK resolve
        # dependencies; never silently substitute the system compiler.
        build_env.pop("DYLD_LIBRARY_PATH", None)
    else:
        raise CandidateError("no supported native LLVM plugin host")
    return build_env


def build(args: argparse.Namespace) -> dict:
    source, llvm, root, asset = validate_inputs(args)
    build_env = pinned_host_build_environment(args.host, root)
    clang = root / "bin" / "clang"
    clangxx = root / "bin" / "clang++"
    config = root / "bin" / "llvm-config"
    llvm_version = command([str(config), "--version"], root, build_env)
    require(llvm_version == llvm["llvm_version"],
            "llvm-config does not match the explicitly selected LLVM host version")
    clang_version = command([str(clang), "--version"], root, build_env)
    require(re.search(r"\bclang version " + re.escape(llvm["llvm_version"]) + r"\b",
                      clang_version) is not None and
            "Apple clang" not in clang_version,
            "actual upstream Clang does not match the selected LLVM plugin ABI")
    cmake_dir = Path(command([str(config), "--cmakedir"], root, build_env))
    require(cmake_dir.is_absolute() and clean_within(cmake_dir, root) and
            (cmake_dir / "LLVMConfig.cmake").is_file(),
            "LLVM CMake development config is not part of pinned LLVM root")
    require(shutil.which("cmake") and shutil.which("ninja") and
            shutil.which("git") and shutil.which("ccache"),
            "real source build requires CMake, Ninja, Git and ccache")
    args.output.mkdir(parents=True)
    tree = args.output / "obfuscator-llvm-src"
    builddir = args.output / "build"
    artifactdir = args.output / "artifact"
    artifactdir.mkdir()
    command(["git", "init", "-q", str(tree)], args.output, build_env)
    command(["git", "-C", str(tree), "fetch", "-q", "--depth=1",
             "https://github.com/eshard/obfuscator-llvm.git",
             source["source_commit"]], args.output, build_env)
    command(["git", "-C", str(tree), "checkout", "-q", "--detach",
             "FETCH_HEAD"], args.output, build_env)
    actual_commit = command(["git", "-C", str(tree), "rev-parse", "HEAD"],
                            args.output, build_env)
    require(actual_commit == source["source_commit"],
            "upstream obfuscator source checkout SHA drifted")
    cmake_args = ["cmake", "-S", str(tree), "-B", str(builddir), "-G", "Ninja",
                  "-DLLVM_DIR=" + str(cmake_dir),
                  "-DCMAKE_C_COMPILER=" + str(clang),
                  "-DCMAKE_CXX_COMPILER=" + str(clangxx),
                  "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_DUMMY=OFF",
                  "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"]
    if args.host.startswith("macos-"):
        sdk = build_env.get("SDKROOT", "")
        require(bool(sdk) and Path(sdk).is_absolute() and Path(sdk).is_dir(),
                "real macOS LLVM plugin requires SDKROOT from xcrun")
        cmake_args.append("-DCMAKE_OSX_SYSROOT=" + str(Path(sdk).resolve()))
        if getattr(args, "runner_llvm18_candidate", False):
            # A Clang-loaded pass plugin on Mach-O resolves LLVM symbols
            # from its host. The real -fpass-plugin execution is mandatory:
            # linker permissiveness alone cannot qualify this candidate.
            cmake_args.append(
                "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-undefined,dynamic_lookup")
    command(cmake_args, args.output, build_env)
    command(["cmake", "--build", str(builddir), "--target", "LLVMObfuscator",
             "--parallel", "2"], args.output, build_env, timeout=2400)
    ext = HOST_EXTENSION[args.host.split("-")[0]]
    options = list(builddir.rglob("*LLVMObfuscator*" + ext))
    plugins = [p for p in options if p.is_file() and
               p.name.endswith(ext) and ".pdb" not in p.name]
    require(len(plugins) == 1,
            "real LLVMObfuscator shared plugin must be produced exactly once")
    raw_plugin = plugins[0]
    dest = artifactdir / raw_plugin.name
    shutil.copy2(raw_plugin, dest)
    require(dest.stat().st_size > 8192,
            "compiled host plugin unexpectedly small")
    manifest = {
        "status": "new-source-built-candidate-not-qualified",
        "release_qualified": False,
        "host": args.host, "target": args.target,
        "plugin_name": dest.name,
        "plugin_sha256": checksum(dest),
        "plugin_bytes": dest.stat().st_size,
        "source_repository": source["repository"],
        "source_commit": actual_commit,
        "llvm_version": llvm["llvm_version"],
        "llvm_source_commit": llvm["source_commit"],
        "compiler_archive_sha256": asset["sha256"],
        "compiler_source": ("runner-homebrew-llvm18-candidate-only"
                            if getattr(args, "runner_llvm18_candidate", False)
                            else "pinned-official-LLVM23-archive"),
        "runner_candidate_only": bool(getattr(args, "runner_llvm18_candidate", False)),
        "llvm_root": str(root),
        "compiler_sha256": checksum(clang),
        "clangxx_sha256": checksum(clangxx),
        "llvm_config_sha256": checksum(config),
        "cmake_version": command(["cmake", "--version"], root, build_env).splitlines()[0],
        "ninja_version": command(["ninja", "--version"], root, build_env),
        "ccache_version": command(["ccache", "--version"], root, build_env).splitlines()[0],
    }
    receipt = artifactdir / "candidate.json"
    receipt.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n",
                       encoding="utf-8")
    gate = ROOT / "scripts" / "ci" / "verify_llvm_mingw_obfuscation.py"
    require(gate.is_file(), "single LLVM IR proof owner was not found")
    proofdir = artifactdir / "preflight"
    gate_argv = [sys.executable, str(gate),
                 "--compiler-family", "llvm-native",
                 "--compiler", str(clang), "--plugin", str(dest),
                 "--candidate-plugin-manifest", str(receipt),
                 "--host", args.host, "--target", args.target,
                 "--build-type", "Release", "--require-native",
                 "--output", str(proofdir)]
    if getattr(args, "runner_llvm18_candidate", False):
        gate_argv.append("--runner-llvm18-candidate")
    command(gate_argv, args.output, build_env, timeout=900)
    proof = json.loads((proofdir / "obfuscation-preflight.json").read_text())
    require(proof["status"] == "source-built-candidate-preflight-only"
            and proof["candidate_only"] is True
            and proof["release_qualified"] is False
            and proof["target_native_execution"] is True
            and proof["host_plugin_sha256"] == manifest["plugin_sha256"]
            and proof["protected_ir_verified"] is True
            and set(proof["verified_named_passes"]) ==
                {"flattening", "substitution"}
            and proof["native_parity_result"],
            "required native LLVM plugin source-built candidate proof was not accepted")
    print("LLVM_NATIVE_PLUGIN_SOURCE_BUILD_CANDIDATE_PASS: " +
          json.dumps({"host": args.host,
                      "llvm": manifest["llvm_version"],
                      "source_commit": actual_commit,
                      "plugin_sha256": manifest["plugin_sha256"],
                      "preflight": proof["status"],
                      "release_qualified": False}, sort_keys=True))
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--llvm-root", required=True, type=Path)
    parser.add_argument("--runner-llvm18-candidate", action="store_true",
                        help="Homebrew runner LLVM 18, native diagnostic only; no Release")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        build(args)
    except (CandidateError, OSError, KeyError, ValueError,
            subprocess.TimeoutExpired) as exc:
        print("LLVM_NATIVE_PLUGIN_SOURCE_BUILD_CANDIDATE_RED: " + str(exc),
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
