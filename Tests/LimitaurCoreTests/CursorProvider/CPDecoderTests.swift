import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline decode(provider: "cursor") always throws),
// I = preserves an invariant, N = exercises new behaviour.

private func cpAmounts(_ snapshot: UsageSnapshot) -> [String: (Decimal, String)] {
    Dictionary(uniqueKeysWithValues: snapshot.informationalAmounts.map { ($0.label, ($0.amount, $0.currency)) })
}
private func cpPercent(spent cents: Int, limit: Int = 500_000) throws -> Double {
    try #require(try cpDecode(cpEnvelope(daily: cpDaily(rows: [cpRow(cents: cents)], limit: limit))).metrics.first?.usedPercent)
}

@Suite struct CPDecoderTests {
    // R, C5/I5/Traced path 5: the traced example gives 0.82 %, code `$`, reset at the cycle end, 41 and 5000 USD.
    @Test func tracedExample() throws {
        let snapshot = try cpDecode(cpEnvelope())
        #expect(snapshot.providerID == "cursor" && snapshot.accountID == "acct" && snapshot.accountLabel == "Label" && snapshot.fetchedAt == cpNow)
        let metric = try #require(snapshot.metrics.first)
        #expect(snapshot.metrics.count == 1 && metric.id == "spend" && metric.label == "Monthly spend")
        #expect(abs(try #require(metric.usedPercent) - 0.82) < 1e-9)
        #expect(metric.resetsAt == Date(timeIntervalSince1970: 1_702_592_000) && metric.windowDuration == nil)
        #expect(windowCode(for: metric) == "$" && providerGlyph(for: snapshot.providerID) == "CU")
        let amounts = cpAmounts(snapshot)
        #expect(snapshot.informationalAmounts.count == 2)
        #expect(amounts["Spent this cycle"]?.0 == 41 && amounts["Spent this cycle"]?.1 == "USD")
        #expect(amounts["Spend limit"]?.0 == 5000 && amounts["Spend limit"]?.1 == "USD")
        #expect(!snapshot.partial && snapshot.warnings.isEmpty && snapshot.balances.isEmpty && snapshot.resetCredits == nil)
        // The metric ranks like any other provider's.
        #expect(rankMetrics([snapshot], wallNow: Date(timeIntervalSince1970: 1_700_100_000)).first?.providerID == "cursor")
    }
    // N, I5.5: amounts are Decimal cents ÷ 100 with no float drift.
    @Test func amountsAreExactDecimals() throws {
        let snapshot = try cpDecode(cpEnvelope(daily: cpDaily(rows: [cpRow(cents: 4123)], limit: 123_457)))
        let amounts = cpAmounts(snapshot)
        #expect(amounts["Spent this cycle"]?.0 == Decimal(string: "41.23") && amounts["Spend limit"]?.0 == Decimal(string: "1234.57"))
    }
    // N, C5/I5.4: no rows, or an absent list, with a limit is a known 0 %, not unknown.
    @Test func noRowsIsKnownZero() throws {
        for rows in [nil, [Any]()] as [Any?] {
            let snapshot = try cpDecode(cpEnvelope(daily: cpDaily(rows: rows)))
            let metric = try #require(snapshot.metrics.first)
            #expect(metric.usedPercent == 0 && !snapshot.partial)
            #expect(cpAmounts(snapshot)["Spent this cycle"]?.0 == 0 && cpAmounts(snapshot)["Spend limit"]?.0 == 5000)
        }
    }
    // N, I5.6/C5: limit absent and limit zero give their distinct warnings, partial, no metric, and still list the spend.
    @Test func absentAndZeroLimitWarnDistinctly() throws {
        let absent = try cpDecode(cpEnvelope(daily: cpDaily(limit: nil)))
        #expect(absent.metrics.isEmpty && absent.partial && absent.warnings == ["Spend limit unavailable"])
        #expect(cpAmounts(absent)["Spent this cycle"]?.0 == 41)
        let zero = try cpDecode(cpEnvelope(daily: cpDaily(limit: 0)))
        #expect(zero.metrics.isEmpty && zero.partial && zero.warnings == ["Spend limit is zero"])
        #expect(cpAmounts(zero)["Spent this cycle"]?.0 == 41)
        let bare = try cpDecode(cpEnvelope(daily: cpDaily(rows: nil, limit: nil)))
        #expect(bare.metrics.isEmpty && bare.warnings == ["Spend limit unavailable"] && bare.informationalAmounts.isEmpty)
    }
    // R, I5.6 (revision 3): spend is unknown, not zero, when neither dailySpend nor a limit is present.
    @Test func unknownSpendIsNotListedAsZero() throws {
        let neither = try cpDecode(cpEnvelope(daily: [String: Any]()))
        #expect(neither.metrics.isEmpty && neither.partial && neither.warnings == ["Spend limit unavailable"])
        #expect(neither.informationalAmounts.isEmpty)
        let zeroLimit = try cpDecode(cpEnvelope(daily: cpDaily(rows: nil, limit: 0)))
        #expect(zeroLimit.metrics.isEmpty && zeroLimit.warnings == ["Spend limit is zero"] && zeroLimit.informationalAmounts.isEmpty)
        let presentEmpty = try cpDecode(cpEnvelope(daily: cpDaily(rows: [Any](), limit: nil)))
        #expect(presentEmpty.metrics.isEmpty && presentEmpty.warnings == ["Spend limit unavailable"])
        #expect(cpAmounts(presentEmpty)["Spent this cycle"]?.0 == 0 && presentEmpty.informationalAmounts.count == 1)
        let present = try cpDecode(cpEnvelope(daily: cpDaily(limit: nil)))
        #expect(cpAmounts(present)["Spent this cycle"]?.0 == 41 && present.informationalAmounts.count == 1)
        // With a positive limit an absent dailySpend is still a known 0.
        let known = try cpDecode(cpEnvelope(daily: cpDaily(rows: nil)))
        #expect(known.metrics.first?.usedPercent == 0 && cpAmounts(known)["Spent this cycle"]?.0 == 0)
    }
    // N, I5.5/C5: the percentage is spend ÷ limit × 100; values above 100 are kept raw.
    @Test func percentages() throws {
        #expect(abs(try cpPercent(spent: 410_000) - 82) < 1e-9)
        #expect(abs(try cpPercent(spent: 600_000) - 120) < 1e-9)
        #expect(try cpPercent(spent: 0) == 0)
        #expect(abs(try cpPercent(spent: 500_000) - 100) < 1e-9)
        #expect(abs(try cpPercent(spent: 1, limit: 1) - 100) < 1e-9)
    }
    // N, I5.3 boundary: int32 maximum is accepted per row, sums may exceed it, and the limit may be as large as int32.
    @Test func int32BoundaryAndWideSums() throws {
        #expect(abs(try cpPercent(spent: 2_147_483_647, limit: 2_147_483_647) - 100) < 1e-9)
        let rows = [cpRow(day: cpStart, cents: 2_147_483_647), cpRow(day: cpStart, cents: 2_147_483_647)]
        let snapshot = try cpDecode(cpEnvelope(daily: cpDaily(rows: rows, limit: 2_147_483_647)))
        #expect(abs(try #require(snapshot.metrics.first?.usedPercent) - 200) < 1e-9)
        #expect(cpAmounts(snapshot)["Spent this cycle"]?.0 == Decimal(string: "42949672.94"))
    }
    // N, I5.3: absent spendCents counts as 0; category and totalTokens are ignored whatever they hold.
    @Test func absentCentsAndIgnoredFields() throws {
        let rows: [[String: Any]] = [cpRow(cents: nil), cpRow(cents: 500, category: 7, tokens: -5), cpRow(cents: 500, category: NSNull(), tokens: ["x": 1])]
        let snapshot = try cpDecode(cpEnvelope(daily: cpDaily(rows: rows)))
        #expect(cpAmounts(snapshot)["Spent this cycle"]?.0 == 10)
        let sparse = try cpDecode(cpEnvelope(daily: cpDaily(rows: [["day": cpStart, "spendCents": 100]])))
        #expect(cpAmounts(sparse)["Spent this cycle"]?.0 == 1)
    }
    // N, I5.3 boundary: start <= day < end, with day as a digit string or an integral number.
    @Test func dayBoundaries() throws {
        let start = Int64(cpStart)!, end = Int64(cpEnd)!
        for day in [String(start), String(end - 1), "1700086400000"] as [Any] { _ = try cpDecode(cpEnvelope(daily: cpDaily(rows: [cpRow(day: day)]))) }
        for day in [start, end - 1] as [Any] { _ = try cpDecode(cpEnvelope(daily: cpDaily(rows: [cpRow(day: day)]))) }
        let rejected: [Any] = [String(start - 1), String(end), String(end + cpDay), "0", "abc", "", "-1", "1.5", "1700000000000x",
                               start - 1, end, -1, 1_700_000_000_000.5, true, false, NSNull(), [1], ["a": 1]]
        for day in rejected { #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: [cpRow(day: day)])))) }
        var withoutDay = cpRow(); withoutDay["day"] = nil
        #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: [withoutDay]))))
    }
    // N, C5/I5.3: invalid spendCents rejects the whole envelope, with no partial sums.
    @Test func invalidSpendCentsRejectsEverything() {
        let bad: [Any] = [-1, 1.5, 0.5, true, false, 2_147_483_648, 9_999_999_999, "100", NSNull(), [1], ["a": 1]]
        for cents in bad {
            #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: [cpRow(cents: cents)]))))
            #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: [cpRow(cents: 100), cpRow(cents: cents)]))))
        }
        #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: [cpRow(cents: 100), cpRow(day: "1")]))))
    }
    // N, I5.2 boundary: 4096 rows are accepted, 4097 rejected; rows must be objects; dailySpend must be an array.
    @Test func rowCountAndShape() throws {
        let rows = (0..<4096).map { _ in cpRow(cents: 1) }
        #expect(cpAmounts(try cpDecode(cpEnvelope(daily: cpDaily(rows: rows))))["Spent this cycle"]?.0 == Decimal(string: "40.96"))
        #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: rows + [cpRow(cents: 1)]))))
        for bad in [[1], ["text"], [NSNull()], [[cpRow()]], [cpRow(), 5]] as [[Any]] { #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: bad)))) }
        for bad in [["day": cpStart], "rows", 5, true] as [Any] { #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(rows: bad)))) }
    }
    // N, I5.1: both sections must be objects with valid cycle bounds.
    @Test func sectionsAndCycleAreValidated() throws {
        #expect(cpDecodeFails(cpEnvelope(cycle: nil)) && cpDecodeFails(cpEnvelope(daily: nil)))
        for bad in [[1], "x", 5, NSNull(), true] as [Any] {
            #expect(cpDecodeFails(cpEnvelope(cycle: bad)) && cpDecodeFails(cpEnvelope(daily: bad)))
        }
        let invalid: [[String: Any]] = [cpCycle(cpEnd, cpStart), cpCycle(cpStart, cpStart), cpCycle("x", cpEnd), cpCycle(cpStart, "1.5"), cpCycle(-1, cpEnd),
                                        cpCycle(cpStart, String(Int64(cpStart)! + 62 * cpDay + 1)), cpCycle("12345678901234567", "99999999999999999"),
                                        ["startDateEpochMillis": cpStart], ["endDateEpochMillis": cpEnd], [:]]
        for cycle in invalid { #expect(cpDecodeFails(cpEnvelope(cycle: cycle))) }
        let widest = cpCycle(cpStart, String(Int64(cpStart)! + 62 * cpDay))
        #expect(try cpDecode(cpEnvelope(cycle: widest)).metrics.first?.resetsAt == Date(timeIntervalSince1970: 1_700_000_000 + 62 * 86_400))
        #expect(try cpDecode(cpEnvelope(cycle: cpCycle(1_700_000_000_000, 1_702_592_000_000))).metrics.count == 1)
    }
    // N, I5.6: effectiveLimitCents in any form other than absent, zero or a positive integral number is rejected.
    @Test func invalidLimitForms() {
        for limit in [-1, 1.5, true, false, "500000", [1], ["a": 1]] as [Any] { #expect(cpDecodeFails(cpEnvelope(daily: cpDaily(limit: limit)))) }
    }
    // N, I5: the raw single response or non-JSON data is not an envelope.
    @Test func nonEnvelopeBodiesAreRejected() {
        #expect(cpDecodeFails(cpJSON(cpDaily())) && cpDecodeFails(cpJSON(cpCycle())) && cpDecodeFails(cpJSON([1])))
        #expect(cpDecodeFails(Data("garbage".utf8)) && cpDecodeFails(Data()))
    }
    // I, C5/I5.7: category names, token counts, day buckets and the raw body never enter the snapshot.
    @Test func snapshotEncodingHoldsNoCategoryOrTokenData() throws {
        let rows = [cpRow(day: "1700086400123", cents: 100, category: "zz-category-alpha", tokens: "987654321"),
                    cpRow(day: "1700172800456", cents: 200, category: "zz-category-beta", tokens: 123456789)]
        var daily = cpDaily(rows: rows); daily["categories"] = ["zz-category-alpha", "zz-category-beta"]; daily["unexpectedField"] = "zz-raw-field"
        let snapshot = try cpDecode(cpEnvelope(daily: daily))
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for forbidden in ["zz-category", "987654321", "123456789", "1700086400123", "1700172800456", "zz-raw-field", "unexpectedField", "totalTokens"] {
            #expect(!json.contains(forbidden))
        }
        #expect(snapshot.warnings.isEmpty && snapshot.capabilities.isEmpty)
        let partial = try cpDecode(cpEnvelope(daily: cpDaily(rows: rows, limit: nil)))
        #expect(partial.warnings == ["Spend limit unavailable"])
    }
    // I, C1: Codex and Claude decoding is untouched, and unknown providers still fail.
    @Test func otherProvidersStillDecode() throws {
        let claude = try UsageDecoder.decode(provider: "claude", data: cpJSON(["limits": [["kind": "session", "percent": 30]]]), now: cpNow)
        #expect(claude.providerID == "claude" && claude.metrics.first?.usedPercent == 30)
        let codex = try UsageDecoder.decode(provider: "codex", data: cpJSON(["rate_limit": ["primary_window": ["used_percent": 20]]]), now: cpNow)
        #expect(codex.providerID == "codex")
        #expect(throws: DecodeFailure.self) { try UsageDecoder.decode(provider: "other", data: cpEnvelope(), now: cpNow) }
    }
}
