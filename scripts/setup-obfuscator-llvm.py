#!/usr/bin/env python3
"""Prepare pinned obfuscator-llvm at compiler setup, with unrestricted LLVM.

Use a supplied native host plugin, or source-build pinned eshard source
against the selected host LLVM development files. Windows llvm-mingw
prepares its stripped headers/import library from the matching source and
installed DLL. No compiler/IR/ABI probe or second engine.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


class SetupError(ValueError):
    pass


def run(args: list[str], cwd: Path | None = None, *, stream: bool = False) -> str:
    if stream:
        print("SOURCE_BUILD: " + subprocess.list2cmdline(args), flush=True)
    proc = subprocess.run(args, cwd=cwd, capture_output=not stream,
                          text=True, check=False)
    if proc.returncode:
        raise SetupError(
            "required source-build command failed: " + Path(args[0]).name
            + "\nSTDOUT:\n" + (proc.stdout or "")[-6000:]
            + "\nSTDERR:\n" + (proc.stderr or "")[-6000:])
    return (proc.stdout or "").strip()


def checkout_source(repository: str, sha: str, destination: Path,
                    sparse: tuple[str, ...] = ()) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise SetupError("Source pin must be an immutable Git SHA")
    destination.mkdir(parents=True)
    run(["git", "init", str(destination)])
    run(["git", "-C", str(destination), "config", "core.longpaths", "true"])
    run(["git", "-C", str(destination), "config", "core.autocrlf", "false"])
    run(["git", "-C", str(destination), "remote", "add", "origin",
         "https://github.com/" + repository + ".git"])
    run(["git", "-C", str(destination), "fetch", "--depth=1", "origin", sha],
        stream=True)
    if sparse:
        run(["git", "-C", str(destination), "sparse-checkout", "init", "--cone"])
        run(["git", "-C", str(destination), "sparse-checkout", "set", *sparse])
    run(["git", "-C", str(destination), "checkout", "--detach", "FETCH_HEAD"],
        stream=True)
    if run(["git", "-C", str(destination), "rev-parse", "HEAD"]) != sha:
        raise SetupError("Source checkout differs from pinned SHA")


def windows_llvm_development(lock: dict, kit: Path, cxx: Path,
                             root: Path) -> tuple[Path, Path]:
    """Build missing headers and an import library for the installed host DLL.

    llvm-mingw strips its LLVM includes, CMake config and .dll.a files. Keep
    its compiler/runtime bytes: upstream's intrinsics_gen supplies the dev
    headers; the installed DLL exports supply its import library.
    """
    source = lock["sources"]["llvm-mingw"]
    receipt = json.loads((kit / "qigao-toolchain-source.json").read_text())
    if receipt["compiler"] != "llvm-mingw" or receipt["tag"] != source["release_tag"]:
        raise SetupError("Windows dev source must belong to the installed MinGW kit")
    machine = {"windows-x64": "i386:x86-64", "windows-arm64": "arm64"}[receipt["host"]]
    dlls = sorted(p for p in (kit / "bin").glob("*.dll")
                  if re.fullmatch(r"(?:lib)?LLVM(?:-[0-9.]+)?\.dll", p.name, re.I))
    if len(dlls) != 1:
        raise SetupError("Selected MinGW kit must provide one host LLVM runtime DLL")
    cc = cxx.with_name(cxx.name.replace("clang++", "clang"))
    source_dir, build_dir = root / "llvm-source", root / "llvm-development"
    # LLVM's Support/TableGen headers also consume libc common utilities.
    # Checking out that directory does not build a libc runtime.
    checkout_source(source["llvm_repository"], source["llvm_source_commit"],
                    source_dir, ("llvm", "cmake", "third-party", "libc"))
    run([
        "cmake", "-S", str(source_dir / "llvm"), "-B", str(build_dir), "-G", "Ninja",
        "-DCMAKE_C_COMPILER=" + str(cc), "-DCMAKE_CXX_COMPILER=" + str(cxx),
        "-DCMAKE_BUILD_TYPE=Release",
        "-DLLVM_ENABLE_PROJECTS=", "-DLLVM_TARGETS_TO_BUILD=ARM;AArch64;X86;NVPTX",
        "-DLLVM_ENABLE_ASSERTIONS=OFF", "-DLLVM_ENABLE_ABI_BREAKING_CHECKS=FORCE_OFF",
        "-DLLVM_ENABLE_RTTI=ON", "-DLLVM_ENABLE_EH=OFF",
        "-DLLVM_BUILD_LLVM_DYLIB=ON", "-DLLVM_LINK_LLVM_DYLIB=ON",
        "-DLLVM_INCLUDE_TESTS=OFF", "-DLLVM_INCLUDE_EXAMPLES=OFF",
        "-DLLVM_INCLUDE_BENCHMARKS=OFF", "-DLLVM_ENABLE_ZLIB=OFF",
        "-DLLVM_ENABLE_ZSTD=OFF", "-DLLVM_ENABLE_LIBXML2=OFF",
        "-DLLVM_ENABLE_LIBEDIT=OFF", "-DLLVM_ENABLE_CURL=OFF",
    ], stream=True)
    run(["cmake", "--build", str(build_dir), "--target", "intrinsics_gen",
         "--parallel", "2"], stream=True)
    # This is a linker input built from the selected runtime, not a plugin
    # load test, compiler probe, or another compiled copy of LLVM.
    exports = run([str(kit / "bin/llvm-readobj.exe"), "--coff-exports", str(dlls[0])])
    names = sorted(set(re.findall(r"^\s*Name: (\S+)\s*$", exports, re.MULTILINE)))
    if not names or any('"' in name for name in names):
        raise SetupError("Cannot generate the selected LLVM DLL import definition")
    definition = root / "llvm-host.def"
    definition.write_text("EXPORTS\n" + "".join(f'  "{name}"\n' for name in names),
                          encoding="utf-8")
    import_library = root / "libLLVM-host.dll.a"
    run([str(kit / "bin/llvm-dlltool.exe"), "-m", machine,
         "-D", dlls[0].name, "-d", str(definition), "-l", str(import_library)],
        stream=True)
    return build_dir / "lib/cmake/llvm", import_library


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


def build_plugin(repo: Path, cxx: Path, root: Path,
                 windows_kit: Path | None = None) -> Path:
    lock = json.loads((repo / "compiler-contracts/release-obfuscation.json")
                      .read_text(encoding="utf-8"))
    source = lock["sources"]["obfuscator-llvm"]
    sha = source["source_commit"]
    if len(sha) != 40 or any(x not in "0123456789abcdef" for x in sha):
        raise SetupError("obfuscator source pin must be immutable Git SHA")
    for required in ("git", "cmake", "ninja"):
        if not shutil.which(required):
            raise SetupError("Required host plugin build tool missing: " + required)
    host_import_library = None
    if windows_kit is not None:
        if os.name != "nt":
            raise SetupError("Windows LLVM development needs a Windows host")
        llvm_dir, host_import_library = windows_llvm_development(
            lock, windows_kit, cxx, root)
    else:
        llvm_dir = Path(run([str(host_llvm_config(cxx)), "--cmakedir"])).resolve()
    if not (llvm_dir / "LLVMConfig.cmake").is_file():
        raise SetupError("Selected host LLVM lacks LLVMConfig.cmake")
    source_dir, build_dir = root / "source", root / "build"
    checkout_source(source["repository"], sha, source_dir)
    # One exact source-compatibility fix: both LLVM 18 and LLVM 23 provide
    # a default alloca insertion point, but LLVM 18 does not accept the
    # LLVM 23 BasicBlock iterator overload here. No version detection.
    for filename in (
        "default-phi-alloca-insertion.patch",
        "fcmp-basicblock-reference.patch",
        "windows-host-import-library.patch",
    ):
        patch = repo / "patches/obfuscator-llvm" / filename
        if not patch.is_file():
            raise SetupError("Pinned obfuscator source patch is missing: " + filename)
        run(["git", "-C", str(source_dir), "apply", "--whitespace=error", str(patch)])
    command = [
        "cmake", "-S", str(source_dir), "-B", str(build_dir), "-G", "Ninja",
        "-DLLVM_DIR=" + str(llvm_dir), "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_DUMMY=OFF", "-DCMAKE_CXX_COMPILER=" + str(cxx)]
    if host_import_library is not None:
        command += [
            "-DCMAKE_C_COMPILER=" + str(cxx.with_name(cxx.name.replace("clang++", "clang"))),
            "-DLLVM_OMIT_EXPORTS_FROM_CONFIG=ON",
            "-DQIGAO_LLVM_HOST_IMPORT_LIBRARY=" + str(host_import_library)]
    if sys.platform == "darwin":
        sdk = os.environ.get("SDKROOT", "")
        if not sdk:
            raise SetupError("macOS source build requires SDKROOT")
        command += [
            "-DCMAKE_OSX_SYSROOT=" + sdk,
            "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-undefined,dynamic_lookup"]
    run(command, cwd=root, stream=True)
    run(["cmake", "--build", str(build_dir), "--target", "LLVMObfuscator",
         "--parallel", "2"], cwd=root, stream=True)
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
    parser.add_argument("--windows-toolchain-root", type=Path)
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
            plugin = build_plugin(
                repo, args.compiler_cxx.resolve(), root,
                args.windows_toolchain_root.resolve() if args.windows_toolchain_root else None)
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
