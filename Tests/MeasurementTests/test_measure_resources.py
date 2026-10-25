"""Offline standard-library checks for the macOS resource collector."""
import contextlib
import ctypes
import argparse
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'measure-resources.py'
SPEC = importlib.util.spec_from_file_location('measure_resources', SCRIPT)
measure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(measure)


class SyntheticRusageFunction:
    def __init__(self, result=0):
        self.result = result
        self.argtypes = None
        self.restype = None
        self.calls = []

    def __call__(self, pid, flavor, usage_pointer):
        self.calls.append((pid, flavor))
        usage_pointer.contents.ri_user_time = 1_000_000
        usage_pointer.contents.ri_system_time = 500_000
        usage_pointer.contents.ri_resident_size = 1024
        usage_pointer.contents.ri_proc_start_abstime = 1
        usage_pointer.contents.ri_runnable_time = 9_000_000
        return self.result


class SyntheticChildFunction:
    def __init__(self, children=None):
        self.children = children or {}
        self.argtypes = None
        self.restype = None

    def __call__(self, pid, buffer, size):
        values = self.children.get(pid, [])
        if len(values) * ctypes.sizeof(ctypes.c_int) > size:
            return -1
        address = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_int))
        for index, value in enumerate(values):
            address[index] = value
        return len(values)


class SyntheticLibrary:
    def __init__(self, function, children=None):
        self.proc_pid_rusage = function
        self.proc_listchildpids = children or SyntheticChildFunction()


class MeasurementTests(unittest.TestCase):
    def test_continuous_clock_uses_native_timebase_without_python_epoch(self):
        self.assertEqual(ctypes.sizeof(measure.MachTimebaseInfo), 8)
        with mock.patch.object(measure, 'native_continuous_clock',
                               return_value=(None, lambda: 600, 2, 3)):
            self.assertEqual(measure.continuous_nanoseconds(), 400)

    def test_sdk_v4_layout_and_typed_call(self):
        structure = measure.RUsageInfoV4
        self.assertEqual(ctypes.sizeof(structure), 296)
        self.assertEqual(len(structure._fields_), 36)
        self.assertEqual(structure.ri_user_time.offset, 16)
        self.assertEqual(structure.ri_system_time.offset, 24)
        self.assertEqual(structure.ri_child_user_time.offset, 96)
        self.assertEqual(structure.ri_runnable_time.offset, 288)

        function = SyntheticRusageFunction()
        configured = measure.configure_rusage(SyntheticLibrary(function))
        self.assertIs(configured, function)
        self.assertEqual(function.argtypes,
                         [ctypes.c_int, ctypes.c_int, ctypes.POINTER(structure)])
        self.assertIs(function.restype, ctypes.c_int)
        with mock.patch.object(measure, 'native_continuous_clock', return_value=(None, None, 1, 1)):
            self.assertAlmostEqual(measure.cpu_seconds(42, proc=function), 0.0015, places=9)
        self.assertEqual(function.calls, [(42, measure.RUSAGE_INFO_V4)])
        child_function = SyntheticChildFunction({42: [43]})
        configured_children = measure.configure_children(SyntheticLibrary(function, child_function))
        self.assertEqual(configured_children.argtypes, [ctypes.c_int, ctypes.c_void_p, ctypes.c_int])
        self.assertIs(configured_children.restype, ctypes.c_int)
        self.assertEqual(measure.child_pids(42, proc=configured_children), [43])

    def test_cpu_times_are_mach_ticks_scaled_by_timebase(self):
        with mock.patch.object(measure, 'native_continuous_clock', return_value=(None, None, 125, 3)):
            self.assertAlmostEqual(measure.cpu_seconds(42, proc=SyntheticRusageFunction()), 0.0625, places=9)

    def test_failed_or_invalid_rusage_is_not_a_zero_measurement(self):
        function = SyntheticRusageFunction(result=-1)
        with self.assertRaises(RuntimeError):
            measure.cpu_seconds(42, proc=function)
        with self.assertRaises(ValueError):
            measure.cpu_seconds(0, proc=function)
        self.assertEqual(function.calls, [(42, measure.RUSAGE_INFO_V4)])

    def test_live_descendants_are_aggregated(self):
        class Usage:
            def __init__(self):
                self.argtypes = None
                self.restype = None
            def __call__(self, pid, flavor, pointer):
                pointer.contents.ri_resident_size = {1: 100, 2: 50, 3: 25}[pid] * 1024
                pointer.contents.ri_user_time = {1: 1_000_000_000, 2: 250_000_000, 3: 125_000_000}[pid]
                pointer.contents.ri_proc_start_abstime = pid * 100
                return 0
        with mock.patch.object(measure, 'native_continuous_clock', return_value=(None, None, 1, 1)):
            rss, cpu, start, counters, children, incomplete = measure.sample(
                1, rusage_proc=Usage(), children_proc=SyntheticChildFunction({1: [2], 2: [3]}))
        self.assertEqual(rss, 175 * 1024)
        self.assertEqual(cpu, 1.0)
        self.assertEqual(start, 100)
        self.assertEqual(children, {(2, 200): 0.25, (3, 300): 0.125})
        self.assertFalse(incomplete)

    def test_incomplete_child_enumeration_cannot_qualify(self):
        full = SyntheticChildFunction({1: list(range(2, 258))})
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            measure.child_pids(1, proc=full)

    def test_interval_requires_sticky_state_proof_after_successes(self):
        base = {'eligible': 1, 'processID': 42, 'violations': 0, 'configurationChanges': 2,
                'sourceChanges': 0, 'profileDisables': 0, 'sleepEvents': 0,
                'credentialFailures': 0, 'credentialExpiries': 0, 'clockChanges': 0,
                'observedAtContinuousNanoseconds': 100,
                'validUntilContinuousNanoseconds': 1000,
                'validUntilWallMilliseconds': 5000}
        start = {'__eligibility': base, 'codex': {'success': 0}, 'claude': {'success': 0}}
        success = {'codex': {'success': 18}, 'claude': {'success': 18}}
        start_clock = (200, 4000)
        end_clock = (900, 4900)
        self.assertTrue(measure.qualifying_counters(start, {'__eligibility': dict(base), **success},
                                                    start_clock, end_clock, 42))
        for name in ('violations', 'configurationChanges', 'sourceChanges',
                     'profileDisables', 'sleepEvents', 'credentialFailures', 'credentialExpiries',
                     'clockChanges'):
            changed = dict(base)
            changed[name] += 1
            with self.subTest(name=name):
                self.assertFalse(measure.qualifying_counters(start, {'__eligibility': changed, **success},
                                                             start_clock, end_clock, 42))
        self.assertFalse(measure.qualifying_counters(start, {'__eligibility': {**base, 'eligible': 0}, **success},
                                                     start_clock, end_clock, 42))
        self.assertFalse(measure.qualifying_counters(start, {'__eligibility': dict(base),
                                                          'codex': {'success': 18, 'throttled': 1},
                                                          'claude': {'success': 18}}, start_clock, end_clock, 42))

    def test_statistics_process_id_must_match_both_measurement_boundaries(self):
        proof = {'eligible': 1, 'processID': 42, 'violations': 0,
                 'observedAtContinuousNanoseconds': 100,
                 'validUntilContinuousNanoseconds': 1000,
                 'validUntilWallMilliseconds': 5000}
        initial = {'__eligibility': dict(proof), 'codex': {'success': 0}, 'claude': {'success': 0}}
        final = {'__eligibility': dict(proof), 'codex': {'success': 18}, 'claude': {'success': 18}}
        start_clock, end_clock = (200, 4000), (900, 4900)
        self.assertTrue(measure.qualifying_counters(initial, final, start_clock, end_clock, 42))
        for boundary in ('initial', 'final'):
            for invalid in (999, None, 0, -1, True, '42'):
                with self.subTest(boundary=boundary, invalid=invalid):
                    before = {'__eligibility': dict(proof), 'codex': {'success': 0}, 'claude': {'success': 0}}
                    after = {'__eligibility': dict(proof), 'codex': {'success': 18}, 'claude': {'success': 18}}
                    target = before if boundary == 'initial' else after
                    if invalid is None:
                        target['__eligibility'].pop('processID')
                    else:
                        target['__eligibility']['processID'] = invalid
                    self.assertFalse(measure.eligible_interval(before, after, start_clock, end_clock, 42))
                    self.assertFalse(measure.qualifying_counters(before, after, start_clock, end_clock, 42))
        self.assertFalse(measure.qualifying_counters(initial, final, start_clock, end_clock, 999))
        self.assertFalse(measure.qualifying_counters(initial, final, start_clock, end_clock, True))

    def test_main_does_not_qualify_statistics_from_another_process(self):
        proof = {'eligible': 1, 'processID': 999, 'violations': 0,
                 'observedAtContinuousNanoseconds': 100,
                 'validUntilContinuousNanoseconds': 1000,
                 'validUntilWallMilliseconds': 5000}
        initial = {'__eligibility': dict(proof), 'codex': {'success': 0}, 'claude': {'success': 0}}
        final = {'__eligibility': dict(proof), 'codex': {'success': 18}, 'claude': {'success': 18}}
        sample = lambda cpu: (10 * 1024 * 1024, cpu, 123, (0, 0, 0), {}, False)
        output = io.StringIO()
        with contextlib.ExitStack() as patches, contextlib.redirect_stdout(output):
            patches.enter_context(mock.patch.object(measure, 'parse_args', return_value=argparse.Namespace(
                pid=42, warmup=60, seconds=600, stats='/synthetic-stats')))
            patches.enter_context(mock.patch.object(measure, 'sample', side_effect=[sample(1), sample(1), sample(1.1)]))
            patches.enter_context(mock.patch.object(measure, 'counters', side_effect=[initial, final]))
            patches.enter_context(mock.patch.object(measure, 'continuous_nanoseconds', side_effect=[200, 900]))
            patches.enter_context(mock.patch.object(measure.time, 'monotonic', side_effect=[0, 0, 0, 600, 600]))
            patches.enter_context(mock.patch.object(measure.time, 'time', side_effect=[4, 4.9]))
            patches.enter_context(mock.patch.object(measure.time, 'sleep', return_value=None))
            measure.main()
        result = json.loads(output.getvalue())
        self.assertEqual(result['refreshOutcomes']['codex']['success'], 18)
        self.assertEqual(result['refreshOutcomes']['claude']['success'], 18)
        self.assertFalse(result['defaultProfileStateEligible'])
        self.assertFalse(result['qualifying'])

    def test_last_record_expires_before_next_poll_despite_eighteen_successes(self):
        eligible = {'eligible': 1, 'processID': 42, 'violations': 0, 'clockChanges': 0,
                    'observedAtContinuousNanoseconds': 589_000_000_000,
                    'validUntilContinuousNanoseconds': 595_000_000_000,
                    'validUntilWallMilliseconds': 595_000}
        initial = {'__eligibility': eligible, 'codex': {'success': 0}, 'claude': {'success': 0}}
        final = {'__eligibility': eligible, 'codex': {'success': 18}, 'claude': {'success': 18}}
        start = (590_000_000_000, 590_000)
        self.assertFalse(measure.qualifying_counters(initial, final, start, (600_000_000_000, 600_000), 42))
        # A backwards wall adjustment cannot extend the bound from mach_continuous_time.
        self.assertFalse(measure.qualifying_counters(initial, final, start, (600_000_000_000, 590_000), 42))
        stale = dict(eligible)
        stale['validUntilContinuousNanoseconds'] = 590_000_000_000
        stale['validUntilWallMilliseconds'] = 0
        self.assertFalse(measure.qualifying_counters(
            {'__eligibility': stale, 'codex': {'success': 0}, 'claude': {'success': 0}},
            {'__eligibility': stale, 'codex': {'success': 18}, 'claude': {'success': 18}},
            (589_500_000_000, 589_500), (600_000_000_000, 600_000), 42))

    def test_transient_partial_json_retries_then_returns_valid_counters(self):
        payloads = iter(['{"codex":', '{"codex":{"success":2}}'])
        delays = []
        def opener(_path, encoding):
            self.assertEqual(encoding, 'utf-8')
            return io.StringIO(next(payloads))
        counts = measure.counters('/synthetic-stats', opener=opener,
                                  sleeper=delays.append, retry_delay=0.01)
        self.assertEqual(counts, {'codex': {'success': 2}})
        self.assertEqual(delays, [0.01])

    def test_persistent_invalid_json_or_metadata_fails_clearly(self):
        for payload in ('{"codex":', 'null', '{"codex":{"success":true}}'):
            delays = []
            with self.subTest(payload=payload), self.assertRaisesRegex(RuntimeError, 'aggregate statistics unavailable'):
                measure.counters('/synthetic-stats', attempts=3, retry_delay=0,
                                 sleeper=delays.append,
                                 opener=lambda _path, encoding: io.StringIO(payload))
            self.assertEqual(len(delays), 2)
        self.assertEqual(measure.counters(None), {})

    def test_bad_arguments_and_measurements_fail(self):
        for arguments in (['0'], ['-2'], ['1', '--warmup', '-1'], ['1', '--seconds', '0']):
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    measure.parse_args(arguments)
                self.assertEqual(caught.exception.code, 2)
        for values in ((1.0, 0.5, 10.0, [1024]), (0.0, 1.0, 0.0, [1024]),
                       (0.0, 1.0, 10.0, [])):
            with self.subTest(values=values), self.assertRaises(RuntimeError):
                measure.checked_cpu_delta(*values)
        with self.assertRaises(RuntimeError):
            measure.outcome_deltas({'codex': {'success': 2}}, {'codex': {'success': 1}})
        self.assertEqual(measure.outcome_deltas({'codex': {'success': 1}},
                                                {'codex': {'success': 3}}),
                         {'codex': {'success': 2}})


if __name__ == '__main__':
    unittest.main()
