# FlowMQ.Native

`FlowMQ.Native` is the centrally qualified native SDK package for `qigao/flowmq`.

The initial package profile is Linux x64 Release. The workflow checks out FlowMQ `main`,
restores released `Salts.Native` 1.2.0 and `SaltsUtils.Native` 2.0.2, consumes third-party
dependencies through the shared qigao vcpkg binary cache, builds/tests/installs FlowMQ,
packs the installed SDK, then restores that package into a clean external CMake consumer.

Package versions are derived from the FlowMQ CMake project version and receive a CI suffix:

```text
<flowmq-version>-ci.<github-run-number>.<run-attempt>
```

This lets the central publisher track FlowMQ `main` without overwriting a previously
qualified package while preserving the product version as the package-version prefix.

The package carries the installed FlowMQ SDK under `sdk/linux-x64/` and declares exact
NuGet dependencies on the released Salts and SaltsUtils SDK packages. The consumer still
uses vcpkg for ABI-compatible third-party libraries such as BoringSSL and ZeroMQ.
