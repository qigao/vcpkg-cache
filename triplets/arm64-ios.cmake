# Canonical vcpkg iOS device triplet plus explicit Autoconf host identity.
# The Autotools --host must differ from the macOS build host, while its OS
# prefix must remain Darwin for ICU's mh-darwin platform fragment. The literal
# apple-ios host falls through ICU 74's platform detector to mh-unknown.
# CMake/iOS sysroot stays authoritative for actual device compilation.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-apple-darwin-ios")
set(VCPKG_OSX_DEPLOYMENT_TARGET "14.0")
