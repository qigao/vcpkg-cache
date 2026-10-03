# Canonical vcpkg iOS device triplet plus explicit Autoconf host identity.
# Older vcpkg-make releases collapsed iOS and macOS to arm64-apple-darwin;
# on Apple Silicon that makes configure think target binaries are host-runnable.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=arm64-apple-ios")
