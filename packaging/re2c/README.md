# Qigao.Re2c.Binary

Prebuilt host binaries and stdlib data for upstream re2c 4.6.

This binary package removes repeated re2c bootstrap work from Salts and other
C/C++ CI pipelines.

## Layout

- `tools/linux-x64/bin/re2c` plus `tools/linux-x64/share/re2c/stdlib/`
- `tools/linux-arm64/bin/re2c` plus `tools/linux-arm64/share/re2c/stdlib/`
- `tools/windows-x64/bin/re2c.exe` plus `tools/windows-x64/share/re2c/stdlib/`
- `tools/macos-arm64/bin/re2c` plus `tools/macos-arm64/share/re2c/stdlib/`

These are the four host RIDs in the published 4.6.4 package. The producer checks
that every RID retains its executable, both Unicode tables and the C syntax
file. macOS x64 is not present; an ARM64 executable is not an x64 substitute.

Use the executable matching the build host. NuGet/Actions ZIP extraction may not preserve
Unix executable bits, so Linux/macOS consumers run `chmod +x` on the restored binary.

Android is intentionally not included: re2c runs on the host and generates source code
before the Android cross-build.

## Linux x64 compatibility and publication

Packaging revision 5 builds Linux x64 on Ubuntu 22.04 with the explicit system
GCC 11 compilers. The packed executable must require no newer versions than
`GLIBC_2.35`, `GLIBCXX_3.4.29` and `CXXABI_1.3.13`. This check remains necessary
even when a CI image happens to have newer C++ runtime libraries installed.
The Linux ARM64, macOS ARM64 and Windows x64 producers retain their native
build hosts; the Linux x64 baseline does not qualify other host architectures.

The workflow packs once, records the NuGet SHA256, and runs that exact package
on both Ubuntu 22.04 and Ubuntu 24.04. Each job checks the ABI floor, executes
`re2c --version`, verifies the canonical Unicode 17 table hashes, generates a
C11 lexer using the packaged syntax and both tables, compiles it, and executes
UTF-8 classification and decimal-category cases. The report records the
package and executable hashes, host RID set, runtime requirements and smoke
result. A failing job blocks publication.

The publishing job downloads the same tested package and verifies its SHA256;
it never rebuilds it. Pull requests cannot publish. Existing NuGet versions
are errors rather than successful duplicate skips, so an older payload cannot
be mistaken for the newly validated package. Consumers must pin a published
package version and digest; changing the action's script revision alone does
not identify a package payload.

The original 4.6.4 package was produced on Ubuntu 24.04 with GCC 13.3.0 in
[run 37188024546](https://github.com/qigao/vcpkg-cache/actions/runs/37188024546).
Its NuGet SHA256 is
`9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269`.
Its Linux x64 executable requires `GLIBCXX_3.4.32`; it is a concrete negative
input for the new compatibility gate. The version 4.6.5 workflow changes are
not themselves evidence of a successful 22.04/24.04 run or a published package.

Upstream project: https://github.com/skvadrik/re2c

Package version: 4.6.5 (upstream re2c 4.6; packaging revision 5)

Upstream source commit: `e485c5d572ab8a9f895b2a3c98e5239bf59254c8`
