#!/usr/bin/env python3
"""Offline checks: python3 Tests/IconPackaging/test_bundle.py /path/Limitaur.app."""
import pathlib
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest

APP = pathlib.Path(sys.argv.pop(1)).resolve()


class IconPackagingTests(unittest.TestCase):
    def setUp(self):
        with (APP / "Contents/Info.plist").open("rb") as stream:
            self.info = plistlib.load(stream)

    def icon(self):
        name = self.info.get("CFBundleIconFile")
        self.assertEqual(name, "AppIcon.icns", "bundle must register AppIcon.icns")
        icon = APP / "Contents/Resources" / name
        self.assertTrue(icon.is_file(), "registered icon must be packaged")
        return icon

    def test_registered_icon_is_packaged(self):
        self.icon()

    def test_standard_icon_representations_decode(self):
        icon = self.icon()
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "AppIcon.iconset"
            subprocess.run(["iconutil", "-c", "iconset", str(icon), "-o", str(output)],
                           check=True, capture_output=True)
            for size in (16, 32, 128, 256, 512):
                for scale in (1, 2):
                    suffix = "@2x" if scale == 2 else ""
                    filename = output / f"icon_{size}x{size}{suffix}.png"
                    with self.subTest(representation=filename.name):
                        data = filename.read_bytes()
                        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                        self.assertEqual(struct.unpack(">II", data[16:24]),
                                         (size * scale, size * scale))

    def test_menu_bar_mode_and_version_preserved(self):
        self.assertIs(self.info.get("LSUIElement"), True)
        self.assertEqual(self.info.get("CFBundleShortVersionString"), "0.2.1")
        self.assertRegex(str(self.info.get("CFBundleVersion", "")), r"^[1-9][0-9]*$")
        version = subprocess.run([str(APP / "Contents/MacOS/Limitaur"), "--version"],
                                 check=True, capture_output=True, text=True)
        self.assertEqual(version.stdout.strip(), "0.2.1")

    def test_bundle_signature_verifies(self):
        subprocess.run(["codesign", "--verify", "--strict", str(APP)],
                       check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
