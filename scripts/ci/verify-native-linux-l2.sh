#!/usr/bin/env bash
# Verify the exact official L2 ABI in a fresh local files cache.
# This helper is shared by the master warm-cache read job and PR acceptance.
set -euo pipefail

# Deliberately no implicit fallback. The caller owns the package profile and
# must name the same manifest used when vcpkg calculated/published that ABI.
if [[ "$#" -ne 1 ]]; then
  echo 'usage: verify-native-linux-l2.sh generic|wabt' >&2
  exit 2
fi
profile="$1"

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${VCPKG_ROOT:?VCPKG_ROOT is required}"
: "${VCPKG_BINARY_CACHE:?VCPKG_BINARY_CACHE is required}"
: "${VCPKG_BINARY_SOURCES:?VCPKG_BINARY_SOURCES is required}"

# An authenticated curl NuGet V3 GET has already populated the local L1.
# Never clear that exact downloaded cache after restore. The vcpkg install
# below is forced to use only those verified bytes; no network provider,
# Mono, NuGet executable, or fallback source compilation is permitted.
test "$VCPKG_BINARY_SOURCES" = "clear;files,$VCPKG_BINARY_CACHE,readwrite"
test -d "$VCPKG_BINARY_CACHE"
test -n "$(find "$VCPKG_BINARY_CACHE" -type f -name '*.zip' -print -quit)"
test -x "$VCPKG_ROOT/vcpkg"

case "$profile" in
  generic)
    manifest="$GITHUB_WORKSPACE"
    ;;
  wabt)
    manifest="$GITHUB_WORKSPACE/cache-contracts/wabt-producer"
    ;;
  *)
    echo "Unsupported exact native cache profile: $profile" >&2
    exit 2
    ;;
esac
test -f "$manifest/vcpkg.json"
install_root="$RUNNER_TEMP/curl-native-${profile}-linux-l2-installed"
log="$RUNNER_TEMP/curl-native-${profile}-linux-l2.log"
rm -rf "$install_root"
"$VCPKG_ROOT/vcpkg" install \
  "--x-manifest-root=$manifest" \
  "--x-install-root=$install_root" \
  --triplet=x64-linux --host-triplet=x64-linux \
  --only-binarycaching 2>&1 | tee "$log"

if grep -Eq '^Building [^:]+:' "$log"; then
  echo 'Unexpected source build in exact native Linux L2 qualification' >&2
  exit 1
fi
if ! grep -Eq 'Restored [1-9][0-9]* package\(s\)' "$log"; then
  echo 'No native ABI package restored from the downloaded files cache' >&2
  exit 1
fi
case "$profile" in
  generic)
    test -f "$install_root/x64-linux/include/simde/x86/sse2.h"
    test -f "$install_root/x64-linux/include/gmssl/tls.h"
    ;;
  wabt)
    test -x "$install_root/x64-linux/tools/wabt/wast2json"
    ;;
esac
printf 'Native Linux %s exact-L2 binaries installed without fallback; \
curl V3 -> local files L1 -> installed ABI.\n' "$profile" >> "$GITHUB_STEP_SUMMARY"
