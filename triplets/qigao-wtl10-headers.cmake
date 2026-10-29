# WTL 10 is pure C++ headers and unmodified upstream samples.
# Stable source staging for OpenATL's MSVC and llvm-mingw Windows targets.
# No binary objects are built or exported from this specialized triplet.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME MinGW)
set(VCPKG_DISABLE_COMPILER_TRACKING ON)
