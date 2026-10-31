#!/usr/bin/env python3
"""Prepare pinned obfuscator-llvm at compiler setup, with unrestricted LLVM.

Use a supplied native host plugin, or source-build pinned eshard source
against the selected host LLVMConfig.cmake. No compiler/IR/ABI probe or
second engine. A missing dev package or failed source build is fatal.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


class SetupError(ValueError):
    pass


def run(args: list[str], cwd: Path | None = None) -> str:
    proc = subprocess.run(args, cwd=cwd, capture_output=True,
                          text=True, check=False)
    if proc.returncode:
        raise SetupError(
            "required source-build command failed: " + Path(args[0]).name
            + "\nSTDOUT:\n" + proc.stdout[-6000:]
            + "\nSTDERR:\n" + proc.stderr[-6000:])
    return proc.stdout.strip()


def host_llvm_config(cxx: Path) -> Path:
    suffix = ".exe" if os.name == "nt" else ""
    candidates = [cxx.parent / ("llvm-config" + suffix)]
    candidates.extend(sorted(cxx.parent.glob("llvm-config-*")))
    available = shutil.which("llvm-config")
    if available:
        candidates.append(Path(available))
    if os.name != "nt":
        candidates.extend(sorted(Path("/usr/bin").glob("llvm-config-[0-9]*")))
        candidates.extend(sorted(Path("/usr/lib").glob("llvm-*/bin/llvm-config")))
    for path in candidates:
        if path.is_file():
            return path.resolve()
    raise SetupError(
        "Installed compiler has no host LLVM development config; install "
        "llvm-config/LLVMConfig.cmake or provide a matching plugin-path. "
        "Never fall back to an unprotected Release.")


def build_plugin(repo: Path, cxx: Path, root: Path) -> Path:
    lock = json.loads((repo / "compiler-contracts/release-obfuscation.json")
                      .read_text(encoding="utf-8"))
    source = lock["sources"]["obfuscator-llvm"]
    sha = source["source_commit"]
    if len(sha) != 40 or any(x not in "0123456789abcdef" for x in sha):
        raise SetupError("obfuscator source pin must be immutable Git SHA")
    llvm_dir = Path(run([str(host_llvm_config(cxx)), "--cmakedir"])).resolve()
    if not (llvm_dir / "LLVMConfig.cmake").is_file():
        raise SetupError("Selected host LLVM lacks LLVMConfig.cmake")
    for required in ("git", "cmake", "ninja"):
        if not shutil.which(required):
            raise SetupError("Required host plugin build tool missing: " + required)
    source_dir, build_dir = root / "source", root / "build"
    source_dir.mkdir(parents=True)
    run(["git", "init", str(source_dir)])
    run(["git", "-C", str(source_dir), "remote", "add", "origin",
         "https://github.com/" + source["repository"] + ".git"])
    run(["git", "-C", str(source_dir), "fetch", "--depth=1", "origin", sha])
    run(["git", "-C", str(source_dir), "checkout", "--detach", "FETCH_HEAD"])
    if run(["git", "-C", str(source_dir), "rev-parse", "HEAD"]) != sha:
        raise SetupError("Obfuscator source checkout differs from pinned SHA")
    # One exact source-compatibility fix: both LLVM 18 and LLVM 23 provide
    # a default alloca insertion point, but LLVM 18 does not accept the
    # LLVM 23 BasicBlock iterator overload here. No version detection.
    patch = repo / "patches/obfuscator-llvm/default-phi-alloca-insertion.patch"
    if not patch.is_file():
        raise SetupError("Pinned obfuscator source compatibility patch is missing")
    run(["git", "-C", str(source_dir), "apply", "--whitespace=error", str(patch)])
    command = [
        "cmake", "-S", str(source_dir), "-B", str(build_dir), "-G", "Ninja",
        "-DLLVM_DIR=" + str(llvm_dir), "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_DUMMY=OFF", "-DCMAKE_CXX_COMPILER=" + str(cxx)]
    if sys.platform == "darwin":
        sdk = os.environ.get("SDKROOT", "")
        if not sdk:
            raise SetupError("macOS source build requires SDKROOT")
        command += [
            "-DCMAKE_OSX_SYSROOT=" + sdk,
            "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-undefined,dynamic_lookup"]
    run(command, cwd=root)
    run(["cmake", "--build", str(build_dir), "--target", "LLVMObfuscator",
         "--parallel", "2"], cwd=root)
    extension = ".dll" if os.name == "nt" else (
        ".dylib" if sys.platform == "darwin" else ".so")
    plugins = sorted(p for p in build_dir.rglob("*") if p.is_file()
                     and p.name.endswith(extension)
                     and "LLVMObfuscator" in p.name)
    if len(plugins) != 1:
        raise SetupError("Expected exactly one native LLVMObfuscator plugin")
    final = root / "plugin" / plugins[0].name
    final.parent.mkdir(parents=True)
    shutil.copy2(plugins[0], final)
    return final


def emit(path: Path, entries: dict[str, str]) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as stream:
        for key, value in entries.items():
            if not value or any(ch in value for ch in ("\n", "\r")):
                raise SetupError("Unsafe GitHub action output: " + key)
            stream.write(key + "=" + value + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--compiler-cxx", type=Path, required=True)
    parser.add_argument("--plugin-path", default="")
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--seed", required=True)
    parser.add_argument("--github-env", type=Path, required=True)
    parser.add_argument("--github-output", type=Path, required=True)
    args = parser.parse_args()
    try:
        repo = args.repo_root.resolve()
        root = args.output_root.resolve()
        if args.plugin_path:
            plugin = Path(args.plugin_path).resolve()
            if not plugin.is_file():
                raise SetupError("Explicit host plugin-path does not exist")
        else:
            if root.exists():
                raise SetupError("Source build root must be fresh")
            root.mkdir(parents=True)
            plugin = build_plugin(repo, args.compiler_cxx.resolve(), root)
        cmake = repo / "cmake/QigaoCompilerObfuscation.cmake"
        launcher = repo / "scripts/obfuscator-clang-launcher.py"
        if not cmake.is_file() or not launcher.is_file():
            raise SetupError("Shared compiler obfuscator integration is missing")
        def posix(p: Path) -> str:
            return str(p).replace("\\", "/")
        output_plugin = posix(plugin)
        emit(args.github_output, {
            "enabled": "true",
            "plugin-path": output_plugin,
            "compile-flag": "-fpass-plugin=" + output_plugin,
            "cmake-file": posix(cmake),
        })
        emit(args.github_env, {
            "QIGAO_OBFUSCATOR_ENABLED": "true",
            "QIGAO_OBFUSCATOR_PLUGIN_PATH": output_plugin,
            "QIGAO_OBFUSCATOR_PYTHON": posix(Path(sys.executable).resolve()),
            "QIGAO_OBFUSCATOR_LAUNCHER": posix(launcher),
            "QIGAO_COMPILER_OBFUSCATION_CMAKE": posix(cmake),
            "LLVM_OBF_SCALAROPTIMIZERLATE_PASSES": "flattening,substitution",
            "LLVM_OBF_SEED": args.seed,
        })
        print("OBFUSCATOR_SETUP_ENABLED: " + output_plugin)
        return 0
    except (SetupError, OSError, KeyError, ValueError) as exc:
        print("OBFUSCATOR_SETUP_FAILED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
