#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
SWIFT = Path('Sources/Limitaur/AppVersion.swift')
PLIST = Path('Resources/Info.plist')
LOG = Path('CHANGELOG.md')
def run(*args, cwd=ROOT, env=None):
    return subprocess.run(args, cwd=cwd, env=env, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True).stdout.strip()
def require(condition, message):
    if not condition:
        raise ValueError(message)
def preflight():
    require(not run('git', 'status', '--porcelain', '--untracked-files=normal'), 'working tree is dirty')
    require(run('git', 'rev-parse', '--is-shallow-repository') == 'false', 'shallow history')
    matches = re.findall(r'^\s*static let string = "([^"]*)"\s*$', (ROOT / SWIFT).read_text(), re.M)
    require(len(matches) == 1 and re.fullmatch(VERSION, matches[0]), 'invalid source version')
    version = matches[0]
    require(plistlib.loads((ROOT / PLIST).read_bytes()).get('CFBundleShortVersionString') == version, 'plist version mismatch')
    return version

def prepare(kind):
    version = preflight()
    numbers = list(map(int, version.split('.')))
    index = {'major': 0, 'minor': 1, 'patch': 2}[kind]
    numbers[index] += 1
    numbers[index + 1:] = [0] * (2 - index)
    target = '.'.join(map(str, numbers))
    require(not run('git', 'tag', '-l', 'v' + target), 'target tag already exists')
    log = (ROOT / LOG).read_text()
    require(not re.search(r'^## \[' + re.escape(target) + r'\]', log, re.M), 'target changelog entry already exists')
    sections = list(re.finditer(r'^## \[Unreleased\]\s*$', log, re.M))
    require(len(sections) == 1, 'missing or duplicate Unreleased section')
    start = sections[0].end()
    next_section = re.search(r'^## \[', log[start:], re.M)
    end = start + next_section.start() if next_section else len(log)
    notes = log[start:end].strip()
    require(bool(notes), 'Unreleased notes are empty')
    swift = (ROOT / SWIFT).read_text().replace('static let string = "' + version + '"', 'static let string = "' + target + '"')
    plist = (ROOT / PLIST).read_text()
    plist, count = re.subn(r'(<key>CFBundleShortVersionString</key>\s*<string>)' + re.escape(version) + r'(</string>)', r'\g<1>' + target + r'\2', plist)
    require(count == 1, 'cannot update plist version')
    log = log[:start] + '\n\n## [' + target + '] - ' + str(datetime.date.today()) + '\n\n' + notes + '\n\n' + log[end:]
    (ROOT / SWIFT).write_text(swift)
    (ROOT / PLIST).write_text(plist)
    (ROOT / LOG).write_text(log)
    print(target)
def validate(app, version, revision, count, license_bytes):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    binary = app / 'Contents/MacOS/Limitaur'
    require(run(str(binary), '--version') == version, 'binary version mismatch')
    require(info.get('CFBundleShortVersionString') == version and info.get('CFBundleVersion') == count, 'bundle version mismatch')
    require(info.get('LimitaurSourceRevision') == revision, 'bundle revision mismatch')
    stamp = info.get('LimitaurBuildDate', '')
    require(bool(re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', stamp)), 'invalid build time')
    datetime.datetime.strptime(stamp, '%Y-%m-%dT%H:%M:%SZ')
    require(run('lipo', '-archs', str(binary)) == 'arm64', 'binary is not arm64-only')
    require(info.get('LSUIElement') is True and info.get('LSMinimumSystemVersion') == '26.0', 'invalid bundle settings')
    resources = app / 'Contents/Resources'
    require((resources / 'LICENSE').read_bytes() == license_bytes, 'license mismatch')
    require(info.get('CFBundleIconFile') == 'AppIcon.icns' and (resources / 'AppIcon.icns').is_file(), 'missing registered icon')
    run('codesign', '--verify', '--strict', str(app))

def package(output):
    version = preflight()
    log = (ROOT / LOG).read_text()
    require(bool(re.search(r'^## \[' + re.escape(version) + r'\] - \d{4}-\d{2}-\d{2}\s*$', log, re.M)), 'missing dated changelog entry')
    revision = run('git', 'rev-parse', 'HEAD')
    count = run('git', 'rev-list', '--count', 'HEAD')
    stable = [(tuple(map(int, tag[1:].split('.'))), tag) for tag in run('git', 'tag', '-l').splitlines() if re.fullmatch('v' + VERSION, tag)]
    current = tuple(map(int, version.split('.')))
    if stable:
        highest, tag = max(stable)
        require(current >= highest, 'version is older than a release tag')
        require(current != highest or run('git', 'rev-parse', tag + '^{}') == revision, 'version tag is not at HEAD')
    out = Path(output).expanduser().resolve() if output else ROOT / 'dist/releases' / version
    name = 'Limitaur-' + version + '-macos-arm64.zip'
    dest, checksum = out / name, out / (name + '.sha256')
    require(not os.path.lexists(dest) and not os.path.lexists(checksum), 'release output already exists')
    with tempfile.TemporaryDirectory(prefix='limitaur-release-') as tmp:
        temp = Path(tmp)
        clone = temp / 'source'
        run('git', 'clone', '--no-local', str(ROOT), str(clone), cwd=temp)
        run('git', 'checkout', '--detach', revision, cwd=clone)
        app = temp / 'Limitaur.app'
        env = os.environ.copy()
        env['LIMITAUR_SIGN_IDENTITY'] = '-'
        run('sh', 'scripts/build-app.sh', str(app), '--arch', 'arm64', '--build-system', 'native', cwd=clone, env=env)
        license_bytes = (clone / 'LICENSE').read_bytes()
        validate(app, version, revision, count, license_bytes)
        archive = temp / name
        run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', str(app), str(archive))
        with zipfile.ZipFile(archive) as z:
            require(bool(z.namelist()) and z.testzip() is None and all(p.split('/')[0] == 'Limitaur.app' for p in z.namelist()), 'invalid archive')
        extracted = temp / 'extracted'
        extracted.mkdir()
        run('ditto', '-x', '-k', str(archive), str(extracted))
        validate(extracted / 'Limitaur.app', version, revision, count, license_bytes)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        check = temp / (name + '.sha256')
        check.write_text(digest + '  ' + name + '\n')
        require(hashlib.sha256(archive.read_bytes()).hexdigest() == check.read_text().split('  ')[0], 'checksum mismatch')
        out.mkdir(parents=True, exist_ok=True)
        with dest.open('xb') as f:
            try:
                f.write(archive.read_bytes())
                with checksum.open('xb') as c:
                    try:
                        c.write(check.read_bytes())
                    except Exception:
                        checksum.unlink()
                        raise
            except Exception:
                dest.unlink()
                raise
    print(dest)
    print(checksum)
def main():
    parser = argparse.ArgumentParser(description='Prepare and package local Limitaur releases')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('prepare').add_argument('increment', choices=('patch', 'minor', 'major'))
    commands.add_parser('package').add_argument('--output-dir')
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            prepare(args.increment)
        else:
            package(args.output_dir)
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        print('release: ' + str(error), file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
