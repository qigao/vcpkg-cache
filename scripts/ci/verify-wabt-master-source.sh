#!/usr/bin/env bash
# CI WABT admission from the repository's current source manifest.
# This is an explicitly SOURCE-ONLY build, not an unavailable-package fallback.
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  echo 'usage: verify-wabt-master-source.sh (no arguments)' >&2
  exit 2
fi

: "${GITHUB_WORKSPACE:?Missing GitHub source checkout}"
: "${RUNNER_TEMP:?Missing runner-owned temporary root}"
: "${VCPKG_ROOT:?Missing canonical pinned vcpkg toolchain}"
: "${VCPKG_BINARY_CACHE:?Missing isolated vcpkg files-cache root}"

manifest="$GITHUB_WORKSPACE/cache-contracts/wabt-producer"
installed="$RUNNER_TEMP/wabt-master-source-installed"
log="$RUNNER_TEMP/wabt-master-source-build.log"
test -s "$manifest/vcpkg.json"
test -x "$VCPKG_ROOT/vcpkg"
test -d "$VCPKG_BINARY_CACHE"

python3 - "$manifest/vcpkg.json" <<'PY'
import json
import re
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data.get("name") == "qigao-wabt-producer"
assert data.get("dependencies") == [{"name": "wabt", "features": ["tools"]}]
assert re.fullmatch(r"[0-9a-f]{40}", data.get("builtin-baseline", ""))
PY

# Do not restore an old native L2 package, and do not write a new L2 package.
# This explicit mode is NOT a fallback: sourcing from master is the contract.
# Keep the binary cache empty, even if the base toolchain sets files/readwrite.
test -z "$(find "$VCPKG_BINARY_CACHE" -type f -name '*.zip' -print -quit)"
rm -rf "$installed"
export VCPKG_BINARY_SOURCES=clear
"$VCPKG_ROOT/vcpkg" install \
  "--x-manifest-root=$manifest" "--x-install-root=$installed" \
  --triplet=x64-linux --host-triplet=x64-linux --binarysource=clear \
  2>&1 | tee "$log"
if ! grep -Eq '^Building wabt(:|\[)' "$log"; then
  echo 'WABT did not compile from the selected master source graph' >&2
  exit 1
fi
if find "$VCPKG_BINARY_CACHE" -type f -name '*.zip' -print -quit | grep -q .; then
  echo 'A native binary-cache ZIP was produced in source-only CI' >&2
  exit 1
fi

tool="$installed/x64-linux/tools/wabt/wast2json"
test -x "$tool"
"$tool" --version

fixture="$RUNNER_TEMP/wabt-master-source-smoke.wast"
json_output="$RUNNER_TEMP/wabt-master-source-smoke.json"
cat > "$fixture" <<'WAST'
(module
  (func (export "answer") (result i32)
    i32.const 42))
(assert_return (invoke "answer") (i32.const 42))
WAST
"$tool" "$fixture" --output="$json_output"
python3 - "$json_output" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
commands = data.get("commands", [])
if len(commands) < 2:
    raise SystemExit("wast2json failed to emit both module and assertion")
if commands[0].get("type") != "module":
    raise SystemExit("wast2json failed the module conversion smoke")
if not any(command.get("type") == "assert_return" for command in commands):
    raise SystemExit("wast2json failed the semantic assertion smoke")
PY

source_sha="$(git -C "$GITHUB_WORKSPACE" rev-parse HEAD)"
manifest_sha="$(sha256sum "$manifest/vcpkg.json" | cut -d' ' -f1)"
tool_sha="$(sha256sum "$tool" | cut -d' ' -f1)"
printf 'WABT source-only source checkout: %s\n' "$source_sha" >> "$GITHUB_STEP_SUMMARY"
printf 'WABT master-owned manifest SHA256: %s\n' "$manifest_sha" >> "$GITHUB_STEP_SUMMARY"
printf 'WABT installed wast2json SHA256: %s\n' "$tool_sha" >> "$GITHUB_STEP_SUMMARY"
printf 'WABT source build and WAST-to-JSON semantics: PASS\n' >> "$GITHUB_STEP_SUMMARY"
printf 'Remote native NuGet publish: DISABLED; L2 restore: NOT REQUIRED\n' >> "$GITHUB_STEP_SUMMARY"
