"""Keep the ABI floor strict even on CI images with newer runtime packages."""
import io
import unittest
import zipfile

from verify_linux_package import HOST_RIDS, UNICODE_SHA256, package_layout, required_versions


BASE = """
Version needs section '.gnu.version_r' contains 3 entries:
  0x0010: Name: GLIBC_2.34 Flags: none Version: 2
  0x0020: Name: GLIBCXX_3.4.29 Flags: none Version: 3
  0x0030: Name: CXXABI_1.3.8 Flags: none Version: 4
"""


class LinuxCompatibilityTests(unittest.TestCase):
    def archive(self, omitted="", extra=""):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            for rid in HOST_RIDS:
                executable = "re2c.exe" if rid == "windows-x64" else "re2c"
                names = [f"tools/{rid}/bin/{executable}"]
                names += [f"tools/{rid}/share/re2c/stdlib/{name}"
                          for name in (*UNICODE_SHA256, "syntax/c")]
                for name in names:
                    if name != omitted:
                        archive.writestr(name, b"fixture")
            if extra:
                archive.writestr(extra, b"fixture")
        return zipfile.ZipFile(stream)

    def test_all_four_original_hosts_are_required(self):
        with self.archive() as archive:
            self.assertEqual(tuple(package_layout(archive)), HOST_RIDS)
        for name in ("tools/macos-arm64/bin/re2c",
                     "tools/linux-arm64/share/re2c/stdlib/unicode_properties.re",
                     "tools/windows-x64/share/re2c/stdlib/syntax/c"):
            with self.archive(omitted=name) as archive, self.assertRaisesRegex(ValueError, "missing"):
                package_layout(archive)

    def test_unreviewed_host_set_change_fails(self):
        with self.archive(extra="tools/macos-x64/bin/re2c") as archive:
            with self.assertRaisesRegex(ValueError, "host RID set differs"):
                package_layout(archive)

    def test_gcc11_requirements_pass(self):
        versions = required_versions(BASE)
        self.assertEqual(versions["GLIBCXX"], ["3.4.29"])

    def test_actual_464_requirement_is_rejected(self):
        # Original 4.6.4's undefined std::__ios_base_library_init requires this
        # symbol version. Its --version succeeds on a newer host but not 22.04.
        with self.assertRaisesRegex(ValueError, "GLIBCXX_3.4.32 exceeds"):
            required_versions(BASE + "  Name: GLIBCXX_3.4.32 Flags: none Version: 18\n")

    def test_newer_glibc_and_cxxabi_are_rejected(self):
        for name in ("GLIBC_2.36", "CXXABI_1.3.14"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "exceeds"):
                required_versions(BASE + "  Name: " + name + " Flags: none\n")

    def test_missing_and_unrecognized_requirements_fail_closed(self):
        for text in ("", BASE.replace("GLIBCXX_3.4.29", "GCC_3.0"),
                     BASE.replace("GLIBC_2.34", "GLIBC_PRIVATE"),
                     BASE.replace("GLIBCXX_3.4.29", "GLIBCXX_future")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                required_versions(text)


if __name__ == "__main__":
    unittest.main()
