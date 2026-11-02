"""Exercise the archive gate used before the updater extracts anything."""
import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib


SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "scripts" / "validate_update.py"


class UpdateArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = pathlib.Path(self.temp.name) / "update.zip"

    def check(self):
        return subprocess.run([sys.executable, "-I", "-B", str(SCRIPT), str(self.archive)],
                              capture_output=True).returncode

    def make_archive(self, extras=()):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("NXLibrary.app/Contents/Info.plist", "synthetic")
            archive.writestr("NXLibrary.app/Contents/MacOS/NXLibrary", "synthetic")
            for name, content in extras:
                archive.writestr(name, content)

    def test_accepts_app_and_internal_runtime_symlink(self):
        link = zipfile.ZipInfo("NXLibrary.app/Contents/Resources/Runtime/python/bin/python3")
        link.create_system = 3
        link.external_attr = (0o120777 << 16)
        self.make_archive([(link, "python3.14"),
                           ("NXLibrary.app/Contents/Resources/Runtime/python/bin/python3.14", "synthetic")])
        self.assertEqual(self.check(), 0)

    def test_rejects_traversal_absolute_and_other_roots(self):
        for path in ["../escape", "/tmp/escape", "NXLibrary.app/../../escape", "Other.app/file"]:
            with self.subTest(path=path):
                self.make_archive([(path, "synthetic")])
                self.assertNotEqual(self.check(), 0)

    def test_rejects_escaping_symlink_and_entries_below_symlink(self):
        link = zipfile.ZipInfo("NXLibrary.app/Contents/link")
        link.create_system = 3
        link.external_attr = (0o120777 << 16)
        for target, extras in [("../../outside", []), ("Resources", [("NXLibrary.app/Contents/link/file", "data")])]:
            with self.subTest(target=target):
                self.make_archive([(link, target)] + extras)
                self.assertNotEqual(self.check(), 0)

    def test_rejects_case_colliding_entries(self):
        self.make_archive([("NXLibrary.app/Contents/info.plist", "collision")])
        self.assertNotEqual(self.check(), 0)

    def test_rejects_unicode_equivalent_entries(self):
        self.make_archive([("NXLibrary.app/Contents/caf\u00e9.txt", "first"),
                           ("NXLibrary.app/Contents/cafe\u0301.txt", "collision")])
        self.assertNotEqual(self.check(), 0)

    def test_rejects_local_header_with_different_filename(self):
        self.make_archive()
        data = bytearray(self.archive.read_bytes())
        # Change only the local header's filename; the central directory still looks valid.
        offset = data.index(b"NXLibrary.app/Contents/Info.plist")
        data[offset] = ord("Z")
        self.archive.write_bytes(data)
        self.assertNotEqual(self.check(), 0)

    def test_rejects_declared_expansion_above_two_gibibytes(self):
        self.make_archive()
        data = bytearray(self.archive.read_bytes())
        offset = data.index(b"PK\x01\x02")
        struct.pack_into("<I", data, offset + 24, 2_147_483_649)
        self.archive.write_bytes(data)
        self.assertNotEqual(self.check(), 0)

    def test_rejects_forged_size_and_prefix_crc(self):
        with zipfile.ZipFile(self.archive, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("NXLibrary.app/Contents/Info.plist", "synthetic")
            archive.writestr("NXLibrary.app/Contents/MacOS/NXLibrary", "synthetic")
            archive.writestr("NXLibrary.app/Contents/big", b"x" * 1_048_576)
        data = bytearray(self.archive.read_bytes())
        with zipfile.ZipFile(self.archive) as archive:
            local = archive.getinfo("NXLibrary.app/Contents/big").header_offset
        central = data.index(b"PK\x01\x02", data.index(b"PK\x01\x02") + 1)
        central = data.index(b"PK\x01\x02", central + 1)
        struct.pack_into("<I", data, local + 22, 1)
        struct.pack_into("<I", data, central + 24, 1)
        struct.pack_into("<I", data, local + 14, zlib.crc32(b"x"))
        struct.pack_into("<I", data, central + 16, zlib.crc32(b"x"))
        self.archive.write_bytes(data)
        self.assertNotEqual(self.check(), 0)

    def test_extraction_preserves_executable_and_relative_link(self):
        executable = zipfile.ZipInfo("NXLibrary.app/Contents/MacOS/helper")
        executable.create_system = 3
        executable.external_attr = (0o100755 << 16)
        link = zipfile.ZipInfo("NXLibrary.app/Contents/MacOS/helper-link")
        link.create_system = 3
        link.external_attr = (0o120777 << 16)
        self.make_archive([(executable, "synthetic helper"), (link, "helper")])
        target = pathlib.Path(self.temp.name) / "unpacked"
        result = subprocess.run([sys.executable, "-I", "-B", str(SCRIPT), str(self.archive), str(target)],
                                capture_output=True)
        self.assertEqual(result.returncode, 0)
        helper = target / "NXLibrary.app/Contents/MacOS/helper"
        self.assertTrue(helper.stat().st_mode & 0o100)
        self.assertTrue(helper.with_name("helper-link").is_symlink())

    def test_rejects_invalid_zip(self):
        self.archive.write_bytes(b"not an archive")
        self.assertNotEqual(self.check(), 0)


if __name__ == "__main__":
    unittest.main()
