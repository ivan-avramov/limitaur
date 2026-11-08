"""Exercise default release publishing with a synthetic app and real ZIP files."""
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

SPEC = importlib.util.spec_from_file_location(
    "release", Path(__file__).resolve().parents[2] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class LayoutTests(unittest.TestCase):
    version = "1.2.3"
    archive = "Limitaur-1.2.3-macos-arm64.zip"
    fail_build = False

    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.build = self.root / "build"
        (self.root / release.SWIFT).parent.mkdir(parents=True)
        (self.root / release.SWIFT).write_text(f'static let string = "{self.version}"\n')
        (self.root / release.PLIST).parent.mkdir()
        (self.root / release.PLIST).write_bytes(
            plistlib.dumps({"CFBundleShortVersionString": self.version}))
        (self.root / release.LOG).write_text(f"## [{self.version}] - 2026-01-01\n")
        self.enterContext(patch.multiple(release, ROOT=self.root, run=self.run_command))

    def run_command(self, *args, **kwargs):
        if args[:2] == ("git", "clone"):
            clone = Path(args[-1])
            clone.mkdir()
            (clone / "LICENSE").write_bytes(b"license")
        elif args[0] == "sh":
            contents = Path(args[2]) / "Contents"
            for name in ("MacOS/Limitaur", "Resources/LICENSE", "Resources/AppIcon.icns"):
                path = contents / name
                path.parent.mkdir(exist_ok=True, parents=True)
                path.write_bytes(b"license")
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleShortVersionString": self.version, "CFBundleVersion": "100",
                "LimitaurSourceRevision": "revision", "LimitaurBuildDate": "2026-01-01T00:00:00Z",
                "LSUIElement": True, "LSMinimumSystemVersion": "26.0",
                "CFBundleIconFile": "AppIcon.icns",
            }))
            if self.fail_build:
                raise subprocess.CalledProcessError(1, args)
        elif args[:2] == ("ditto", "-c"):
            app = Path(args[-2])
            with ZipFile(args[-1], "w") as archive:
                for file in app.rglob("*"):
                    if file.is_file():
                        archive.write(file, file.relative_to(app.parent))
        elif args[:2] == ("ditto", "-x"):
            with ZipFile(args[-2]) as archive:
                archive.extractall(args[-1])
        elif args[0] == "git":
            return {"rev-parse": "false" if args[2].startswith("--") else "revision",
                    "rev-list": "100"}.get(args[1], "")
        elif args[0] == "lipo":
            return "arm64"
        elif args[-1] == "--version":
            return self.version
        elif args[0] != "codesign":
            self.fail(f"unexpected command {args}")

    def test_default_package_replaces_generated_outputs(self):
        self.build.mkdir()
        for name in (self.archive, "Limitaur-1.2.2-macos-arm64.zip",
                     "Limitaur-1.2.2-macos-arm64.zip.sha256", "Limitaur.app.sha256", ".DS_Store"):
            (self.build / name).write_bytes(b"old")
        old_app = self.build / "Limitaur.app"
        old_app.mkdir()
        (old_app / "old").touch()
        for _ in range(2):
            release.package(None)
            checksum = self.archive + ".sha256"
            self.assertEqual({p.name for p in self.build.iterdir()},
                             {"Limitaur.app", self.archive, checksum})
            self.assertFalse((old_app / "old").exists())
            archive = self.build / self.archive
            self.assertEqual((self.build / checksum).read_text(),
                             f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {self.archive}\n")
            with ZipFile(archive) as zipped:
                binary = "Contents/MacOS/Limitaur"
                self.assertEqual((old_app / binary).read_bytes(),
                                 zipped.read("Limitaur.app/" + binary))

    def test_failed_build_preserves_generated_output(self):
        self.build.mkdir()
        previous = self.build / self.archive
        previous.write_bytes(b"old")
        self.fail_build = True
        with self.assertRaises(subprocess.CalledProcessError):
            release.package(None)
        self.assertEqual(list(self.build.iterdir()), [previous])
        self.assertEqual(previous.read_bytes(), b"old")

    def test_refuses_unrelated_contents(self):
        self.build.mkdir()
        marker = self.build / "keep"
        marker.write_bytes(b"keep")
        with self.assertRaises((ValueError, OSError)):
            release.package(None)
        self.assertEqual(list(self.build.iterdir()), [marker])
        self.assertEqual(marker.read_bytes(), b"keep")

    def test_refuses_symlink_root(self):
        target = self.root / "other"
        target.mkdir()
        self.build.symlink_to(target, target_is_directory=True)
        with self.assertRaises((ValueError, OSError)):
            release.package(None)
        self.assertEqual(self.build.readlink(), target)
        self.assertEqual(list(target.iterdir()), [])

    def test_refuses_file_root(self):
        self.build.write_bytes(b"keep")
        with self.assertRaises((ValueError, OSError)):
            release.package(None)
        self.assertEqual(self.build.read_bytes(), b"keep")
