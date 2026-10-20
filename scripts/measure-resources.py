#!/usr/bin/env python3
"""Sample an already running Limitaur process without reading its data or credentials."""
import argparse
import ctypes
import functools
import json
import math
import statistics
import time


class RUsageInfoV4(ctypes.Structure):
    _fields_ = [
        ('ri_uuid', ctypes.c_uint8 * 16),
        ('ri_user_time', ctypes.c_uint64),
        ('ri_system_time', ctypes.c_uint64),
        ('ri_pkg_idle_wkups', ctypes.c_uint64),
        ('ri_interrupt_wkups', ctypes.c_uint64),
        ('ri_pageins', ctypes.c_uint64),
        ('ri_wired_size', ctypes.c_uint64),
        ('ri_resident_size', ctypes.c_uint64),
        ('ri_phys_footprint', ctypes.c_uint64),
        ('ri_proc_start_abstime', ctypes.c_uint64),
        ('ri_proc_exit_abstime', ctypes.c_uint64),
        ('ri_child_user_time', ctypes.c_uint64),
        ('ri_child_system_time', ctypes.c_uint64),
        ('ri_child_pkg_idle_wkups', ctypes.c_uint64),
        ('ri_child_interrupt_wkups', ctypes.c_uint64),
        ('ri_child_pageins', ctypes.c_uint64),
        ('ri_child_elapsed_abstime', ctypes.c_uint64),
        ('ri_diskio_bytesread', ctypes.c_uint64),
        ('ri_diskio_byteswritten', ctypes.c_uint64),
        ('ri_cpu_time_qos_default', ctypes.c_uint64),
        ('ri_cpu_time_qos_maintenance', ctypes.c_uint64),
        ('ri_cpu_time_qos_background', ctypes.c_uint64),
        ('ri_cpu_time_qos_utility', ctypes.c_uint64),
        ('ri_cpu_time_qos_legacy', ctypes.c_uint64),
        ('ri_cpu_time_qos_user_initiated', ctypes.c_uint64),
        ('ri_cpu_time_qos_user_interactive', ctypes.c_uint64),
        ('ri_billed_system_time', ctypes.c_uint64),
        ('ri_serviced_system_time', ctypes.c_uint64),
        ('ri_logical_writes', ctypes.c_uint64),
        ('ri_lifetime_max_phys_footprint', ctypes.c_uint64),
        ('ri_instructions', ctypes.c_uint64),
        ('ri_cycles', ctypes.c_uint64),
        ('ri_billed_energy', ctypes.c_uint64),
        ('ri_serviced_energy', ctypes.c_uint64),
        ('ri_interval_max_phys_footprint', ctypes.c_uint64),
        ('ri_runnable_time', ctypes.c_uint64),
    ]


RUSAGE_INFO_V4 = 4
MAX_CHILDREN = 256
if ctypes.sizeof(RUsageInfoV4) != 296:
    raise RuntimeError('unsupported rusage_info_v4 layout')


class MachTimebaseInfo(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]


@functools.lru_cache(maxsize=1)
def native_continuous_clock():
    library = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    ticks = library.mach_continuous_time
    ticks.argtypes = []
    ticks.restype = ctypes.c_uint64
    timebase = library.mach_timebase_info
    timebase.argtypes = [ctypes.POINTER(MachTimebaseInfo)]
    timebase.restype = ctypes.c_int
    info = MachTimebaseInfo()
    if timebase(ctypes.byref(info)) != 0 or not info.denom:
        raise RuntimeError('continuous clock unavailable')
    return library, ticks, info.numer, info.denom


def continuous_nanoseconds():
    _, ticks, numer, denom = native_continuous_clock()
    return ticks() * numer // denom


def configure_rusage(library):
    function = library.proc_pid_rusage
    function.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(RUsageInfoV4)]
    function.restype = ctypes.c_int
    return function


def configure_children(library):
    function = library.proc_listchildpids
    function.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
    function.restype = ctypes.c_int
    return function


@functools.lru_cache(maxsize=1)
def native_rusage():
    library = ctypes.CDLL('/usr/lib/libproc.dylib')
    return library, configure_rusage(library), configure_children(library)


def child_pids(pid, proc=None):
    if pid <= 0:
        raise ValueError('pid must be positive')
    if proc is None:
        _, _, proc = native_rusage()
    buffer = (ctypes.c_int * MAX_CHILDREN)()
    count = proc(pid, ctypes.cast(buffer, ctypes.c_void_p), ctypes.sizeof(buffer))
    if count < 0 or count >= MAX_CHILDREN:
        raise RuntimeError('child enumeration incomplete')
    ids = [int(buffer[index]) for index in range(count)]
    if any(child <= 0 or child == pid for child in ids) or len(ids) != len(set(ids)):
        raise RuntimeError('invalid child enumeration')
    return ids


def process_usage(pid, proc=None):
    if pid <= 0:
        raise ValueError('pid must be positive')
    if proc is None:
        _, proc, _ = native_rusage()
    usage = RUsageInfoV4()
    if proc(pid, RUSAGE_INFO_V4, ctypes.pointer(usage)) != 0:
        raise RuntimeError('process accounting unavailable')
    if not usage.ri_proc_start_abstime or not usage.ri_resident_size:
        raise RuntimeError('incomplete process accounting')
    return usage


def cpu_seconds(pid, proc=None):
    usage = process_usage(pid, proc)
    return (usage.ri_user_time + usage.ri_system_time) / 1_000_000_000


def sample(root, *, rusage_proc=None, children_proc=None):
    if rusage_proc is None or children_proc is None:
        _, native_usage, native_children = native_rusage()
        rusage_proc = rusage_proc or native_usage
        children_proc = children_proc or native_children
    first = process_usage(root, rusage_proc)
    rss = first.ri_resident_size
    children = {}
    seen = {root}
    pending = [root]
    incomplete = False
    while pending:
        parent = pending.pop()
        try:
            ids = child_pids(parent, children_proc)
        except RuntimeError:
            incomplete = True
            continue
        for pid in ids:
            if pid in seen or len(seen) >= MAX_CHILDREN:
                incomplete = True
                continue
            seen.add(pid)
            try:
                usage = process_usage(pid, rusage_proc)
            except RuntimeError:
                incomplete = True
                continue
            identity = (pid, usage.ri_proc_start_abstime)
            children[identity] = (usage.ri_user_time + usage.ri_system_time) / 1_000_000_000
            rss += usage.ri_resident_size
            pending.append(pid)
    last = process_usage(root, rusage_proc)
    if first.ri_proc_start_abstime != last.ri_proc_start_abstime:
        raise RuntimeError('Limitaur process identity changed')
    root_cpu = (last.ri_user_time + last.ri_system_time) / 1_000_000_000
    child_counters = (last.ri_child_user_time, last.ri_child_system_time,
                      last.ri_child_elapsed_abstime)
    return rss, root_cpu, last.ri_proc_start_abstime, child_counters, children, incomplete


def validate_counters(value):
    if not isinstance(value, dict):
        raise ValueError('invalid aggregate statistics')
    for provider, outcomes in value.items():
        if not isinstance(provider, str) or not isinstance(outcomes, dict):
            raise ValueError('invalid aggregate statistics')
        for name, count in outcomes.items():
            if not isinstance(name, str) or type(count) is not int or count < 0:
                raise ValueError('invalid aggregate statistics')
    return value


def counters(path, *, attempts=3, retry_delay=0.01, sleeper=time.sleep, opener=open):
    if not path:
        return {}
    if attempts < 1 or retry_delay < 0:
        raise ValueError('invalid statistics read policy')
    for attempt in range(attempts):
        try:
            with opener(path, encoding='utf-8') as source:
                return validate_counters(json.load(source))
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
            if attempt + 1 == attempts:
                raise RuntimeError('aggregate statistics unavailable') from None
            sleeper(retry_delay)


def outcome_deltas(initial, final):
    outcomes = {}
    for provider in initial.keys() | final.keys():
        before = initial.get(provider, {})
        after = final.get(provider, {})
        differences = {}
        for name in before.keys() | after.keys():
            difference = after.get(name, 0) - before.get(name, 0)
            if difference < 0:
                raise RuntimeError('aggregate statistics counters decreased')
            differences[name] = difference
        outcomes[provider] = differences
    return outcomes


def proof_current(status, continuous_now, wall_now_ms, expected_pid):
    if (type(expected_pid) is not int or expected_pid <= 0 or
            type(status.get('processID')) is not int or
            status['processID'] != expected_pid or status.get('eligible') != 1):
        return False
    observed = status.get('observedAtContinuousNanoseconds', 0)
    deadline = status.get('validUntilContinuousNanoseconds', 0)
    wall_deadline = status.get('validUntilWallMilliseconds', 0)
    return (observed > 0 and observed <= continuous_now < deadline and
            (wall_deadline == 0 or wall_now_ms < wall_deadline))


def eligible_interval(initial, final, start_clock, end_clock, expected_pid):
    before = initial.get('__eligibility')
    after = final.get('__eligibility')
    if not isinstance(before, dict) or not isinstance(after, dict):
        return False
    if (not proof_current(before, *start_clock, expected_pid) or
            not proof_current(after, *end_clock, expected_pid)):
        return False
    keys = ('violations', 'configurationChanges', 'sourceChanges', 'profileDisables',
            'sleepEvents', 'credentialFailures', 'credentialExpiries', 'clockChanges')
    return all(after.get(key, 0) == before.get(key, 0) for key in keys)


def qualifying_counters(initial, final, start_clock, end_clock, expected_pid):
    if not eligible_interval(initial, final, start_clock, end_clock, expected_pid):
        return False
    outcomes = outcome_deltas({key: value for key, value in initial.items() if key != '__eligibility'},
                              {key: value for key, value in final.items() if key != '__eligibility'})
    return all(outcomes.get(provider, {}).get('success', 0) >= 18 and
               sum(count for name, count in outcomes.get(provider, {}).items() if name != 'success') == 0
               for provider in ('codex', 'claude'))


def checked_cpu_delta(initial_cpu, final_cpu, elapsed, rss):
    delta = final_cpu - initial_cpu
    if (not rss or any(value <= 0 for value in rss) or elapsed <= 0 or
            not all(math.isfinite(value) for value in (initial_cpu, final_cpu, elapsed, delta)) or
            delta < 0):
        raise RuntimeError('invalid resource measurement')
    return delta


def parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('pid', type=int)
    parser.add_argument('--warmup', type=int, default=60)
    parser.add_argument('--seconds', type=int, default=600)
    parser.add_argument('--stats', help='sanitized aggregate stats file from Limitaur --stats')
    args = parser.parse_args(argv)
    if args.pid <= 0 or args.warmup < 0 or args.seconds <= 0:
        parser.error('pid must be positive, warmup nonnegative, and seconds positive')
    return args


def main():
    args = parse_args()
    time.sleep(args.warmup)
    start = time.monotonic()
    first = sample(args.pid)
    initial_counts = counters(args.stats)
    start_clock = (continuous_nanoseconds(), int(time.time() * 1000))
    rss = []
    observed_children = set(first[4])
    child_cpu = dict(first[4])
    child_cpu_delta = 0.0
    last_children = set(first[4])
    missing_child = first[5]
    child_counter_change = False
    while time.monotonic() - start < args.seconds:
        current = sample(args.pid)
        if current[2] != first[2]:
            raise RuntimeError('Limitaur process identity changed')
        rss.append(current[0])
        current_ids = set(current[4])
        missing_child |= current[5] or bool(last_children - current_ids)
        child_counter_change |= current[3] != first[3]
        for identity, cpu in current[4].items():
            child_cpu_delta += max(0, cpu - child_cpu[identity]) if identity in child_cpu else cpu
            child_cpu[identity] = cpu
        observed_children |= current_ids
        last_children = current_ids
        time.sleep(min(2, max(0, args.seconds - (time.monotonic() - start))))
    elapsed = time.monotonic() - start
    final = sample(args.pid)
    if final[2] != first[2]:
        raise RuntimeError('Limitaur process identity changed')
    final_counts = counters(args.stats)
    end_clock = (continuous_nanoseconds(), int(time.time() * 1000))
    missing_child |= final[5] or bool(last_children - set(final[4]))
    child_counter_change |= final[3] != first[3]
    observed_children |= set(final[4])
    for identity, cpu in final[4].items():
        child_cpu_delta += max(0, cpu - child_cpu[identity]) if identity in child_cpu else cpu
    mib = 1024 * 1024
    cpu_delta = checked_cpu_delta(first[1], final[1], elapsed, rss) + child_cpu_delta
    outcomes = outcome_deltas({key: value for key, value in initial_counts.items() if key != '__eligibility'},
                              {key: value for key, value in final_counts.items() if key != '__eligibility'})
    good_fetches = qualifying_counters(initial_counts, final_counts, start_clock, end_clock, args.pid)
    state_eligible = bool(args.stats) and eligible_interval(initial_counts, final_counts, start_clock, end_clock, args.pid)
    qualifying = (args.warmup >= 60 and args.seconds >= 600 and state_eligible and
                  not observed_children and not missing_child and not child_counter_change and good_fetches)
    result = {
        'classification': 'qualifying workload' if qualifying else 'smoke or nonqualifying workload',
        'warmupSeconds': args.warmup, 'measuredSeconds': elapsed, 'sampleIntervalSeconds': 2,
        'maxRSSMiB': max(rss) / mib, 'meanRSSMiB': statistics.mean(rss) / mib,
        'medianRSSMiB': statistics.median(rss) / mib,
        'cpuSeconds': cpu_delta,
        'cpuPercentOneCore': 100 * cpu_delta / elapsed,
        'rssTargetMet': max(rss) / mib < 50,
        'cpuTargetMet': 100 * cpu_delta / elapsed < 0.1,
        'descendantCountObserved': len(observed_children),
        'unaccountedExitedChild': missing_child or child_counter_change,
        'refreshOutcomes': outcomes,
        'defaultProfileStateEligible': state_eligible,
        'qualifying': qualifying,
        'samplingLimit': 'RSS peaks and children born and exited between samples may be missed',
    }
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
