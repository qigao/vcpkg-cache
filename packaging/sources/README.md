# Locked upstream source downloads

`lua-5.4.8.tar.gz` is the unmodified Lua 5.4.8 source distribution from
https://www.lua.org/ftp/lua-5.4.8.tar.gz, recovered from the existing vcpkg
download cache. Lua is distributed under the MIT license; its original
copyright/license are retained inside the archive (`doc/readme.html`).

- Upstream SHA-256: `4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae`
- Pinned vcpkg SHA-512: `875ad1f6df3ba63722b5069564c9d3a4057b4c3564c691061bb49cf6cdf5d2e303f05762bd46797b444aaf992c03021f423df142123eebf86751fd77edaf8060`

The producer copies these required, digest-checked bytes into its normal
vcpkg downloads directory before resolving/building dependencies. The port
still verifies its original archive hash. This avoids depending on Lua's live
TLS endpoint for this pinned input; there is no alternate implementation,
automatic mirror search, changed port version, or TLS verification override.
