# Centralized TLS provider contract for the libpq overlay.
#
# GmSSL is the only provider in this branch. PostgreSQL still consumes its
# OpenSSL-shaped TLS API through the dedicated GmSSL compatibility layer.

set(LIBPQ_TLS_PROVIDER "gmssl-openssl-compat")
set(LIBPQ_TLS_CONFIGURE_NAME "openssl")
set(LIBPQ_TLS_OPENSSL_COMPAT_VERSION "3.0.0")
set(LIBPQ_TLS_WINDOWS_PATCHES)
