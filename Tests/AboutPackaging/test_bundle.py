#!/usr/bin/env python3
"""Verify a freshly built app: test_bundle.py APP [EXPECTED_REVISION [LICENSE_PATH]]."""
import datetime
import pathlib
import plistlib
import subprocess
import sys
import unittest

APP = pathlib.Path(sys.argv.pop(1)).resolve()
REVISION = sys.argv.pop(1) if len(sys.argv) > 1 else None
LICENSE = pathlib.Path(sys.argv.pop(1)) if len(sys.argv) > 1 else (
    pathlib.Path(__file__).resolve().parents[2] / "LICENSE"
)


class AboutPackagingTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())

    def test_full_source_revision(self):
        actual = self.info["LimitaurSourceRevision"]
        self.assertRegex(actual, r"^[0-9a-f]{40}(?:-dirty)?$")
        if REVISION is not None:
            self.assertEqual(actual, REVISION)

    def test_recent_utc_build_time(self):
        raw = self.info.get("LimitaurBuildDate", "")
        self.assertRegex(raw, r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        built = datetime.datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        self.assertTrue(0 <= (datetime.datetime.now(datetime.timezone.utc) - built).total_seconds() < 3600)

    def test_signed_license_and_version(self):
        subprocess.run(["codesign", "--verify", "--strict", str(APP)], check=True, capture_output=True)
        self.assertEqual(self.info["CFBundleShortVersionString"], "0.2.2")
        version = subprocess.run([str(APP / "Contents/MacOS/Limitaur"), "--version"],
                                 check=True, capture_output=True, text=True, timeout=10)
        self.assertEqual(version.stdout, "0.2.2\n")
        self.assertEqual((APP / "Contents/Resources/LICENSE").read_bytes(), LICENSE.read_bytes())


if __name__ == "__main__":
    unittest.main()
