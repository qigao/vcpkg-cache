# Normalize public Windows preprocessor guards for ordinary MSVC consumers.
# MSVC guarantees _WIN32; WIN32 is not a language/toolchain guarantee.

foreach(_gmssl_public_header IN ITEMS
        "${SOURCE_PATH}/include/gmssl/socket.h"
        "${SOURCE_PATH}/include/gmssl/dylib.h")
    vcpkg_replace_string(
        "${_gmssl_public_header}"
        "#ifdef WIN32"
        "#if defined(_WIN32) || defined(WIN32)"
    )
endforeach()

unset(_gmssl_public_header)

# Android API 24 does not export getentropy(). Preserve GmSSL's bounded
# 256-byte rand_bytes() contract with a fail-closed /dev/urandom read loop.
set(_gmssl_rand_unix_c "${SOURCE_PATH}/src/rand_unix.c")
vcpkg_replace_string(
    "${_gmssl_rand_unix_c}"
    "#include <unistd.h> // in Linux"
    "#include <unistd.h> // in Linux\n#ifdef __ANDROID__\n#include <errno.h>\n#include <fcntl.h>\n#endif"
)
vcpkg_replace_string(
    "${_gmssl_rand_unix_c}"
[==[
	if (getentropy(buf, len) != 0) {
		error_print();
		return -1;
	}
]==]
[==[
#ifdef __ANDROID__
	{
		int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
		size_t offset = 0;
		if (fd < 0) {
			error_print();
			return -1;
		}
		while (offset < len) {
			ssize_t n = read(fd, buf + offset, len - offset);
			if (n > 0) {
				offset += (size_t)n;
				continue;
			}
			if (n < 0 && errno == EINTR) {
				continue;
			}
			(void)close(fd);
			error_print();
			return -1;
		}
		if (close(fd) != 0) {
			error_print();
			return -1;
		}
	}
#else
	if (getentropy(buf, len) != 0) {
		error_print();
		return -1;
	}
#endif
]==]
)
unset(_gmssl_rand_unix_c)

