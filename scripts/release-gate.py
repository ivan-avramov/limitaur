#!/usr/bin/env python3
"""Release gate: native tests, the frozen Python suites and a scripted UI pass against live data.

Writes .build/release-gate/<revision>/ (result.json, logs/, shots/). `release.py package` refuses to
package unless HEAD has a complete, passing record from a clean tree.

The UI pass takes over the mouse and keyboard for a few minutes. It quits any running Limitaur,
backs up and restores the app's preferences, and relaunches a previously running bundle.
One-time setup: Accessibility and Screen Recording for the terminal; Claude and Cursor enabled and
signed in (Keychain reads go through /usr/bin/security, so rebuilds do not prompt again).
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
import traceback

ROOT = Path(__file__).resolve().parent.parent
DOMAIN = 'local.limitaur.app'
RESET_KEYS = ('sharedBudget', 'claudeSpendResetDay', 'settingsWindowTopLeft', 'NSWindow Frame LimitaurSettings')


class GateFailure(Exception):
    pass


def sh(*args, check=True, timeout=None, **kw):
    return subprocess.run(args, check=check, timeout=timeout, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)


def git(*args):
    return sh('git', *args, cwd=ROOT).stdout.strip()


# MARK: - Steps

def test_steps(binary):
    adv = dict(os.environ, LIMITAUR_BINARY=str(binary))
    bars = dict(os.environ, LIMITAUR_BIN=str(binary))
    py = [sys.executable, '-m', 'unittest']
    return [
        ('swift-test', ['swift', 'test', '--parallel'], None, 900),
        ('swift-test-serial', ['swift', 'test', '--no-parallel'], None, 1200),
        ('release-build', ['swift', 'build', '-c', 'release'], None, 900),
        ('adversarial', py + ['Adversarial/test_acceptance.py'], adv, 300),
        ('adversarial-bars', py + ['discover', '-s', 'AdversarialBars', '-p', 'test_acceptance.py'], bars, 300),
        ('adversarial-claude', py + ['AdversarialClaude/test_acceptance.py'], adv, 300),
        ('release-tooling', py + ['discover', '-s', 'Tests/ReleaseTooling'], None, 300),
        ('measurement', py + ['discover', '-s', 'Tests/MeasurementTests'], None, 300),
    ]


def run_step(record, logs, name, cmd, env, timeout):
    started = time.monotonic()
    log = logs / (name + '.log')
    with log.open('w') as out:
        try:
            code = subprocess.run(cmd, cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            code = 'timeout'
    ok = code == 0
    tail = log.read_text(errors='replace').strip().splitlines()[-3:]
    record['steps'].append({'name': name, 'ok': ok, 'seconds': round(time.monotonic() - started, 1),
                            'detail': ' | '.join(tail)[-400:]})
    print(f"{'PASS' if ok else 'FAIL'}  {name}  ({record['steps'][-1]['seconds']}s)", flush=True)
    return ok


# MARK: - UI driver

class UI:
    def __init__(self, helper, pid, shots):
        self.helper, self.pid, self.shots = str(helper), pid, shots

    def call(self, *args):
        result = sh(self.helper, *map(str, args), check=False, timeout=30)
        if result.returncode != 0:
            raise GateFailure(f"uihelper {args[0]}: {result.stderr.strip()}")
        return result.stdout

    def tree(self):
        return json.loads(self.call('tree', self.pid))

    def windows(self):
        return json.loads(self.call('windows', self.pid))

    def press(self, node):
        self.call('press', self.pid, node['path'])

    def set_value(self, node, value):
        self.call('set', self.pid, node['path'], value)

    def focus(self, node):
        self.call('focus', self.pid, node['path'])

    def move(self, node, x, y):
        self.call('move', self.pid, node['path'], f'{x},{y}')

    def click(self, x, y):
        self.call('click', round(x, 1), round(y, 1))

    def click_node(self, node, dx=None):
        x, y, w, h = node['frame']
        self.click(x + (w / 2 if dx is None else dx), y + h / 2)

    @staticmethod
    def keystroke(text, command=False):
        using = ' using command down' if command else ''
        sh('osascript', '-e', f'tell application "System Events" to keystroke "{text}"{using}', timeout=20)

    @staticmethod
    def keycode(code):
        sh('osascript', '-e', f'tell application "System Events" to key code {code}', timeout=20)

    def wait(self, what, probe, timeout=20.0, interval=0.5):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            try:
                last = probe()
            except GateFailure:
                last = None
            if last:
                return last
            time.sleep(interval)
        raise GateFailure(f'timed out waiting for {what}')

    def shot(self, name, window=None, rect=None):
        path = self.shots / (name + '.png')
        if window is not None:
            sh('screencapture', '-x', '-o', '-l', str(window), str(path), check=False)
        elif rect is not None:
            x, y, w, h = rect
            sh('screencapture', '-x', '-R', f'{x},{y},{w},{h}', str(path), check=False)
        return path


def label(node):
    return node.get('title') or node.get('desc') or ''


def within(nodes, parent):
    prefix = parent['path'] + '.'
    return [n for n in nodes if n['path'].startswith(prefix)]


def first(nodes, what, **match):
    for n in nodes:
        if all((n.get(k) if k != 'label' else label(n)) == v for k, v in match.items()):
            return n
    raise GateFailure(f'missing {what}')


def labelled(nodes, text, role, what=None):
    """A control by its own title or description, else the first sibling of `role` after a static text `text`."""
    for n in nodes:
        if n.get('role') == role and label(n) == text:
            return n
    for n in nodes:
        if n.get('role') == 'AXStaticText' and n.get('value') == text:
            parent, index = n['path'].rsplit('.', 1)
            siblings = [s for s in nodes if s.get('role') == role and s['path'].rsplit('.', 1)[0] == parent
                        and int(s['path'].rsplit('.', 1)[1]) > int(index)]
            if siblings:
                return min(siblings, key=lambda s: int(s['path'].rsplit('.', 1)[1]))
    raise GateFailure(f'missing {what or text}')


def ending(nodes, role, text):
    """SwiftUI may prefix a description with the visible label ("Label, Label for …")."""
    for n in nodes:
        if n.get('role') == role and label(n).endswith(text):
            return n
    raise GateFailure(f'missing {text}')


def status_item(nodes):
    return first(nodes, 'menu-bar status item', role='AXMenuBarItem', subrole='AXMenuExtra')


def slots(nodes):
    """(provider or None, percent) per menu-bar slot, from the status item's accessibility description."""
    out = []
    for part in status_item(nodes).get('desc', '').split('; '):
        if not part:
            continue
        if part.startswith('unavailable slot'):
            out.append((None, None))
            continue
        m = re.search(r'([\d.]+) percent', part)
        out.append((part.split(',')[0].strip(), float(m.group(1)) if m else None))
    return out


def popover(nodes):
    return next((n for n in nodes if n.get('role') == 'AXPopover'), None)


def settings_window(nodes):
    return next((n for n in nodes if n.get('role') == 'AXWindow' and n.get('subrole') == 'AXStandardWindow'), None)


def amount_in(texts, name):
    """A member row's amount, whether exposed as "Name, $1.00" or as "Name" then "$1.00"."""
    for i, x in enumerate(texts):
        m = re.fullmatch(re.escape(name) + r',? (\$[\d,]+\.\d\d)', x)
        if m:
            return money(m.group(1))
        if x == name and i + 1 < len(texts) and re.fullmatch(r'\$[\d,]+\.\d\d', texts[i + 1]):
            return money(texts[i + 1])
    return None


def money(text):
    return float(text.replace('$', '').replace(',', ''))


def prefs():
    out = sh('defaults', 'export', DOMAIN, '-', check=False)
    return plistlib.loads(out.stdout.encode()) if out.returncode == 0 else {}


def profiles():
    raw = prefs().get('profiles')
    return json.loads(raw) if raw else []


class UIPass:
    def __init__(self, ui, record):
        self.ui, self.record = ui, record
        self.checks = record['ui'] = []

    def check(self, name, ok, detail=''):
        self.checks.append({'name': name, 'ok': bool(ok), 'detail': detail})
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{'  ' + detail if detail else ''}", flush=True)
        if not ok:
            raise GateFailure(f'{name}: {detail}')

    # Helpers bound to the live tree.
    def open_popover(self):
        nodes = self.ui.tree()
        if not popover(nodes):
            self.ui.press(status_item(nodes))
        return self.ui.wait('popover', lambda: popover(self.ui.tree()) and self.ui.tree())

    def close_popover(self):
        if popover(self.ui.tree()):
            self.ui.press(status_item(self.ui.tree()))
            self.ui.wait('popover to close', lambda: not popover(self.ui.tree()))

    def popover_shot(self, name):
        wins = [w for w in self.ui.windows() if w['layer'] > 0 and w['onscreen']]
        if wins:
            self.ui.shot(name, window=wins[0]['id'])

    def settings(self):
        return self.ui.wait('Settings window', lambda: settings_window(self.ui.tree()))

    def settings_shot(self, name):
        wins = [w for w in self.ui.windows() if w['layer'] == 0 and w['onscreen'] and w['frame'][2] > 200]
        if wins:
            self.ui.shot(name, window=wins[0]['id'])

    def activate(self, window):
        """Synthetic keys reach Settings only when it is key; a real click on the title bar makes it so."""
        x, y, w, _ = window['frame']
        self.ui.click(x + w / 2, y + 12)
        time.sleep(0.6)

    def open_settings(self):
        self.open_popover()
        self.ui.keystroke(',', command=True)
        return self.settings()

    def window_nodes(self):
        nodes = self.ui.tree()
        window = settings_window(nodes)
        if not window:
            raise GateFailure('Settings window not open')
        return window, within(nodes, window)

    def tab(self, name):
        window, inside = self.window_nodes()
        self.ui.press(first(inside, f'{name} tab', role='AXButton', label=name))
        return self.ui.wait(f'{name} tab title', lambda: (w := settings_window(self.ui.tree())) and w.get('title') == name and w)

    def run(self):
        try:
            self.checks_in_order()
        except GateFailure:
            try:
                (self.ui.shots.parent / 'logs' / 'failure-tree.json').write_text(json.dumps(self.ui.tree(), indent=1))
            except GateFailure:
                pass
            raise

    def checks_in_order(self):
        ui = self.ui
        nodes = ui.wait('Claude and Cursor bars to be fresh', lambda: (
            n := ui.tree()) and {'claude', 'cursor'} <= {p for p, v in slots(n) if v is not None} and n, timeout=120)
        item = status_item(nodes)
        ui.shot('menubar-budget-off', rect=[item['frame'][0] - 4, 0, item['frame'][2] + 8, 30])
        self.check('menu bar shows Claude and Cursor', [p for p, _ in slots(nodes)] and 'budget' not in dict(slots(nodes)),
                   str(slots(nodes)))

        nodes = self.open_popover()
        pop = within(nodes, popover(nodes))
        texts = [n.get('value', '') for n in pop if n.get('role') == 'AXStaticText']
        descs = [n.get('desc', '') for n in pop if n.get('role') == 'AXUnknown']
        for provider in ('Claude', 'Cursor'):
            self.check(f'{provider} card', any(t == provider or t.startswith(provider + ' · ') for t in texts))
        self.check('cards Healthy', descs.count('Healthy') >= 2, str([d for d in descs if ',' not in d]))
        self.check('Monthly spend metrics', sum(d.startswith('Monthly spend') for d in descs) >= 2)
        self.check('spend rows', sum(x.startswith('Spent this cycle') for x in texts) >= 2
                   and sum(x.startswith('Spend limit') for x in texts) >= 2)
        self.popover_shot('dropdown-budget-off')

        self.refresh_shortcut()

        ui.keystroke(',', command=True)
        window = self.settings()
        self.check('⌘, opens Settings on General', window.get('title') == 'General', repr(window.get('title')))
        general_size = window['frame'][2:]
        self.activate(window)
        self.budget()
        self.indicators()
        providers = self.tab('Providers')
        self.check('Settings resizes per tab', providers['frame'][3] != general_size[1],
                   f"{general_size[1]} -> {providers['frame'][3]}")
        _, inside = self.window_nodes()
        resets = labelled(inside, 'Spend resets', 'AXPopUpButton')
        self.check('Claude Spend resets defaults to 1st', resets.get('value') == '1st', repr(resets.get('value')))
        self.settings_shot('settings-providers')
        self.label_commit()
        self.close_and_position()

    def refresh_shortcut(self):
        stats = Path(self.record['stats'])
        def counts():
            try:
                data = json.loads(stats.read_text())
            except (OSError, ValueError):
                return None
            return {p: sum(v.values()) for p, v in data.items() if isinstance(v, dict)}
        before = self.ui.wait('statistics file', counts, timeout=30)
        self.ui.keystroke('r', command=True)
        def advanced():
            now = counts() or {}
            return all(now.get(p, 0) > before.get(p, 0) for p in ('claude', 'cursor')) and now
        try:
            after = self.ui.wait('⌘R refresh', advanced, timeout=15)
        except GateFailure:
            after = counts()
        self.check('⌘R refreshes Claude and Cursor', after and advanced(), f'{before} -> {after}')

    def budget(self):
        window, inside = self.window_nodes()
        self.ui.press(labelled(inside, 'Track a shared monthly budget', 'AXCheckBox', 'budget switch'))
        amount = self.ui.wait('amount field', lambda: labelled(within(self.ui.tree(), settings_window(self.ui.tree())), 'Amount', 'AXTextField'))
        window, inside = self.window_nodes()
        prefilled = bool(re.fullmatch(r'\$[\d,]+\.\d\d', amount.get('value', '')))
        self.prefilled = prefilled
        self.check('amount pre-fills from the common reported limit', prefilled, 'pre-filled' if prefilled else repr(amount.get('value')))
        row = [first(inside, f'{name} member', role='AXCheckBox', desc=f'Include {name} in shared budget')
               for name in ('Claude', 'Cursor')]
        self.check('Includes Claude and Cursor, both on', all(n.get('value') in (1, '1') for n in row),
                   str([n.get('value') for n in row]))
        resets = labelled(inside, 'Resets', 'AXPopUpButton')
        self.check('Resets defaults to 1st', resets.get('value') == '1st', repr(resets.get('value')))
        self.settings_shot('settings-budget-on')

        nodes = self.ui.wait('SB bar', lambda: (n := self.ui.tree()) and dict(slots(n)).get('budget') is not None and n)
        shown = slots(nodes)
        values = dict(shown)
        detail = str(shown)
        self.check('SB bar ranks first by percent', shown[0][0] == 'budget', detail)
        nodes = self.open_popover()
        pop = within(nodes, popover(nodes))
        texts = [n.get('value', '') for n in pop if n.get('role') == 'AXStaticText']
        self.check('budget card first', next((t for t in texts if t in ('Shared budget', 'Claude', 'Cursor')
                                              or t.startswith(('Claude · ', 'Cursor · '))), '') == 'Shared budget')
        start = texts.index('Shared budget')
        card = texts[start:start + 12]
        total = next((m for x in card if (m := re.search(r'(\$[\d,]+\.\d\d) of (\$[\d,]+\.\d\d)', x))), None)
        self.check('budget total shown', total is not None, 'shown' if total else str(len(card)))
        rows = [amount_in(card, name) for name in ('Claude', 'Cursor')]
        self.check('one row per member', all(r is not None for r in rows), str([r is not None for r in rows]))
        spent, limit = money(total.group(1)), money(total.group(2))
        self.check('total equals the member rows', abs(spent - sum(rows)) < 0.005, f'{len(rows)} rows')
        if prefilled:
            self.check('amount equals the pre-filled field', abs(limit - money(amount['value'])) < 0.005)
        self.popover_shot('dropdown-budget-on')
        self.close_popover()
        window = self.settings()
        self.activate(window)

    def indicators(self):
        for count in (1, 3, 8, 2):
            window, inside = self.window_nodes()
            group = labelled(inside, 'Indicators', 'AXRadioGroup')
            buttons = [n for n in within(inside, group) if n.get('role') == 'AXRadioButton']
            self.ui.press(buttons[count - 1])
            nodes = self.ui.wait(f'{count} slots', lambda: (n := self.ui.tree()) and len(slots(n)) == count and n)
            shown = slots(nodes)
            known = [p for p, _ in shown if p]
            self.check(f'{count} indicator(s)', len(shown) == count and known == known[:3] and
                       all(p is None for p, _ in shown[len(known):]), str([p or '·' for p, _ in shown]))
            values = dict(shown)
            if count == 3 and self.prefilled:
                parts = [values.get(p) for p in ('budget', 'claude', 'cursor')]
                self.check('SB percent is the sum of member percents',
                           None not in parts and abs(parts[0] - parts[1] - parts[2]) < 0.03, str(shown))
            item = status_item(nodes)
            self.ui.shot(f'menubar-{count}', rect=[item['frame'][0] - 4, 0, item['frame'][2] + 8, 30])

    def codex(self):
        _, inside = self.window_nodes()
        heading = first(inside, 'Codex section', role='AXHeading', desc='Codex')
        group = next(n for n in inside if n['path'] == heading['path'].rsplit('.', 1)[0])
        return within(inside, group)

    def label_commit(self):
        before = profiles()
        add = next((n for n in self.codex() if n.get('role') == 'AXButton' and label(n) == 'Add another account'), None)
        if not add:
            raise GateFailure('Codex "Add another account" missing (remove extra Codex accounts before the gate)')
        self.ui.press(add)
        added = self.ui.wait('new account', lambda: len(profiles()) == len(before) + 1 and profiles())
        new = next(p for p in added if p['id'] not in {b['id'] for b in before})
        try:
            field = self.expand_others(new['label'])
            self.ui.focus(field)
            self.ui.keystroke('a', command=True)
            self.ui.keystroke('Gate label')
            time.sleep(0.5)
            inside = self.codex()
            choose = ending(inside, 'AXButton', f"Choose file for Codex {new['label']}")
            self.ui.click_node(choose)
            panel = self.ui.wait('open panel', lambda: next((n for n in self.ui.tree() if n.get('role') == 'AXWindow'
                                                             and n.get('subrole') == 'AXDialog'), None))
            stored = next(p['label'] for p in profiles() if p['id'] == new['id'])
            self.check('Choose… does not commit the draft label', stored == new['label'], repr(stored))
            self.ui.keycode(53)
            self.ui.wait('open panel to close', lambda: not any(n.get('subrole') == 'AXDialog' for n in self.ui.tree()))
            stored = next(p['label'] for p in profiles() if p['id'] == new['id'])
            self.check('cancelled panel leaves the label unchanged', stored == new['label'], repr(stored))
            inside = self.codex()
            field = ending(inside, 'AXTextField', f"Label for Codex {new['label']}")
            self.ui.focus(field)
            self.ui.keycode(36)
            committed = self.ui.wait('label commit', lambda: next((p['label'] for p in profiles() if p['id'] == new['id']
                                                                   and p['label'] == 'Gate label'), None), timeout=5)
            self.check('Return commits the label', committed == 'Gate label')
        finally:
            remove = next((n for n in self.codex() if n.get('role') == 'AXButton' and label(n).startswith('Remove ')), None)
            if remove:
                self.ui.press(remove)
            self.ui.wait('account removal', lambda: len(profiles()) == len(before), timeout=5)
        self.check('temporary account removed', len(profiles()) == len(before))

    def expand_others(self, account_label):
        def field():
            return next((n for n in self.codex() if n.get('role') == 'AXTextField'
                         and n.get('desc', '').endswith(f'Label for Codex {account_label}')), None)
        self.activate(self.settings())
        triangle = first(self.codex(), '"Other accounts" disclosure', role='AXDisclosureTriangle')
        attempts = [lambda: self.ui.press(triangle)] + [lambda dx=dx: self.ui.click_node(triangle, dx) for dx in (27, 12, 40)]
        for attempt in attempts:
            try:
                attempt()
            except GateFailure:
                pass
            time.sleep(0.8)
            if field():
                return field()

        raise GateFailure('"Other accounts" does not expand')

    def close_and_position(self):
        window = self.settings()
        self.activate(window)
        self.ui.keycode(53)
        self.check('Escape closes Settings', self.ui.wait('close', lambda: not settings_window(self.ui.tree()), timeout=5))
        window = self.open_settings()
        target = (window['frame'][0] + 37, window['frame'][1] + 23)
        self.ui.move(window, *target)
        time.sleep(0.5)
        close = first(within(self.ui.tree(), settings_window(self.ui.tree())), 'close button', subrole='AXCloseButton')
        self.ui.press(close)
        self.ui.wait('close', lambda: not settings_window(self.ui.tree()), timeout=5)
        window = self.open_settings()
        self.check('Settings reopens where it was left', abs(window['frame'][0] - target[0]) < 2 and
                   abs(window['frame'][1] - target[1]) < 2, f"{window['frame'][:2]} vs {list(target)}")
        self.activate(window)
        self.ui.keystroke('w', command=True)
        self.check('⌘W closes Settings', self.ui.wait('close', lambda: not settings_window(self.ui.tree()), timeout=5))


# MARK: - UI pass setup and teardown

def running_limitaur():
    out = sh('pgrep', '-x', 'Limitaur', check=False).stdout.split()
    found = []
    for pid in map(int, out):
        args = sh('ps', '-o', 'args=', '-p', str(pid), check=False).stdout.strip()
        found.append((pid, args))
    return found


def stop(pid, wait=10.0):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.2)
    os.kill(pid, signal.SIGKILL)


def ui_pass(record, out, helper_source):
    helper = out / 'uihelper'
    sh('swiftc', '-O', str(helper_source), '-o', str(helper), timeout=300)
    if sh(str(helper), 'trusted').stdout.strip() != 'true':
        raise GateFailure('the terminal needs Accessibility permission (System Settings → Privacy & Security)')
    app = out / 'Limitaur.app'
    env = dict(os.environ, LIMITAUR_SIGN_IDENTITY='-')
    with (out / 'logs' / 'bundle.log').open('w') as log:
        if subprocess.run(['sh', 'scripts/build-app.sh', str(app)], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT).returncode:
            raise GateFailure('bundle build failed; see logs/bundle.log')
    bundle_id = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
    if bundle_id != DOMAIN:
        raise GateFailure(f'unexpected bundle id {bundle_id}')

    previous = running_limitaur()
    backup = out / 'prefs-backup.plist'
    had_prefs = sh('defaults', 'export', DOMAIN, str(backup), check=False).returncode == 0
    stats = out / 'stats.json'
    record['stats'] = str(stats)
    child = None
    try:
        for pid, _ in previous:
            stop(pid)
        enabled = {(p.get('providerID') or {}).get('rawValue') for p in profiles() if p.get('enabled', True)}
        if not {'claude', 'cursor'} <= enabled:
            raise GateFailure('enable Claude and Cursor in Settings before running the gate')
        for key in RESET_KEYS:
            sh('defaults', 'delete', DOMAIN, key, check=False)
        sh('defaults', 'write', DOMAIN, 'indicatorCount', '-int', '2')
        stats.unlink(missing_ok=True)   # the app creates it exclusively
        child = subprocess.Popen([str(app / 'Contents/MacOS/Limitaur'), '--stats', str(stats)],
                                 stdout=(out / 'logs' / 'app.log').open('w'), stderr=subprocess.STDOUT)
        ui = UI(helper, child.pid, out / 'shots')
        ui.wait('status item', lambda: status_item(ui.tree()), timeout=30)
        UIPass(ui, record).run()
    finally:
        if child:
            stop(child.pid)
        if had_prefs:
            sh('defaults', 'import', DOMAIN, str(backup), check=False)
        else:
            sh('defaults', 'delete', DOMAIN, check=False)
        for _, args in previous:
            bundle = re.match(r'(.+?\.app)/Contents/MacOS/Limitaur$', args)
            if bundle:
                sh('open', bundle.group(1), check=False)
            else:
                record.setdefault('notes', []).append(f'not relaunched: {args}')


def notify(text):
    sh('osascript', '-e', f'display notification "{text}" with title "Limitaur release gate"', check=False)


def main():
    parser = argparse.ArgumentParser(description='Run the Limitaur release gate')
    parser.add_argument('--ui-only', action='store_true', help='skip the test steps (record is not complete)')
    args = parser.parse_args()
    revision = git('rev-parse', 'HEAD')
    dirty = bool(git('status', '--porcelain', '--untracked-files=normal'))
    out = ROOT / '.build' / 'release-gate' / revision
    shutil.rmtree(out, ignore_errors=True)
    for sub in ('logs', 'shots'):
        (out / sub).mkdir(parents=True, exist_ok=True)
    record = {'revision': revision, 'dirty': dirty, 'complete': not args.ui_only, 'passed': False,
              'started': datetime.datetime.now().astimezone().isoformat(timespec='seconds'), 'steps': []}
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(GateFailure('gate exceeded 45 minutes')))
    signal.alarm(45 * 60)
    ok = True
    try:
        binary = Path(sh('swift', 'build', '-c', 'release', '--show-bin-path', cwd=ROOT).stdout.strip()) / 'Limitaur'
        if not args.ui_only:
            for name, cmd, env, timeout in test_steps(binary):
                ok = run_step(record, out / 'logs', name, cmd, env, timeout) and ok
        print('UI pass (hands off the keyboard and mouse)', flush=True)
        try:
            ui_pass(record, out, ROOT / 'scripts/gate/uihelper.swift')
            record['steps'].append({'name': 'ui', 'ok': True})
        except Exception as failure:   # any error, not only a failed check, fails the gate
            ok = False
            record['steps'].append({'name': 'ui', 'ok': False, 'detail': f'{type(failure).__name__}: {failure}'})
            (out / 'logs' / 'ui-error.log').write_text(traceback.format_exc())
            print(f'FAIL  ui: {failure}', flush=True)
    except BaseException as failure:
        ok = False
        record['steps'].append({'name': 'gate', 'ok': False, 'detail': f'{type(failure).__name__}: {failure}'})
        raise
    finally:
        signal.alarm(0)
        record['passed'] = ok
        record['finished'] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
        (out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    verdict = 'PASSED' if ok else 'FAILED'
    notes = '' if record['complete'] and not dirty else ' (not valid for release: ' + \
        ', '.join(x for x, y in (('UI only', not record['complete']), ('dirty tree', dirty)) if y) + ')'
    print(f'{verdict}{notes}\n{out}')
    notify(f'{verdict}{notes}')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
