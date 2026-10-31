#!/usr/bin/env python3
"""LLVM obfuscation C/C++ compiler launcher, selected at compiler setup.

Not a compiler test, source allowlist, IR probe, or ABI-version checker.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("required compiler/arguments missing", file=sys.stderr)
        return 2
    if os.environ.get("QIGAO_OBFUSCATOR_ENABLED") != "true":
        print("compiler obfuscation was disabled after configure",
              file=sys.stderr)
        return 2
    plugin = os.environ.get("QIGAO_OBFUSCATOR_PLUGIN_PATH", "")
    if not plugin or not Path(plugin).is_file():
        print("required host obfuscator-llvm plugin is missing",
              file=sys.stderr)
        return 2
    # The CMake module does not enable the launcher for Debug.
    return subprocess.run(
        [sys.argv[1], "-fpass-plugin=" + plugin, *sys.argv[2:]],
        check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
