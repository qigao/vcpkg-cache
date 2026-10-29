# WTL 10.0.10320 source and MS-PL are immutable; package manager is the
# sole WTL provider. This overlay deliberately does not depend on the
# Visual Studio/Microsoft ATL package. Consumers supply OpenATL::ATL.
vcpkg_download_distfile(WTL_ARCHIVE
    URLS "https://raw.githubusercontent.com/Win32-WTL/WTL/065ef5597383c1231bd4892cf8e94331b29bdb97/Releases/WTL10_10320_Final.zip"
    FILENAME "wtl-10.0.10320-065ef559.zip"
    SHA512 086a6cf6a49a4318a8c519136ba6019ded7aa7f2c1d85f78c30b21183654537b3428a400a64fcdacba3a7a10a9ef05137b6f2119f59594da300d55f9ebfb1309
)
vcpkg_extract_source_archive(
    SOURCE_PATH
    ARCHIVE "${WTL_ARCHIVE}"
    NO_REMOVE_ONE_LEVEL
    PATCHES
        appwizard_setup.js-vs2022.patch
        atlmisc.h-bug329.patch
        atlribbon.h-wtl66.patch
        atlribbon.h-clang-std.patch
)
if(NOT EXISTS "${SOURCE_PATH}/Include/atlapp.h" OR
   NOT EXISTS "${SOURCE_PATH}/Samples/GuidGen/GuidGen.cpp" OR
   NOT EXISTS "${SOURCE_PATH}/Samples/WTLExplorer/WTLExplorer.cpp" OR
   NOT EXISTS "${SOURCE_PATH}/MS-PL.txt")
    message(FATAL_ERROR "Pinned WTL 10.0.10320 release is missing full source or MS-PL")
endif()
file(INSTALL "${SOURCE_PATH}/Include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include"
     FILES_MATCHING PATTERN "*.h")
file(COPY "${SOURCE_PATH}/Samples" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file(COPY "${SOURCE_PATH}/AppWizard" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file(INSTALL "${SOURCE_PATH}/MS-PL.txt"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
# Source provenance is independently enforced by OpenATL's configure gate.
# The consumer is never allowed to substitute a second WTL tree.
file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/openatl-wtl-source.txt"
     "wtl=10.0.10320#7\nsha512=086a6cf6a49a4318a8c519136ba6019ded7aa7f2c1d85f78c30b21183654537b3428a400a64fcdacba3a7a10a9ef05137b6f2119f59594da300d55f9ebfb1309\nprovider=vcpkg-cache/ports/wtl\n"
)
