"""Phase A black-box adversarial tests for Limitaur (candidate-blind).

Uses only the documented diagnostic surface: --check-percent, --inspect-fixture,
--rank-fixture. Binary: $LIMITAUR_BIN, else .build/release/Limitaur under the repo root.
If the binary is absent every test FAILS (never skips/passes): absence is a truthful
"cannot run" result. All fixture values are invented. No network, no credentials.

Run: python3 -I AdversarialClaude/test_acceptance.py
"""
import json
import os
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.environ.get("LIMITAUR_BIN") or os.path.join(ROOT, ".build", "release", "Limitaur")
NOW = 1792368000 + 36000  # 2026-10-19T10:00:00Z (invented clock)


def run(*args):
    if not (os.path.isfile(BIN) and os.access(BIN, os.X_OK)):
        raise AssertionError("Limitaur binary not available at configured path; cannot execute")
    env = {"PATH": "/usr/bin:/bin", "HOME": tempfile.gettempdir()}  # no credentials in env
    return subprocess.run([BIN, *args], capture_output=True, text=True, timeout=30, env=env)


def fixture(data):
    d = tempfile.mkdtemp(prefix="lmt-adv-")
    p = os.path.join(d, "f.json")
    with open(p, "w") as f:
        f.write(data if isinstance(data, str) else json.dumps(data))
    return p


def inspect(provider, data):
    return run("--inspect-fixture", provider, fixture(data))


def ok(provider, data):
    r = inspect(provider, data)
    assert r.returncode == 0, "expected success, rc=%s" % r.returncode
    return json.loads(r.stdout)


def rejected(tc, r):
    tc.assertNotEqual(r.returncode, 0)
    tc.assertEqual(r.stdout.strip(), "", "no snapshot may be emitted on schema failure")


class Percent(unittest.TestCase):
    # Class: preserves invariant (thresholds are strict: >80, >95)
    def test_01_threshold_boundaries(self):
        cases = [("0", "normal"), ("80", "normal"), ("80.01", "warning"), ("95", "warning"),
                 ("95.01", "critical"), ("100", "critical"), ("250", "critical")]
        for v, sev in cases:
            j = json.loads(run("--check-percent", v).stdout)
            self.assertEqual(j["severity"], sev, v)
        self.assertAlmostEqual(json.loads(run("--check-percent", "80").stdout)["fill"], 0.8)
        self.assertEqual(json.loads(run("--check-percent", "250").stdout)["fill"], 1)  # clamp ring only

    # Class: preserves invariant (invalid is unknown, never 0)
    def test_02_invalid_is_unknown_not_zero(self):
        for v in ["-1", "-0.01", "nan", "inf", "-inf", "abc", ""]:
            r = run("--check-percent", v)
            j = json.loads(r.stdout)
            self.assertEqual(j["severity"], "unknown", v)
            self.assertIsNone(j["fill"], v)


class Codex(unittest.TestCase):
    # Class: exercises new behavior (window identity from duration, not primary/secondary)
    def test_03_windows_and_reset_units(self):
        j = ok("codex", {"rate_limit": {
            "primary_window": {"used_percent": 12.5, "limit_window_seconds": 604800, "reset_at": NOW + 1000},
            "secondary_window": {"used_percent": 81, "limit_window_seconds": 18000, "reset_at": NOW + 2000}}})
        self.assertEqual(j["providerID"], "codex")
        m = j["metrics"]
        self.assertEqual(len(m), 2)
        self.assertEqual(len({x["id"] for x in m}), 2)
        by = {x["usedPercent"]: x for x in m}
        self.assertEqual(by[12.5]["resetsAt"], NOW + 1000)  # seconds, not ms
        self.assertEqual(by[81]["resetsAt"], NOW + 2000)
        # a 7-day primary must not be labelled as a 5-hour window and vice versa
        self.assertNotEqual(by[12.5]["label"], by[81]["label"])

    # Class: preserves invariant (envelope validity)
    def test_04_invalid_envelopes_rejected(self):
        for bad in [{}, {"unknown_future": {"a": 1}}, {"rate_limit": "oops"},
                    {"credits": [1]}, {"rate_limit_reset_credits": 5}, "[]", "not json"]:
            rejected(self, inspect("codex", bad))

    # Class: exercises new behavior (malformed row -> partial, never 0)
    def test_05_negative_percent_is_not_zero_and_partial(self):
        j = ok("codex", {"rate_limit": {
            "primary_window": {"used_percent": 40, "limit_window_seconds": 18000, "reset_at": NOW + 5},
            "secondary_window": {"used_percent": -5, "limit_window_seconds": 604800, "reset_at": NOW + 9}}})
        self.assertIn(40, [x["usedPercent"] for x in j["metrics"]])
        for x in j["metrics"]:
            if x["usedPercent"] is not None:
                self.assertGreaterEqual(x["usedPercent"], 0)
            self.assertNotEqual(x["usedPercent"], 0 if x["resetsAt"] == NOW + 9 else -1)
        self.assertTrue(j["partial"])
        self.assertTrue(j["warnings"])

    # Class: exercises new behavior (count-only != empty; credits opaque units)
    def test_06_count_only_resets_and_opaque_credits(self):
        j = ok("codex", {"credits": {"has_credits": True, "unlimited": False, "balance": "12.50"},
                         "rate_limit_reset_credits": {"available_count": 3, "applicable_available_count": 2}})
        rc = j["resetCredits"]
        self.assertEqual(rc["availableCount"], 3)
        self.assertEqual(rc["applicableCount"], 2)
        self.assertIsNone(rc["details"])  # not []
        b = j["balances"][0]
        self.assertEqual(float(b["remaining"]), 12.5)
        self.assertIsNone(b["currency"])  # never infer USD
        self.assertFalse(b["unlimited"])
        self.assertIsNone(b["expiresAt"])  # never infer expiry


class Claude(unittest.TestCase):
    MODERN = [
        {"kind": "session", "group": "session", "percent": 100, "resets_at": "2026-10-19T12:00:00.500+02:00", "is_active": True},
        {"kind": "weekly_all", "group": "weekly", "percent": 30, "resets_at": "2026-10-25T10:00:00Z", "is_active": False},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 55, "resets_at": None, "is_active": False,
         "scope": {"model": {"id": "m-x", "display_name": "Fable"}}},
    ]

    # Class: exercises new behavior (is_active advisory, no double count, offset/fraction parse)
    def test_07_modern_inactive_fable_no_double_count(self):
        data = {"limits": self.MODERN, "five_hour": {"utilization": 77, "resets_at": None},
                "seven_day": {"utilization": 66, "resets_at": None}}
        j = ok("claude", data)
        m = j["metrics"]
        self.assertEqual(len(m), 3, "legacy objects must not be added to a modern list")
        self.assertEqual(sorted(x["usedPercent"] for x in m), [30, 55, 100])
        fable = [x for x in m if x["usedPercent"] == 55][0]
        self.assertIn("Fable", fable["label"])
        self.assertIsNone(fable["resetsAt"])
        sess = [x for x in m if x["usedPercent"] == 100][0]
        self.assertAlmostEqual(sess["resetsAt"], NOW + 0.5, delta=1.0)  # 12:00+02:00 == 10:00Z

    # Class: exercises new behavior (empty list authoritative; null permits fallback)
    def test_08_empty_authoritative_vs_null_fallback(self):
        j = ok("claude", {"limits": [], "five_hour": {"utilization": 77, "resets_at": None}})
        self.assertEqual(j["metrics"], [])
        j = ok("claude", {"limits": None, "five_hour": {"utilization": 42, "resets_at": None},
                          "seven_day": None})
        self.assertEqual([x["usedPercent"] for x in j["metrics"]], [42])

    # Class: preserves invariant (never fall back around malformed authoritative container)
    def test_09_wrong_type_limits_no_fallback(self):
        rejected(self, inspect("claude", {"limits": "x", "five_hour": {"utilization": 42, "resets_at": None}}))
        rejected(self, inspect("claude", {}))
        rejected(self, inspect("claude", {"future_only": {"a": 1}}))

    # Class: exercises new behavior (partial vs all-malformed)
    def test_10_mixed_malformed_rows_partial_all_malformed_fail(self):
        good = self.MODERN[1]
        j = ok("claude", {"limits": [good, {"kind": "x", "percent": "NaN"}, 7]})
        self.assertEqual(len(j["metrics"]), 1)
        self.assertTrue(j["partial"])
        self.assertTrue(j["warnings"])
        rejected(self, inspect("claude", {"limits": [{"kind": "x", "percent": -3}, "junk"]}))


class Rank(unittest.TestCase):
    def rank(self, snaps, now=NOW):
        r = run("--rank-fixture", fixture(snaps), "--now", str(now))
        self.assertEqual(r.returncode, 0)
        return json.loads(r.stdout)

    @staticmethod
    def snap(p, a, metrics, age=0):
        return {"providerID": p, "accountID": a, "fetchedAt": NOW - age, "metrics": metrics}

    @staticmethod
    def met(i, pct, reset=None):
        return {"id": i, "label": i, "usedPercent": pct, "resetsAt": reset}

    # Class: preserves invariant (top-3 ordering, lexical tie-break, unknown excluded, multi per provider)
    def test_11_top_three_ties_and_unknown(self):
        out = self.rank([
            self.snap("codex", "c1", [self.met("x", 90), self.met("y", 10), self.met("z", 95)]),
            self.snap("claude", "a1", [self.met("m1", 50), self.met("m2", 90)]),
            self.snap("claude", "a2", [self.met("bad", -3), self.met("nul", None), self.met("str", "9")]),
        ])
        self.assertEqual([(o["providerID"], o["accountID"], o["id"]) for o in out],
                         [("codex", "c1", "z"), ("claude", "a1", "m2"), ("codex", "c1", "x")])

    # Class: preserves invariant (exact-equality staleness/expiry is due; no zeroing)
    def test_12_age_and_reset_boundaries(self):
        out = self.rank([
            self.snap("p", "age89", [self.met("a", 10)], age=89),
            self.snap("p", "age90", [self.met("a", 99)], age=90),
            self.snap("p", "r", [self.met("eq", 98, NOW), self.met("past", 97, NOW - 1),
                                 self.met("fut", 20, NOW + 1)]),
        ])
        got = {(o["accountID"], o["id"]): o["usedPercent"] for o in out}
        self.assertEqual(got, {("age89", "a"): 10, ("r", "fut"): 20})


if __name__ == "__main__":
    unittest.main()
