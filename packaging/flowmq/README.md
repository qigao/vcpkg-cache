# FlowMQ.Native

`FlowMQ.Native` is the centrally qualified native SDK package for `qigao/flowmq`.

The package is built from one pinned FlowMQ `main` commit and contains Release SDK profiles for:

- `linux-x64` — build, full FlowMQ CTest, package restore, external consumer compile/link/run.
- `windows-x64` — build, full FlowMQ CTest, package restore, external consumer compile/link/run.
- the architecture of the `macos-15` publisher (`macos-x64` or `macos-arm64`) — build, full FlowMQ CTest, package restore, external consumer compile/link/run.
- `android-arm64-v8a` at API 26 — cross-build plus package restore and external NDK consumer compile/link. No emulator/runtime qualification is claimed.

Released `Salts.Native` 1.2.0 and `SaltsUtils.Native` 2.0.2 are exact NuGet dependencies. Cross compilation keeps target and host profiles separate: Android links the Android SDK profiles while FMP/1 code generation executes the Linux-host `tbe_compiler` from `SaltsUtils.Native`.

Every platform first restores BoringSSL and ZeroMQ through the shared qigao vcpkg cache with `--only-binarycaching`. A missing ABI-compatible package fails qualification rather than silently compiling a private dependency copy.

Package versions are derived from the FlowMQ CMake project version:

```text
<flowmq-version>-ci.<github-run-number>.<run-attempt>
```

The package carries each installed FlowMQ SDK under `sdk/<rid>/` and records source/dependency provenance in `flowmq-sdk-manifest.txt`.
