# Centralized TLS provider contract for the libpq overlay.
#
# Keep this file provider-specific and keep the rest of the port provider-neutral.
# BoringSSL remains the active provider in this behavior-preserving slice.

set(LIBPQ_TLS_PROVIDER "boringssl")
set(LIBPQ_TLS_CONFIGURE_NAME "openssl")
set(LIBPQ_TLS_OPENSSL_COMPAT_VERSION "1.1.1")
set(LIBPQ_TLS_WINDOWS_PATCHES
    windows/boringssl.patch
    windows/boringssl-libpq.patch)
