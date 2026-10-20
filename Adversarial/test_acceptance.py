"""Phase-A black-box acceptance tests for Limitaur.

These tests intentionally know nothing about the Swift implementation.  They invoke
the documented production diagnostic entry points against invented data only.

Run from the repository root after a release build:

    LIMITAUR_BINARY=.build/release/Limitaur \
      python3 -m unittest -v Adversarial/test_acceptance.py

The driver is responsible for providing network and credential isolation.  Each
subprocess also receives a fresh HOME and a minimal environment so fixture tests
cannot discover a normal provider session accidentally.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from decimal import Decimal, InvalidOperation


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BINARY = REPOSITORY_ROOT / ".build" / "release" / "Limitaur"


class DiagnosticSurfaceCase(unittest.TestCase):
    """Shared process and JSON assertions; this class contains no test cases."""

    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        configured = os.environ.get("LIMITAUR_BINARY")
        cls.binary = Path(configured) if configured else DEFAULT_BINARY
        if not cls.binary.is_file():
            raise RuntimeError(
                "Limitaur diagnostic binary is missing; build release first or set "
                "LIMITAUR_BINARY"
            )

    def _run(self, arguments: list[str], sandbox: Path) -> subprocess.CompletedProcess[str]:
        environment = {
            "HOME": str(sandbox),
            "TMPDIR": str(sandbox),
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "LC_ALL": "C",
        }
        return subprocess.run(
            [str(self.binary), *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            check=False,
            env=environment,
        )

    def _successful_json(self, arguments: list[str], sandbox: Path):
        completed = self._run(arguments, sandbox)
        self.assertEqual(completed.returncode, 0, "diagnostic command failed")
        self.assertEqual(completed.stderr, "", "successful diagnostics must be quiet")
        try:
            return json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            self.fail(f"diagnostic stdout was not exactly one JSON value: {error}")

    def _inspect(self, provider: str, fixture: object) -> dict:
        with tempfile.TemporaryDirectory(prefix="limitaur-a-") as temporary:
            sandbox = Path(temporary)
            fixture_path = sandbox / "fixture.json"
            fixture_path.write_text(
                json.dumps(fixture, allow_nan=False), encoding="utf-8"
            )
            value = self._successful_json(
                ["--inspect-fixture", provider, str(fixture_path)], sandbox
            )
        self.assertIsInstance(value, dict)
        self.assertIsInstance(value.get("providerID"), str)
        self.assertIsInstance(value.get("metrics"), list)
        self.assertIsInstance(value.get("balances"), list)
        self.assertTrue(
            value.get("resetCredits") is None
            or isinstance(value.get("resetCredits"), dict)
        )
        self.assertIs(type(value.get("partial")), bool)
        self.assertIsInstance(value.get("warnings"), list)
        return value

    def _rank(self, snapshots: list[dict], now: float) -> list[dict]:
        with tempfile.TemporaryDirectory(prefix="limitaur-a-") as temporary:
            sandbox = Path(temporary)
            fixture_path = sandbox / "ranking.json"
            fixture_path.write_text(
                json.dumps(snapshots, allow_nan=False), encoding="utf-8"
            )
            value = self._successful_json(
                ["--rank-fixture", str(fixture_path), "--now", str(now)], sandbox
            )
        self.assertIsInstance(value, list)
        for selected in value:
            self.assertIsInstance(selected, dict)
            self.assertTrue(
                {"providerID", "accountID", "id", "usedPercent"}
                <= selected.keys()
            )
        return value

    def _check_percent(self, value: str) -> dict:
        with tempfile.TemporaryDirectory(prefix="limitaur-a-") as temporary:
            result = self._successful_json(
                ["--check-percent", value], Path(temporary)
            )
        self.assertIsInstance(result, dict)
        self.assertIn(result.get("severity"), {"normal", "warning", "critical", "unknown"})
        fill = result.get("fill")
        self.assertTrue(fill is None or (type(fill) in (int, float) and 0 <= fill <= 1))
        return result

    def _invalid_fixture_result(self, provider: str, fixture: object):
        temporary = tempfile.TemporaryDirectory(prefix="limitaur-a-")
        self.addCleanup(temporary.cleanup)
        sandbox = Path(temporary.name)
        fixture_path = sandbox / "invalid.json"
        fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
        completed = self._run(
            ["--inspect-fixture", provider, str(fixture_path)], sandbox
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(completed.stdout.strip(), "", "invalid envelopes emit no snapshot")
        message = completed.stderr.strip()
        self.assertTrue(message, "invalid envelopes require a fixed sanitized error")
        self.assertEqual(len(message.splitlines()), 1)
        self.assertNotIn(str(fixture_path), message)
        return completed, message


class PreservesInvariantAcceptanceTests(DiagnosticSurfaceCase):
    """Cases classified as: preserves invariant."""

    acceptance_classification = "preserves invariant"

    def test_percent_thresholds_use_raw_value_and_clamp_only_fill(self) -> None:
        cases = {
            "0": ("normal", 0.0),
            "80": ("normal", 0.8),
            "80.01": ("warning", 0.8001),
            "95": ("warning", 0.95),
            "95.01": ("critical", 0.9501),
            "100": ("critical", 1.0),
            "137.5": ("critical", 1.0),
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                result = self._check_percent(raw)
                self.assertEqual(result["severity"], expected[0])
                self.assertAlmostEqual(result["fill"], expected[1], places=8)

    def test_negative_and_nonfinite_percentages_are_unknown_not_zero(self) -> None:
        for raw in ("-0.01", "nan", "inf", "-inf"):
            with self.subTest(raw=raw):
                result = self._check_percent(raw)
                self.assertEqual(result, {"severity": "unknown", "fill": None})

    def test_ranking_selects_three_across_accounts_with_lexical_ties(self) -> None:
        snapshots = [
            {
                "providerID": "claude",
                "accountID": "account-b",
                "accountLabel": "mutable label z",
                "fetchedAt": 990,
                "metrics": [
                    {"id": "shared", "label": "B", "usedPercent": 92, "resetsAt": None},
                    {"id": "fourth", "label": "D", "usedPercent": 84, "resetsAt": None},
                ],
            },
            {
                "providerID": "claude",
                "accountID": "account-a",
                "accountLabel": "mutable label a",
                "fetchedAt": 990,
                "metrics": [
                    {"id": "shared", "label": "A", "usedPercent": 92, "resetsAt": None}
                ],
            },
            {
                "providerID": "codex",
                "accountID": "account-c",
                "fetchedAt": 990,
                "metrics": [
                    {"id": "third", "label": "C", "usedPercent": 85, "resetsAt": None}
                ],
            },
        ]
        selected = self._rank(snapshots, now=1000)
        self.assertEqual(
            [(row["providerID"], row["accountID"], row["id"], row["usedPercent"]) for row in selected],
            [
                ("claude", "account-a", "shared", 92),
                ("claude", "account-b", "shared", 92),
                ("codex", "account-c", "third", 85),
            ],
        )

    def test_ranking_deduplicates_identity_and_excludes_unknown_or_invalid_values(self) -> None:
        snapshots = [
            {
                "providerID": "codex",
                "accountID": "account-a",
                "fetchedAt": 500,
                "metrics": [
                    {"id": "valid", "label": "Valid", "usedPercent": 88, "resetsAt": None},
                    {"id": "valid", "label": "Valid duplicate", "usedPercent": 88, "resetsAt": None},
                    {"id": "unknown", "label": "Unknown", "usedPercent": None, "resetsAt": None},
                    {"id": "negative", "label": "Negative", "usedPercent": -1, "resetsAt": None},
                    {"id": "wrong-type", "label": "Wrong", "usedPercent": "91", "resetsAt": None},
                    {"id": "zero", "label": "Zero", "usedPercent": 0, "resetsAt": None},
                ],
            }
        ]
        selected = self._rank(snapshots, now=500)
        self.assertEqual([row["id"] for row in selected], ["valid", "zero"])
        self.assertEqual([row["usedPercent"] for row in selected], [88, 0])

    def test_freshness_and_reset_expire_at_exact_equality(self) -> None:
        snapshots = [
            {
                "providerID": "codex",
                "accountID": "stale-account",
                "fetchedAt": 1910,
                "metrics": [
                    {"id": "age-equal", "label": "Age equal", "usedPercent": 99, "resetsAt": None}
                ],
            },
            {
                "providerID": "codex",
                "accountID": "fresh-account",
                "fetchedAt": 1910.001,
                "metrics": [
                    {"id": "fresh", "label": "Fresh", "usedPercent": 60, "resetsAt": None},
                    {"id": "reset-equal", "label": "Due", "usedPercent": 98, "resetsAt": 2000},
                    {"id": "reset-past", "label": "Past", "usedPercent": 97, "resetsAt": 1999.999},
                    {"id": "reset-future", "label": "Future", "usedPercent": 50, "resetsAt": 2000.001},
                ],
            },
        ]
        selected = self._rank(snapshots, now=2000)
        self.assertEqual([row["id"] for row in selected], ["fresh", "reset-future"])

    def test_codex_direct_preserves_windows_credit_units_and_count_only_resets(self) -> None:
        snapshot = self._inspect(
            "codex",
            {
                "rate_limit": {
                    "primary_window": {
                        "used_percent": 25,
                        "limit_window_seconds": 18000,
                        "reset_at": 1893456000,
                    },
                    "secondary_window": {
                        "used_percent": 85,
                        "limit_window_seconds": 604800,
                        "reset_at": 1894060800,
                    },
                },
                "additional_rate_limits": None,
                "code_review_rate_limit": None,
                "credits": {"has_credits": True, "unlimited": False, "balance": "17.2500"},
                "rate_limit_reset_credits": {
                    "available_count": 7,
                    "applicable_available_count": 3,
                },
            },
        )
        self.assertEqual(sorted(metric["usedPercent"] for metric in snapshot["metrics"]), [25, 85])
        self.assertEqual(len({metric["id"] for metric in snapshot["metrics"]}), 2)
        self.assertEqual(
            sorted(metric["resetsAt"] for metric in snapshot["metrics"]),
            [1893456000, 1894060800],
        )
        self.assertEqual(len(snapshot["balances"]), 1)
        balance = snapshot["balances"][0]
        try:
            remaining = Decimal(balance["remaining"])
        except (InvalidOperation, TypeError) as error:
            self.fail(f"credit balance was not emitted as a decimal string: {error}")
        self.assertEqual(remaining, Decimal("17.2500"))
        self.assertIsNone(balance["currency"])
        self.assertFalse(balance["unlimited"])
        self.assertIsNone(balance["expiresAt"])
        self.assertEqual(snapshot["resetCredits"]["availableCount"], 7)
        self.assertEqual(snapshot["resetCredits"]["applicableCount"], 3)
        self.assertIsNone(snapshot["resetCredits"]["details"])
        self.assertFalse(snapshot["partial"])

    def test_codex_unlimited_credit_is_not_zero_or_currency(self) -> None:
        snapshot = self._inspect(
            "codex",
            {"credits": {"has_credits": True, "unlimited": True, "balance": None}},
        )
        self.assertEqual(len(snapshot["balances"]), 1)
        balance = snapshot["balances"][0]
        self.assertTrue(balance["unlimited"])
        self.assertIsNone(balance["remaining"])
        self.assertIsNone(balance["currency"])
        self.assertIsNone(balance["expiresAt"])

    def test_codex_app_server_distinguishes_count_only_from_known_empty_details(self) -> None:
        count_only = self._inspect(
            "codex",
            {
                "rateLimitsByLimitId": {},
                "rateLimitResetCredits": {"availableCount": 2, "credits": None},
            },
        )
        known_empty = self._inspect(
            "codex",
            {
                "rateLimitsByLimitId": {},
                "rateLimitResetCredits": {"availableCount": 0, "credits": []},
            },
        )
        self.assertEqual(count_only["resetCredits"]["availableCount"], 2)
        self.assertIsNone(count_only["resetCredits"]["details"])
        self.assertEqual(known_empty["resetCredits"]["availableCount"], 0)
        self.assertEqual(known_empty["resetCredits"]["details"], [])

    def test_claude_empty_modern_limits_are_authoritative_over_legacy(self) -> None:
        snapshot = self._inspect(
            "claude",
            {
                "limits": [],
                "five_hour": {"utilization": 71, "resets_at": "2030-01-01T00:00:00Z"},
                "seven_day": {"utilization": 72, "resets_at": None},
            },
        )
        self.assertEqual(snapshot["metrics"], [])
        self.assertFalse(snapshot["partial"])

    def test_invalid_envelopes_fail_without_snapshot_and_use_fixed_sanitized_errors(self) -> None:
        _, empty_error = self._invalid_fixture_result("codex", {})
        _, future_error = self._invalid_fixture_result(
            "codex", {"future_only": {"opaque": "SENTINEL_NOT_FOR_ERROR"}}
        )
        self.assertEqual(empty_error, future_error)
        self.assertNotIn("SENTINEL_NOT_FOR_ERROR", future_error)


class ExercisesNewBehaviorAcceptanceTests(DiagnosticSurfaceCase):
    """Cases classified as: exercises new behavior."""

    acceptance_classification = "exercises new behavior"

    def test_codex_app_server_prefers_modern_map_without_legacy_duplication(self) -> None:
        snapshot = self._inspect(
            "codex",
            {
                "rateLimitsByLimitId": {
                    "bucket-b": {
                        "primary": {
                            "usedPercent": 62,
                            "windowDurationMins": 300,
                            "resetsAt": 1893456000,
                        }
                    },
                    "bucket-a": {
                        "secondary": {
                            "usedPercent": 41,
                            "windowDurationMins": 10080,
                            "resetsAt": 1894060800,
                        }
                    },
                },
                "rateLimits": {
                    "primary": {
                        "usedPercent": 99,
                        "windowDurationMins": 60,
                        "resetsAt": 1893000000,
                    }
                },
            },
        )
        self.assertEqual(sorted(metric["usedPercent"] for metric in snapshot["metrics"]), [41, 62])
        self.assertEqual(len({metric["id"] for metric in snapshot["metrics"]}), 2)
        self.assertNotIn(99, [metric["usedPercent"] for metric in snapshot["metrics"]])

    def test_claude_inactive_fable_is_preserved_and_exact_duplicates_are_deduplicated(self) -> None:
        fable = {
            "kind": "weekly",
            "group": "scoped",
            "percent": 65,
            "resets_at": "2030-01-01T01:00:00+01:00",
            "scope": {
                "model": {"id": "model-a", "display_name": "Fable"},
                "surface": "chat",
            },
            "is_active": False,
        }
        snapshot = self._inspect(
            "claude",
            {
                "limits": [
                    fable,
                    dict(fable),
                    {
                        "kind": "weekly",
                        "group": "scoped",
                        "percent": 66,
                        "resets_at": "2030-01-01T00:00:00.000Z",
                        "scope": {
                            "model": {"id": "model-b", "display_name": "Atlas"},
                            "surface": "chat",
                        },
                        "is_active": False,
                    },
                ]
            },
        )
        self.assertEqual(len(snapshot["metrics"]), 2)
        self.assertEqual(sorted(metric["usedPercent"] for metric in snapshot["metrics"]), [65, 66])
        self.assertEqual(len({metric["id"] for metric in snapshot["metrics"]}), 2)
        self.assertTrue(any("Fable" in metric["label"] for metric in snapshot["metrics"]))
        self.assertEqual({metric["resetsAt"] for metric in snapshot["metrics"]}, {1893456000})

    def test_claude_explicit_future_meter_and_unknown_top_level_fields_survive_together(self) -> None:
        snapshot = self._inspect(
            "claude",
            {
                "limits": [
                    {
                        "kind": "future_window_kind",
                        "group": "future-group",
                        "percent": 12.3,
                        "resets_at": None,
                        "scope": {
                            "model": {"id": "future-model", "display_name": "Nebula"},
                            "surface": "future-surface",
                            "future_scope_field": {"ignored": True},
                        },
                        "is_active": True,
                        "future_row_field": [1, 2, 3],
                    }
                ],
                "future_top_level": {"ignored": True},
            },
        )
        self.assertEqual(len(snapshot["metrics"]), 1)
        self.assertEqual(snapshot["metrics"][0]["usedPercent"], 12.3)
        self.assertIn("Nebula", snapshot["metrics"][0]["label"])
        self.assertFalse(snapshot["partial"])

    def test_claude_null_modern_limits_enable_legacy_fallback(self) -> None:
        snapshot = self._inspect(
            "claude",
            {
                "limits": None,
                "five_hour": {"utilization": 24, "resets_at": "2030-01-01T00:00:00Z"},
                "seven_day": {"utilization": 74, "resets_at": None},
            },
        )
        self.assertEqual(sorted(metric["usedPercent"] for metric in snapshot["metrics"]), [24, 74])
        self.assertEqual(len({metric["id"] for metric in snapshot["metrics"]}), 2)

    def test_mixed_malformed_claude_rows_are_partial_but_all_malformed_rows_fail(self) -> None:
        mixed = self._inspect(
            "claude",
            {
                "limits": [
                    {
                        "kind": "session",
                        "group": "all",
                        "percent": 44,
                        "resets_at": None,
                        "scope": {"surface": "chat"},
                        "is_active": True,
                    },
                    {"kind": "weekly", "percent": -1, "resets_at": None},
                    {"kind": "weekly", "percent": True, "resets_at": None},
                    {"kind": "weekly", "percent": "91", "resets_at": None},
                ]
            },
        )
        self.assertEqual([metric["usedPercent"] for metric in mixed["metrics"]], [44])
        self.assertTrue(mixed["partial"])
        self.assertGreater(len(mixed["warnings"]), 0)

        completed, message = self._invalid_fixture_result(
            "claude",
            {
                "limits": [
                    {"kind": "weekly", "percent": -1},
                    {"kind": "weekly", "percent": "91"},
                ]
            },
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertTrue(message)

    def test_wrong_type_authoritative_container_does_not_fall_back(self) -> None:
        completed, message = self._invalid_fixture_result(
            "claude",
            {
                "limits": {"not": "an array"},
                "five_hour": {"utilization": 77, "resets_at": None},
            },
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertNotIn("77", message)

    def test_codex_mixed_window_failure_retains_valid_data_as_partial(self) -> None:
        snapshot = self._inspect(
            "codex",
            {
                "rate_limit": {
                    "primary_window": {
                        "used_percent": 53,
                        "limit_window_seconds": 18000,
                        "reset_at": 1893456000,
                    },
                    "secondary_window": {
                        "used_percent": "not-a-number",
                        "limit_window_seconds": 604800,
                        "reset_at": 1894060800,
                    },
                }
            },
        )
        self.assertEqual([metric["usedPercent"] for metric in snapshot["metrics"]], [53])
        self.assertTrue(snapshot["partial"])
        self.assertGreater(len(snapshot["warnings"]), 0)

    def test_reset_detail_cap_is_visible_and_count_remains_authoritative(self) -> None:
        details = [
            {
                "id": f"invented-{index:03d}",
                "label": f"Synthetic reset {index:03d}",
                "expiresAt": 1893456000 + index,
            }
            for index in range(130)
        ]
        snapshot = self._inspect(
            "codex",
            {
                "rateLimitsByLimitId": {},
                "rateLimitResetCredits": {
                    "availableCount": 130,
                    "credits": details,
                },
            },
        )
        summary = snapshot["resetCredits"]
        self.assertEqual(summary["availableCount"], 130)
        self.assertIsNone(summary["applicableCount"])
        self.assertEqual(len(summary["details"]), 128)
        self.assertTrue(snapshot["partial"])
        self.assertGreater(len(snapshot["warnings"]), 0)

    def test_unverified_claude_money_does_not_become_a_known_balance(self) -> None:
        amount = {"amount_minor": 12345, "currency": "ZZZ", "exponent": 3}
        snapshot = self._inspect(
            "claude",
            {
                "limits": [],
                "spend": {
                    "enabled": True,
                    "percent": 33.3,
                    "used": amount,
                    "limit": amount,
                    "balance": amount,
                    "cap": amount,
                },
            },
        )
        self.assertIn(33.3, [metric["usedPercent"] for metric in snapshot["metrics"]])
        self.assertTrue(
            all(balance["remaining"] is None for balance in snapshot["balances"]),
            "unverified nonnull spend shapes must not become a known monetary balance",
        )
        self.assertTrue(snapshot["partial"] or snapshot["warnings"])


if __name__ == "__main__":
    unittest.main()
