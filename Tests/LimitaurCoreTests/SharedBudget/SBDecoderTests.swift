import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline shows "Spend" at spend.percent, no reset, no limit,
// and warns "Spend limit or balance metadata unavailable"), I = preserves an invariant, N = exercises new behaviour.
// Criteria C3 (Claude) and C4 (Cursor).

private func spendMetric(_ snapshot: UsageSnapshot) -> UsageMetric? { snapshot.metrics.first { $0.id == "spend" } }

@Suite struct SBClaudeDecoderTests {
    // R, C3: the observed shape gives "Monthly spend" at the utilization percent, both amounts, a reset from the default day,
    // snapshot.spend, no warning and not partial.
    @Test func observedShape() throws {
        let snapshot = try sbDecodeClaude()
        let metric = try #require(spendMetric(snapshot))
        let percent = try #require(metric.usedPercent)
        #expect(metric.label == "Monthly spend" && abs(percent - 8.2) < 1e-9)
        #expect(metric.resetsAt == sbUTC(2026, 12, 1))
        let amounts = sbAmounts(snapshot)
        #expect(amounts["Spent this cycle"]?.amount == 410 && amounts["Spent this cycle"]?.currency == "USD")
        #expect(amounts["Spend limit"]?.amount == 5000 && amounts["Spend limit"]?.currency == "USD")
        #expect(snapshot.spend == SpendSummary(spent: 410, limit: 5000, currency: "USD", periodEnd: sbUTC(2026, 12, 1)))
        #expect(snapshot.warnings.isEmpty && !snapshot.partial)
        #expect(snapshot.metrics.contains { $0.id != "spend" }, "the quota rows stay")
    }
    // R, C3: with the shape's own spend.percent (15) differing from utilization (8.2), utilization wins; the old label is gone.
    @Test func oldLabelAndAmountNamesAreGone() throws {
        let snapshot = try sbDecodeClaude()
        #expect(!snapshot.metrics.contains { $0.label == "Spend" })
        #expect(sbAmounts(snapshot)["Spend used"] == nil)
    }
    // N, C3/I3: the reset comes from the configured day, relative to `now` (2026-11-10 12:00 UTC).
    @Test func resetFollowsTheConfiguredDay() throws {
        for (day, expected) in [(MonthlyResetDay.day(1), sbUTC(2026, 12, 1)), (.day(15), sbUTC(2026, 11, 15)),
                                (.day(5), sbUTC(2026, 12, 5)), (.lastDay, sbUTC(2026, 11, 30)), (.day(10), sbUTC(2026, 12, 10))] {
            let snapshot = try sbDecodeClaude(day: day)
            #expect(spendMetric(snapshot)?.resetsAt == expected, "\(day)")
            #expect(snapshot.spend?.periodEnd == expected, "\(day)")
        }
    }
    // N, C3: each utilization condition failing falls back to spend.percent (15) without a warning.
    @Test func utilizationFallbackConditions() throws {
        let overrides: [[String: Any]] = [["is_enabled": false], ["monthly_limit": 400000], ["used_credits": 40999.0], ["used_credits": 41000.5],
                                          ["currency": "EUR"], ["utilization": -1], ["utilization": "8.2"], ["utilization": NSNull()]]
        for override in overrides {
            let snapshot = try sbDecodeClaude(sbClaudeBody(extra: sbExtra(override)))
            #expect(spendMetric(snapshot)?.usedPercent == 15, "\(override)")
            #expect(snapshot.warnings.isEmpty && !snapshot.partial, "\(override)")
        }
    }
    // N, C3: an absent extra_usage, or an absent field in it, also falls back.
    @Test func missingExtraUsageFallsBack() throws {
        #expect(spendMetric(try sbDecodeClaude(sbClaudeBody(extra: nil)))?.usedPercent == 15)
        for key in ["monthly_limit", "used_credits", "currency", "utilization", "is_enabled"] {
            var extra = sbExtra(); extra[key] = nil
            #expect(spendMetric(try sbDecodeClaude(sbClaudeBody(extra: extra)))?.usedPercent == 15, "\(key)")
        }
    }
    // N, C3: used_credits compares numerically (41000 == 41000.0), and a mismatch of the limit against a different limit amount falls back.
    @Test func utilizationAcceptsNumericallyEqualCredits() throws {
        for credits in [41000, 41000.0] as [Any] {
            #expect(spendMetric(try sbDecodeClaude(sbClaudeBody(extra: sbExtra(["used_credits": credits]))))?.usedPercent == 8.2)
        }
        let other = ["amount_minor": 600000, "currency": "USD", "exponent": 2] as [String: Any]
        let snapshot = try sbDecodeClaude(sbClaudeBody(spend: sbSpend(["limit": other])))
        #expect(spendMetric(snapshot)?.usedPercent == 15, "extra_usage.monthly_limit no longer matches spend.limit")
    }
    // I, C3: when no percent is usable the existing rule applies: no spend metric and "Spend usage unavailable".
    @Test func noUsablePercentWarnsAsBefore() throws {
        var spend = sbSpend(); spend["percent"] = nil
        let snapshot = try sbDecodeClaude(sbClaudeBody(spend: spend, extra: sbExtra(["is_enabled": false])))
        #expect(spendMetric(snapshot) == nil && snapshot.warnings == ["Spend usage unavailable"] && snapshot.partial)
        #expect(snapshot.spend?.spent == 410, "the amounts are still reported")
        var bad = sbSpend(); bad["percent"] = "15"
        #expect(spendMetric(try sbDecodeClaude(sbClaudeBody(spend: bad, extra: nil))) == nil)
    }
    // N, C3: a malformed limit warns "Spend limit unavailable", lists no limit amount and leaves spend.limit nil.
    @Test func malformedLimitWarns() throws {
        let limits: [Any] = [["amount_minor": "x", "currency": "USD", "exponent": 2], ["amount_minor": 5, "currency": "", "exponent": 2],
                             ["amount_minor": 5, "currency": "USD"], ["amount_minor": -1.5, "currency": "USD", "exponent": 2],
                             [String: Any](), "oops"]
        for limit in limits {
            let snapshot = try sbDecodeClaude(sbClaudeBody(spend: sbSpend(["limit": limit])))
            #expect(snapshot.warnings == ["Spend limit unavailable"] && snapshot.partial, "\(limit)")
            #expect(sbAmounts(snapshot)["Spend limit"] == nil && snapshot.spend?.limit == nil && snapshot.spend?.spent == 410)
            #expect(sbAmounts(snapshot)["Spent this cycle"]?.amount == 410)
        }
    }
    // R, C3: non-null cap, balance and auto_reload raise no warning and are not exposed as balances.
    @Test func capBalanceAndAutoReloadAreIgnored() throws {
        let money = ["amount_minor": 7, "currency": "USD", "exponent": 2] as [String: Any]
        let spend = sbSpend(["balance": money, "cap": ["money": money, "credits": money], "auto_reload": ["enabled": true, "threshold": money]])
        let snapshot = try sbDecodeClaude(sbClaudeBody(spend: spend))
        #expect(snapshot.warnings.isEmpty && !snapshot.partial && snapshot.balances.isEmpty)
        #expect(snapshot.spend == SpendSummary(spent: 410, limit: 5000, currency: "USD", periodEnd: sbUTC(2026, 12, 1)))
    }
    // N, C3: a limit in another currency gives a nil spend.limit; both amounts keep their own currency; spent stays in used's.
    @Test func differentLimitCurrency() throws {
        let euro = ["amount_minor": 500000, "currency": "EUR", "exponent": 2] as [String: Any]
        let snapshot = try sbDecodeClaude(sbClaudeBody(spend: sbSpend(["limit": euro])))
        #expect(snapshot.spend?.limit == nil && snapshot.spend?.currency == "USD" && snapshot.spend?.spent == 410)
        #expect(sbAmounts(snapshot)["Spend limit"]?.currency == "EUR" && sbAmounts(snapshot)["Spent this cycle"]?.currency == "USD")
    }
    // N, C3: an absent limit keeps the spend but has no limit amount; invalid used gives no spend summary.
    @Test func absentLimitAndInvalidUsed() throws {
        let noLimit = try sbDecodeClaude(sbClaudeBody(spend: sbSpend(["limit": NSNull()])))
        #expect(noLimit.spend?.limit == nil && noLimit.spend?.spent == 410 && sbAmounts(noLimit)["Spend limit"] == nil)
        let badUsed = try sbDecodeClaude(sbClaudeBody(spend: sbSpend(["used": ["amount_minor": "x", "currency": "USD", "exponent": 2]])))
        #expect(badUsed.spend == nil && badUsed.warnings.contains("Spend units unavailable"))
    }
    // I, C3: a disabled spend is unchanged: no spend metric, amounts, warning or summary (the checked-in fixture's shape).
    @Test func disabledSpendIsUnchanged() throws {
        let snapshot = try sbDecodeClaude(sbClaudeBody(spend: sbSpend(["enabled": false]), extra: nil))
        #expect(spendMetric(snapshot) == nil && snapshot.informationalAmounts.isEmpty && snapshot.spend == nil)
        #expect(snapshot.warnings.isEmpty && !snapshot.partial)
        let bad = try sbDecodeClaude(sbClaudeBody(spend: sbSpend(["enabled": 1])))
        #expect(bad.warnings == ["Spend status unavailable"] && bad.spend == nil)
    }
    // I, C3: with spend absent, the extra_usage branch is unchanged: "Extra usage" at its utilization, with its units warning.
    @Test func extraUsageBranchWithoutSpendIsUnchanged() throws {
        let snapshot = try sbDecodeClaude(sbClaudeBody(spend: nil))
        #expect(snapshot.metrics.first { $0.id == "extra_usage" }?.usedPercent == 8.2 && snapshot.metrics.first { $0.id == "extra_usage" }?.label == "Extra usage")
        #expect(snapshot.warnings == ["Extra usage amount units unavailable"] && snapshot.spend == nil)
    }
    // I, C3: Codex ignores the new parameter.
    @Test func codexIgnoresTheResetDay() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":20}}}"#.utf8)
        func decode(_ day: MonthlyResetDay) throws -> UsageSnapshot {
            try UsageDecoder.decode(provider: "codex", data: data, accountID: "a", accountLabel: "L", now: sbNow, spendResetDay: day)
        }
        let fifteen = try decode(.day(15)), defaulted = try decode(.default), last = try decode(.lastDay)
        #expect(fifteen == defaulted && last.spend == nil)
    }
}

@Suite struct SBSnapshotTests {
    // I, I2: `spend` defaults to nil, round-trips, and an old encoding without the key still decodes.
    @Test func spendIsOptionalAndBackwardCompatible() throws {
        let plain = UsageSnapshot(providerID: "claude", accountID: "a", accountLabel: "L", fetchedAt: sbNow, metrics: [])
        #expect(plain.spend == nil)
        let encoded = try JSONEncoder().encode(plain)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["spend"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: old) == plain)
        let withSpend = UsageSnapshot(providerID: "claude", accountID: "a", accountLabel: "L", fetchedAt: sbNow, metrics: [],
                                      spend: sbSummary(12.5, limit: nil, end: nil))
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(withSpend)) == withSpend)
    }
}

@Suite struct SBCursorDecoderTests {
    // N, C4: the traced Cursor envelope fills snapshot.spend (41 of 5000 USD, ends at the cycle end); metrics and amounts are as before.
    @Test func cursorFillsSpend() throws {
        let snapshot = try cpDecode(cpEnvelope())
        #expect(snapshot.spend == SpendSummary(spent: 41, limit: 5000, currency: "USD", periodEnd: Date(timeIntervalSince1970: 1_702_592_000)))
        #expect(snapshot.metrics.count == 1 && snapshot.metrics.first?.id == "spend" && snapshot.metrics.first?.label == "Monthly spend")
        #expect(abs(try #require(snapshot.metrics.first?.usedPercent) - 0.82) < 1e-9)
        #expect(snapshot.informationalAmounts.map(\.label) == ["Spent this cycle", "Spend limit"] && !snapshot.partial)
    }
    // N, C4: cents are exact decimals.
    @Test func cursorCentsAreExact() throws {
        let snapshot = try cpDecode(cpEnvelope(daily: cpDaily(rows: [cpRow(cents: 4123)], limit: 123_457)))
        #expect(snapshot.spend?.spent == Decimal(string: "41.23") && snapshot.spend?.limit == Decimal(string: "1234.57"))
    }
    // N, C4: spend is filled whenever "Spent this cycle" is listed: a missing limit leaves limit nil; known-empty rows are 0.
    @Test func cursorWithoutLimitOrRows() throws {
        let noLimit = try cpDecode(cpEnvelope(daily: cpDaily(limit: nil)))
        #expect(noLimit.spend?.spent == 41 && noLimit.spend?.limit == nil && noLimit.spend?.currency == "USD")
        let empty = try cpDecode(cpEnvelope(daily: cpDaily(rows: nil)))
        #expect(empty.spend?.spent == 0 && empty.spend?.limit == 5000)
    }
    // I, C4: when spend is unknown (no rows and no limit) no amount is listed and there is no summary.
    @Test func cursorUnknownSpendHasNoSummary() throws {
        let snapshot = try cpDecode(cpEnvelope(daily: [String: Any]()))
        #expect(snapshot.informationalAmounts.isEmpty && snapshot.spend == nil)
    }
}
