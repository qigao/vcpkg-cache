# Canonical vcpkg Apple Silicon simulator triplet plus explicit Autoconf
# host identity. Keep --host distinct from the arm64 macOS build machine.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphonesimulator)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=arm64-apple-ios")
