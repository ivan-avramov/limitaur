#!/usr/bin/env python3
'''Adversarial black-box tests for compact bars (reviewer Phase A, candidate-blind).

Run: LIMITAUR_BIN=/path/to/Limitaur python3 -I -m unittest AdversarialBars/test_acceptance.py
Missing or unusable LIMITAUR_BIN FAILS every test (never skips). Offline, fabricated data only.
Class tags: [REQ-FIX] reproduces a required-fix failure, [INV] preserves an invariant,
[NEW] exercises new behavior.
Contract used: --rank-fixture PATH --now EPOCH [--count N] (count appended after --now);
fetchedAt/resetsAt are Unix seconds; providers claude/codex; --check-percent keys severity/fill.
'''
import json
import os
import subprocess
import tempfile
import unittest

NOW = 1800000000


def binary():
    path = os.environ.get('LIMITAUR_BIN')
    if not path:
        raise AssertionError('LIMITAUR_BIN not set: production binary required')
    if not (os.path.isfile(path) and os.access(path, os.X_OK)):
        raise AssertionError('LIMITAUR_BIN is not an executable file')
    return path


class Base(unittest.TestCase):
    def setUp(self):
        self.bin = binary()
        self._tmp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR') or None)
        self.addCleanup(self._tmp.cleanup)

    def run_cli(self, *args):
        return subprocess.run([self.bin] + [str(a) for a in args], capture_output=True,
                              text=True, timeout=30, stdin=subprocess.DEVNULL)

    def write(self, obj, name='f.json'):
        p = os.path.join(self._tmp.name, name)
        with open(p, 'w') as fh:
            json.dump(obj, fh)
        return p


def snap(provider, account, metrics, fetched=NOW - 5):
    out = []
    for (i, p, r) in metrics:
        m = {'id': i, 'label': i, 'usedPercent': p}
        if r is not None:
            m['resetsAt'] = r
        out.append(m)
    return {'providerID': provider, 'accountID': account, 'fetchedAt': fetched, 'metrics': out}


def many():
    # 10 distinct metrics, 10..100 percent, across two providers and accounts
    s1 = snap('codex', 'a', [('m%d' % i, 10 * i, None) for i in range(1, 6)])
    s2 = snap('claude', 'b', [('m%d' % i, 10 * i, None) for i in range(6, 11)])
    return [s1, s2]


class RankBase(Base):
    def rank(self, snaps, count=None, now=NOW):
        args = ['--rank-fixture', self.write(snaps), '--now', now]
        if count is not None:
            args += ['--count', count]
        r = self.run_cli(*args)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def keys(self, out):
        return [(m['providerID'], m['accountID'], m['id']) for m in out]


class CountBoundaries(RankBase):
    def test_default_is_three(self):
        '''[INV] no --count selects exactly 3, highest first.'''
        out = self.rank(many())
        self.assertEqual([m['usedPercent'] for m in out], [100, 90, 80])

    def test_counts_1_3_5_8_sizes_and_prefix_consistency(self):
        '''[NEW] each N returns N entries and is a prefix of the N=8 ordering.'''
        full = self.keys(self.rank(many(), 8))
        self.assertEqual(len(full), 8)
        for n in (1, 3, 5, 8):
            self.assertEqual(self.keys(self.rank(many(), n)), full[:n], n)

    def test_fewer_than_n_returns_all_without_padding(self):
        '''[NEW] two eligible metrics with --count 8 gives exactly two entries.'''
        out = self.rank([snap('codex', 'a', [('x', 5, None), ('y', 7, None)])], 8)
        self.assertEqual([m['id'] for m in out], ['y', 'x'])

    def test_zero_eligible_is_empty_array(self):
        '''[NEW] nothing eligible gives [] with exit 0.'''
        self.assertEqual(self.rank([snap('codex', 'a', [('x', None, None)])], 5), [])

    def test_invalid_counts_rejected_fixed_diagnostic_no_json(self):
        '''[NEW] invalid counts: exit 2, empty stdout, one identical non-echoing stderr.'''
        path = self.write(many())
        errs = set()
        for bad in ('0', '9', '-1', 'abc', '1.5', '', '99999999999999999999', '3x'):
            r = self.run_cli('--rank-fixture', path, '--now', NOW, '--count', bad)
            self.assertEqual(r.returncode, 2, repr(bad))
            self.assertEqual(r.stdout.strip(), '', repr(bad))
            errs.add(r.stderr)
        self.assertEqual(len(errs), 1, 'diagnostic must be fixed, not echo input')
        self.assertTrue(next(iter(errs)).strip())


class RankingSemantics(RankBase):
    def test_tie_break_lexical_across_accounts_and_providers(self):
        '''[INV] equal percent ordered by providerID, accountID, metricID.'''
        snaps = [snap('codex', 'b', [('z', 50, None), ('a', 50, None)]),
                 snap('codex', 'a', [('m', 50, None)]),
                 snap('claude', 'z', [('q', 50, None)])]
        self.assertEqual(self.keys(self.rank(snaps, 8)),
                         [('claude', 'z', 'q'), ('codex', 'a', 'm'),
                          ('codex', 'b', 'a'), ('codex', 'b', 'z')])

    def test_stale_boundary_and_fresh_fill(self):
        '''[INV] age 89 included, 90 and 500 excluded; stale high values do not block fill.'''
        fresh = snap('codex', 'a', [('f', 10, None)], fetched=NOW - 89)
        edge = snap('codex', 'b', [('e', 99, None)], fetched=NOW - 90)
        old = snap('codex', 'c', [('o', 98, None)], fetched=NOW - 500)
        self.assertEqual(self.keys(self.rank([fresh, edge, old], 8)), [('codex', 'a', 'f')])
        snaps = [snap('codex', 'a', [('h1', 99, None), ('h2', 98, None)], fetched=NOW - 120),
                 snap('claude', 'b', [('l%d' % i, i, None) for i in range(1, 6)])]
        self.assertEqual([m['usedPercent'] for m in self.rank(snaps, 3)], [5, 4, 3])

    def test_reset_equality_excludes_only_that_metric(self):
        '''[INV] resetsAt<=now excluded; now+1 and absent kept; siblings in same snapshot kept.'''
        s = snap('claude', 'a', [('due', 90, NOW), ('past', 91, NOW - 1),
                                 ('soon', 50, NOW + 1), ('none', 40, None)])
        self.assertEqual([m['id'] for m in self.rank([s], 8)], ['soon', 'none'])

    def test_over_100_ranks_first_and_is_raw(self):
        '''[INV] values over 100 keep raw percent and outrank 100.'''
        out = self.rank([snap('codex', 'a', [('a', 100, None), ('b', 250.5, None)])], 2)
        self.assertEqual([m['id'] for m in out], ['b', 'a'])
        self.assertEqual(out[0]['usedPercent'], 250.5)

    def test_unknown_values_excluded_known_zero_kept(self):
        '''[INV] null/missing/negative/string percent never selected nor treated as 0.'''
        s = {'providerID': 'codex', 'accountID': 'a', 'fetchedAt': NOW - 1, 'metrics': [
            {'id': 'null', 'label': 'n', 'usedPercent': None},
            {'id': 'missing', 'label': 'm'},
            {'id': 'neg', 'label': 'g', 'usedPercent': -1},
            {'id': 'str', 'label': 's', 'usedPercent': '50'},
            {'id': 'zero', 'label': 'z', 'usedPercent': 0}]}
        out = self.rank([s], 8)
        self.assertEqual([m['id'] for m in out], ['zero'])
        self.assertEqual(out[0]['usedPercent'], 0)

    def test_identity_duplicates_collapse_distinct_accounts_kept(self):
        '''[INV] exact duplicate identity once; same metric id on distinct accounts both kept;
        several metrics from one account allowed; output has the four documented fields.'''
        s = snap('codex', 'a', [('w', 70, None), ('w', 70, None), ('v', 60, None)])
        self.assertEqual(self.keys(self.rank([s], 8)), [('codex', 'a', 'w'), ('codex', 'a', 'v')])
        two = [snap('codex', 'a', [('w', 70, None)]), snap('codex', 'b', [('w', 70, None)])]
        out = self.rank(two, 8)
        self.assertEqual(len(out), 2)
        for k in ('providerID', 'accountID', 'id', 'usedPercent'):
            self.assertIn(k, out[0])


class InspectBase(Base):
    def inspect(self, provider, payload):
        r = self.run_cli('--inspect-fixture', provider, self.write(payload))
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    @staticmethod
    def row(kind='session', pct=42):
        return {'kind': kind, 'group': kind, 'percent': pct, 'resets_at': None}

    @staticmethod
    def pcts(out):
        return sorted(m['usedPercent'] for m in out['metrics']
                      if m.get('usedPercent') is not None)

    def assertIncomplete(self, out):
        self.assertTrue(out.get('partial') is True or out.get('warnings'),
                        'enabled invalid/missing usage must be explicit partial/unknown')


MONEY = {'amount_minor': 1234, 'currency': 'USD', 'exponent': 2}


class SpendSemantics(InspectBase):
    def test_modern_enabled_spend_invalid_percent_is_partial(self):
        '''[REQ-FIX] enabled spend with invalid percent: incomplete, healthy quota row kept.'''
        for bad in ('abc', -5, True):
            out = self.inspect('claude', {'limits': [self.row()],
                                          'spend': {'enabled': True, 'used': MONEY, 'percent': bad}})
            self.assertIncomplete(out)
            self.assertEqual(self.pcts(out), [42])

    def test_legacy_enabled_extra_usage_invalid_utilization_is_partial(self):
        '''[REQ-FIX] enabled legacy extra_usage with invalid utilization: incomplete.'''
        for bad in ('abc', -1, [1]):
            out = self.inspect('claude', {'five_hour': {'utilization': 10, 'resets_at': None},
                                          'extra_usage': {'is_enabled': True, 'utilization': bad}})
            self.assertIncomplete(out)
            self.assertEqual(self.pcts(out), [10])

    def test_enabled_missing_percent_not_healthy_zero(self):
        '''[REQ-FIX] enabled spend/extra_usage with absent percent: unavailable, no synthesized 0.'''
        for payload in ({'limits': [self.row()], 'spend': {'enabled': True}},
                        {'five_hour': {'utilization': 42, 'resets_at': None},
                         'extra_usage': {'is_enabled': True}}):
            out = self.inspect('claude', payload)
            self.assertEqual(self.pcts(out), [42])
            self.assertNotIn(0, [m.get('usedPercent') for m in out['metrics']])
            self.assertIncomplete(out)

    def test_empty_modern_limits_does_not_hide_malformed_enabled_spend(self):
        '''[REQ-FIX] empty limits is authoritative for quota only, not for spend diagnostics.'''
        out = self.inspect('claude', {'limits': [],
                                      'spend': {'enabled': True, 'used': MONEY, 'percent': 'bad'}})
        self.assertEqual(out['metrics'], [])
        self.assertIncomplete(out)

    def test_disabled_spend_stays_healthy_without_metric(self):
        '''[INV] observed disabled spend with zero used: not partial, no invented metric.'''
        out = self.inspect('claude', {'limits': [self.row()],
                                      'spend': {'enabled': False,
                                                'used': {'amount_minor': 0, 'currency': 'USD',
                                                         'exponent': 2}}})
        self.assertIs(out['partial'], False)
        self.assertEqual(self.pcts(out), [42])
        self.assertEqual(len(out['metrics']), 1)

    def test_valid_amounts_and_percents_invent_no_currency_or_zero(self):
        '''[NEW] valid extra_usage percent with null units shows percent and no currency;
        valid amount-only spend adds no fake percent metric and no foreign currency.'''
        out = self.inspect('claude', {'five_hour': {'utilization': 10, 'resets_at': None},
                                      'extra_usage': {'is_enabled': True, 'utilization': 50,
                                                      'currency': None, 'decimal_places': None,
                                                      'monthly_limit': None,
                                                      'used_credits': None}})
        self.assertIn(50, self.pcts(out))
        for b in out.get('balances', []) + out.get('informationalAmounts', []):
            self.assertIn(b.get('currency'), (None, ''))
        out = self.inspect('claude', {'limits': [self.row()],
                                      'spend': {'enabled': True, 'used': MONEY}})
        self.assertEqual(self.pcts(out), [42])
        self.assertEqual(len(out['metrics']), 1)
        text = json.dumps(out)
        for cur in ('EUR', 'GBP', 'JPY'):
            self.assertNotIn(cur, text)


class PercentCheck(Base):
    def check(self, v):
        r = self.run_cli('--check-percent', v)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_threshold_edges_and_fill_clamp(self):
        '''[INV] 80/80.01 and 95/95.01 differ; over-100 fill equals 100 fill.'''
        c = {v: self.check(v) for v in ('0', '80', '80.01', '95', '95.01', '100', '150')}
        self.assertEqual(c['80']['severity'], c['0']['severity'])
        self.assertNotEqual(c['80']['severity'], c['80.01']['severity'])
        self.assertEqual(c['95']['severity'], c['80.01']['severity'])
        self.assertNotEqual(c['95']['severity'], c['95.01']['severity'])
        self.assertEqual(c['150']['severity'], c['95.01']['severity'])
        self.assertEqual(c['150']['fill'], c['100']['fill'])


if __name__ == '__main__':
    unittest.main()
