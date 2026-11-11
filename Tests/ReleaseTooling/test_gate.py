"""The package command requires a complete, passing release-gate record from a clean tree at HEAD."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "release", Path(__file__).resolve().parents[2] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)

GOOD = {"revision": "revision", "passed": True, "complete": True, "dirty": False}


class Reached(Exception):
    pass


class GateTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        (self.root / release.SWIFT).parent.mkdir(parents=True)
        (self.root / release.SWIFT).write_text('static let string = "1.2.3"\n')
        (self.root / release.PLIST).parent.mkdir()
        (self.root / release.PLIST).write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.2.3"}))
        (self.root / release.LOG).write_text("## [1.2.3] - 2026-01-01\n")
        self.enterContext(patch.multiple(release, ROOT=self.root, run=self.run_command))

    def run_command(self, *args, **kwargs):
        if args[:2] == ("git", "clone"):
            raise Reached()
        if args[0] == "git":
            return {"rev-parse": "false" if args[2].startswith("--") else "revision", "rev-list": "100"}.get(args[1], "")
        return ""

    def record(self, data):
        path = self.root / ".build/release-gate/revision/result.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def test_missing_record_refuses_before_building(self):
        with self.assertRaisesRegex(ValueError, "release gate"):
            release.package(None, require_gate=True)
        self.assertFalse((self.root / "build").exists())

    def test_incomplete_failed_dirty_or_other_revision_refuses(self):
        for change in ({"passed": False}, {"complete": False}, {"dirty": True}, {"revision": "other"}, {"passed": "true"}):
            with self.subTest(change=change):
                self.record(GOOD | change)
                with self.assertRaisesRegex(ValueError, "release gate"):
                    release.package(None, require_gate=True)

    def test_passing_record_proceeds_to_build(self):
        self.record(GOOD)
        with self.assertRaises(Reached):
            release.package(None, require_gate=True)

    def test_direct_calls_keep_the_previous_behaviour(self):
        with self.assertRaises(Reached):
            release.package(None)


if __name__ == "__main__":
    unittest.main()
