# Centralized TLS provider contract for the libpq overlay.
#
# PostgreSQL 16.9 natively targets the OpenSSL API. Keep that contract intact
# and use the vcpkg OpenSSL port rather than carrying BoringSSL compatibility
# patches.

set(LIBPQ_TLS_PROVIDER "openssl")
set(LIBPQ_TLS_CONFIGURE_NAME "openssl")
set(LIBPQ_TLS_OPENSSL_COMPAT_VERSION "3.5.2")
set(LIBPQ_TLS_WINDOWS_PATCHES)
