"""The UI-pass waiver accepts only a clean, complete record whose sole failure is the UI step."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "release", Path(__file__).resolve().parents[2] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)

REV = "a" * 40


class WaiverTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.enterContext(patch.object(release, "ROOT", self.root))
        self.enterContext(patch("sys.stderr"))

    def write(self, steps, **fields):
        record = {"revision": REV, "dirty": False, "complete": True,
                  "passed": all(s["ok"] for s in steps), "steps": steps}
        record.update(fields)
        path = self.root / ".build/release-gate" / REV
        path.mkdir(parents=True, exist_ok=True)
        (path / "result.json").write_text(json.dumps(record))

    def test_passing_record_needs_no_waiver(self):
        self.write([{"name": "swift-test", "ok": True}, {"name": "ui", "ok": True}])
        release.check_gate(REV)

    def test_ui_failure_rejected_without_waiver(self):
        self.write([{"name": "swift-test", "ok": True}, {"name": "ui", "ok": False}])
        with self.assertRaises(ValueError):
            release.check_gate(REV)

    def test_ui_failure_accepted_with_waiver(self):
        self.write([{"name": "swift-test", "ok": True}, {"name": "ui", "ok": False}])
        release.check_gate(REV, waive_ui=True)

    def test_other_failure_rejected_with_waiver(self):
        self.write([{"name": "swift-test", "ok": False}, {"name": "ui", "ok": False}])
        with self.assertRaises(ValueError):
            release.check_gate(REV, waive_ui=True)

    def test_dirty_incomplete_or_stepless_record_rejected_with_waiver(self):
        ui = [{"name": "swift-test", "ok": True}, {"name": "ui", "ok": False}]
        for fields, steps in (({"dirty": True}, ui), ({"complete": False}, ui), ({"passed": False}, [])):
            self.write(steps, **fields)
            with self.assertRaises(ValueError):
                release.check_gate(REV, waive_ui=True)


if __name__ == "__main__":
    unittest.main()
