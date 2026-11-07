"""Offline release CLI checks using disposable repositories."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "scripts/release.py"
OLD = "## [1.1.0] - 2025-01-01\n\n- Keep this entry.\n"
NOTES = "- Promote these notes.\n"

class ReleaseTests(unittest.TestCase):
    def git(self, *args):
        return subprocess.check_output(["git", "-C", self.repo, *args])

    def fixture(self, source="1.2.3", bundle="1.2.3", notes=NOTES, section=""):
        directory = self.enterContext(tempfile.TemporaryDirectory())
        self.repo = pathlib.Path(directory) / "repo"
        self.marker = self.repo.parent / "build-invoked"
        files = {
            "Sources/Limitaur/AppVersion.swift": f'enum AppVersion {{\n    static let string = "{source}"\n}}\n'.encode(),
            "Resources/Info.plist": plistlib.dumps({"CFBundleShortVersionString": bundle}),
            "CHANGELOG.md": f"# Changelog\n\n## [Unreleased]\n\n{notes}\n{section}{OLD}".encode(),
            "scripts/build-app.sh": f'#!/bin/sh\ntouch "{self.marker}"\nexit 99\n'.encode(),
        }
        for name, data in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (self.repo / "scripts/build-app.sh").chmod(0o755)
        if SCRIPT.is_file():
            shutil.copyfile(SCRIPT, self.repo / "scripts/release.py")
        self.git("init", "-q")
        self.git("add", ".")
        self.commit()

    def commit(self):
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "fixture")

    def release(self, *args):
        return subprocess.run([sys.executable, self.repo / "scripts/release.py", *args],
                              cwd=self.repo.parent, capture_output=True, text=True, timeout=20)

    def test_increments(self):
        for bump, expected in (("patch", "1.2.4"), ("minor", "1.3.0"), ("major", "2.0.0")):
            with self.subTest(bump=bump):
                self.fixture()
                head = self.git("rev-parse", "HEAD")
                result = self.release("prepare", bump)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(expected, result.stdout)
                self.assertIn(f'"{expected}"', (self.repo / "Sources/Limitaur/AppVersion.swift").read_text())
                info = plistlib.loads((self.repo / "Resources/Info.plist").read_bytes())
                self.assertEqual(info["CFBundleShortVersionString"], expected)
                changelog = (self.repo / "CHANGELOG.md").read_text()
                self.assertRegex(changelog, rf"## \[Unreleased\]\s+## \[{expected.replace('.', '[.]')}\] - \d{{4}}-\d{{2}}-\d{{2}}\n\s+{NOTES}")
                self.assertTrue(changelog.endswith(OLD))
                self.assertEqual(self.git("rev-parse", "HEAD"), head)
                self.assertEqual(self.git("tag"), b"")
                self.assertFalse(self.marker.exists())

    def test_preflight_rejections(self):
        self.assertTrue(SCRIPT.is_file(), "baseline has no release CLI to test rejections")
        for command, case in (("prepare", "invalid"), ("prepare", "mismatch"), ("prepare", "empty"),
                              ("prepare", "target-tag"), ("prepare", "dirty"), ("package", "dirty"),
                              ("package", "undated"), ("package", "stale"), ("package", "wrong-commit"),
                              ("package", "existing-zip")):
            with self.subTest(command=command, case=case):
                version = "01.2.3" if case == "invalid" else "1.2.3"
                date = "" if case == "undated" else " - 2026-01-01"
                section = f"## [1.2.3]{date}\n\n{NOTES}\n" if command == "package" else ""
                self.fixture(version, "1.2.2" if case == "mismatch" else version,
                             "" if case == "empty" else NOTES, section)
                tags = {"target-tag": "v1.2.4", "stale": "v1.3.0", "wrong-commit": "v1.2.3"}
                if case in tags:
                    self.git("tag", tags[case])
                if case == "wrong-commit":
                    self.commit()
                if case == "dirty":
                    (self.repo / "untracked").touch()
                output = self.repo.parent / "Limitaur-1.2.3-macos-arm64.zip"
                if case == "existing-zip":
                    output.write_bytes(b"preserve")
                before = self.git("status", "--porcelain")
                args = ["patch"] if command == "prepare" else ["--output-dir", str(output.parent)]
                result = self.release(command, *args)
                if case == "existing-zip":
                    self.assertEqual(output.read_bytes(), b"preserve")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.marker.exists())
                self.assertEqual(self.git("status", "--porcelain"), before)
