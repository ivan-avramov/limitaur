import Foundation
import Testing
@testable import LimitaurCore

private func utc(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: text.count == 10 ? text + "T00:00:00Z" : text)!
}
private let mid = utc("2023-11-15T12:00:00Z")
private let december = utc("2023-12-01")

// MARK: - C2 MonthlyResetDay

@Test func resetDayStorageRoundTripsAndRejectsInvalid() throws {
    for day in [MonthlyResetDay.day(1), .day(15), .day(28), .lastDay] {
        #expect(MonthlyResetDay(storage: day.storage) == day)
        let data = try JSONEncoder().encode(day)
        #expect(try JSONDecoder().decode(MonthlyResetDay.self, from: data) == day)
    }
    #expect(MonthlyResetDay.day(15).storage == "15" && MonthlyResetDay.lastDay.storage == "last")
    for bad in ["", "0", "29", "31", "01", "+1", " 1", "1.0", "Last", "-1", "abc"] { #expect(MonthlyResetDay(storage: bad) == nil) }
    #expect(MonthlyResetDay.default == .day(1))
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(MonthlyResetDay.self, from: Data(#""29""#.utf8)) }
}

@Test func resetDayNextResetAndPeriodStart() {
    let cases: [(MonthlyResetDay, String, String, String)] = [
        (.day(1), "2023-11-15T12:00:00Z", "2023-11-01", "2023-12-01"),
        (.day(15), "2023-11-15T12:00:00Z", "2023-11-15", "2023-12-15"),
        (.day(15), "2023-11-14T23:59:59Z", "2023-10-15", "2023-11-15"),
        (.day(28), "2024-02-10T00:00:00Z", "2024-01-28", "2024-02-28"),
        (.lastDay, "2024-01-31T12:00:00Z", "2024-01-31", "2024-02-29"),
        (.lastDay, "2023-01-31T12:00:00Z", "2023-01-31", "2023-02-28"),
        (.lastDay, "2024-02-29T12:00:00Z", "2024-02-29", "2024-03-31"),
        (.lastDay, "2023-04-15T00:00:00Z", "2023-03-31", "2023-04-30"),
        (.day(1), "2023-12-31T23:59:59Z", "2023-12-01", "2024-01-01"),
        (.day(15), "2024-01-10T00:00:00Z", "2023-12-15", "2024-01-15"),
        (.lastDay, "2023-12-31T12:00:00Z", "2023-12-31", "2024-01-31"),
    ]
    for (day, instant, start, next) in cases {
        #expect(day.periodStart(containing: utc(instant)) == utc(start), "\(day) \(instant)")
        #expect(day.nextReset(after: utc(instant)) == utc(next), "\(day) \(instant)")
    }
}

@Test func resetDayAtExactResetAndOutOfRange() {
    #expect(MonthlyResetDay.day(1).periodStart(containing: december) == december)
    #expect(MonthlyResetDay.day(1).nextReset(after: december) == utc("2024-01-01"))
    #expect(MonthlyResetDay.lastDay.nextReset(after: utc("2024-02-29")) == utc("2024-03-31"))
    for n in [0, 29, 31, -3, 1000] {
        #expect(MonthlyResetDay.day(n).nextReset(after: mid) == december)
        #expect(MonthlyResetDay.day(n).periodStart(containing: mid) == utc("2023-11-01"))
        #expect(MonthlyResetDay.day(n).storage == "1")
    }
}

// MARK: - C3 Claude decoder

private let observedSpend = #""spend":{"enabled":true,"percent":15,"severity":"normal","used":{"amount_minor":41000,"currency":"USD","exponent":2},"limit":{"amount_minor":500000,"currency":"USD","exponent":2},"cap":{"money":null,"credits":{"amount_minor":500000,"exponent":2}},"balance":null,"auto_reload":null,"disabled_reason":null}"#
private let observedExtra = #""extra_usage":{"is_enabled":true,"monthly_limit":500000,"used_credits":41000.0,"utilization":8.2,"currency":"USD","decimal_places":2}"#
private func claude(_ body: String, day: MonthlyResetDay = .default) throws -> UsageSnapshot {
    try UsageDecoder.decode(provider: "claude", data: Data(body.utf8), now: mid, spendResetDay: day)
}

@Test func claudeObservedSpendShape() throws {
    let snapshot = try claude("{\"limits\":[],\(observedSpend),\(observedExtra)}")
    #expect(snapshot.metrics == [UsageMetric(id: "spend", label: "Monthly spend", usedPercent: 8.2, resetsAt: december)])
    #expect(snapshot.informationalAmounts == [InformationalAmount(label: "Spent this cycle", amount: 410, currency: "USD"),
                                             InformationalAmount(label: "Spend limit", amount: 5000, currency: "USD")])
    #expect(snapshot.spend == SpendSummary(spent: 410, limit: 5000, currency: "USD", periodEnd: december))
    #expect(snapshot.warnings.isEmpty && !snapshot.partial)
    let fifteenth = try claude("{\(observedSpend),\(observedExtra)}", day: .day(15))
    #expect(fifteenth.metrics.first?.resetsAt == utc("2023-12-15") && fifteenth.spend?.periodEnd == utc("2023-12-15"))
}

@Test func claudeUtilizationFallsBackToSpendPercent() throws {
    let variants = [
        #""extra_usage":{"is_enabled":false,"monthly_limit":500000,"used_credits":41000.0,"utilization":8.2,"currency":"USD"}"#,
        #""extra_usage":{"is_enabled":true,"monthly_limit":400000,"used_credits":41000.0,"utilization":8.2,"currency":"USD"}"#,
        #""extra_usage":{"is_enabled":true,"monthly_limit":500000,"used_credits":41000.5,"utilization":8.2,"currency":"USD"}"#,
        #""extra_usage":{"is_enabled":true,"monthly_limit":500000,"used_credits":41000.0,"utilization":8.2,"currency":"EUR"}"#,
        #""extra_usage":{"is_enabled":true,"monthly_limit":500000,"used_credits":41000.0,"utilization":-1,"currency":"USD"}"#,
        #""extra_usage":{"is_enabled":true,"monthly_limit":500000,"used_credits":41000.0,"utilization":"8.2","currency":"USD"}"#,
        #""extra_usage":null"#,
    ]
    for extra in variants {
        let snapshot = try claude("{\(observedSpend),\(extra)}")
        #expect(snapshot.metrics.map(\.usedPercent) == [15], "\(extra)")
        #expect(!snapshot.partial)
    }
    let noPercent = try claude(#"{"spend":{"enabled":true,"used":{"amount_minor":1,"currency":"USD","exponent":2}}}"#)
    #expect(noPercent.metrics.isEmpty && noPercent.warnings == ["Spend usage unavailable"])
    #expect(noPercent.spend == SpendSummary(spent: Decimal(string: "0.01")!, limit: nil, currency: "USD", periodEnd: december))
}

@Test func claudeSpendLimitWarningsAndCurrency() throws {
    let malformed = try claude(#"{"spend":{"enabled":true,"percent":15,"used":{"amount_minor":41000,"currency":"USD","exponent":2},"limit":{"amount_minor":"x","currency":"USD","exponent":2}}}"#)
    #expect(malformed.warnings == ["Spend limit unavailable"] && malformed.partial)
    #expect(malformed.spend?.limit == nil && malformed.informationalAmounts.map(\.label) == ["Spent this cycle"])
    let extras = try claude(#"{"spend":{"enabled":true,"percent":15,"used":{"amount_minor":41000,"currency":"USD","exponent":2},"cap":{"amount_minor":1},"balance":{"amount_minor":2,"currency":"USD","exponent":2},"auto_reload":{"x":1}}}"#)
    #expect(extras.warnings.isEmpty && !extras.partial)
    let euro = try claude(#"{"spend":{"enabled":true,"percent":15,"used":{"amount_minor":41000,"currency":"USD","exponent":2},"limit":{"amount_minor":500000,"currency":"EUR","exponent":2}}}"#)
    #expect(euro.spend == SpendSummary(spent: 410, limit: nil, currency: "USD", periodEnd: december))
    #expect(euro.informationalAmounts.last == InformationalAmount(label: "Spend limit", amount: 5000, currency: "EUR"))
    let disabled = try claude("{\"limits\":[],\"spend\":{\"enabled\":false,\"percent\":15,\"used\":{\"amount_minor\":41000,\"currency\":\"USD\",\"exponent\":2}},\(observedExtra)}")
    #expect(disabled.metrics.isEmpty && disabled.informationalAmounts.isEmpty && disabled.spend == nil && !disabled.partial)
    let extraOnly = try claude("{\"limits\":[],\(observedExtra)}")
    #expect(extraOnly.metrics.map(\.id) == ["extra_usage"] && extraOnly.spend == nil)
    #expect(extraOnly.warnings == ["Extra usage amount units unavailable"])
}

// MARK: - C4 Cursor decoder

@Test func cursorFillsSpendSummary() throws {
    let cycle = #"{"startDateEpochMillis":"1698796800000","endDateEpochMillis":"1701388800000"}"#
    func decode(_ spend: String) throws -> UsageSnapshot {
        try UsageDecoder.decode(provider: "cursor", data: Data(#"{"billingCycle":\#(cycle),"dailySpendByCategory":\#(spend)}"#.utf8), now: mid)
    }
    let limited = try decode(#"{"dailySpend":[{"day":"1698796800000","spendCents":4100}],"effectiveLimitCents":500000}"#)
    #expect(limited.spend == SpendSummary(spent: 41, limit: 5000, currency: "USD", periodEnd: december))
    #expect(limited.metrics.map(\.label) == ["Monthly spend"] && limited.informationalAmounts.map(\.label) == ["Spent this cycle", "Spend limit"])
    let unlimited = try decode(#"{"dailySpend":[{"day":"1698796800000","spendCents":4100}]}"#)
    #expect(unlimited.spend == SpendSummary(spent: 41, limit: nil, currency: "USD", periodEnd: december))
    #expect(unlimited.metrics.isEmpty && unlimited.warnings == ["Spend limit unavailable"])
    #expect(try decode("{}").spend == nil)
    #expect(try decode(#"{"effectiveLimitCents":0}"#).spend == nil)
}

@Test func snapshotsWithoutSpendStillDecode() throws {
    let old = UsageSnapshot(providerID: "codex", accountID: "a", accountLabel: "A", fetchedAt: mid, metrics: [])
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
    object["spend"] = nil
    let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded == old && decoded.spend == nil)
}

// MARK: - C5 sharedBudget

private let config = SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["claude", "cursor"], resetDay: .day(1))
private let mains: [ProviderID: String] = ["claude": "claude-default", "cursor": "cursor-default"]
private func row(_ provider: ProviderID, id: String? = nil, spent: Decimal? = nil, currency: String = "USD",
                 periodEnd: Date? = december, health: Health = .healthy, message: String? = nil,
                 deadline: TimeInterval? = 190, generation: Int = 1, metrics: [UsageMetric] = []) -> ProfileDisplay {
    let snapshot = UsageSnapshot(providerID: provider, accountID: AccountID("acct-" + provider.rawValue), accountLabel: "Default",
                                 fetchedAt: mid, metrics: metrics,
                                 spend: spent.map { SpendSummary(spent: $0, limit: 5000, currency: currency, periodEnd: periodEnd) })
    return ProfileDisplay(profile: AccountProfile(id: id ?? provider.rawValue + "-default", providerID: provider, label: "Default",
                                                  source: provider == "claude" ? .claudeDefaultDiscovery : .cursorDefaultDiscovery),
                          snapshot: snapshot, health: health, message: message, fetchedAge: 0,
                          freshnessDeadline: deadline, snapshotGeneration: generation)
}
private func budget(_ rows: [ProfileDisplay], _ config: SharedBudgetConfig = config, mains: [ProviderID: String] = mains,
                    wall: Date = mid, mono: TimeInterval = 100) -> SharedBudgetState? {
    sharedBudget(config, rows: rows, mainProfileIDs: mains, wallNow: wall, monotonicNow: mono)
}

@Test func sharedBudgetSuccessTrace() throws {
    let state = try #require(budget([row("claude", spent: 410, deadline: 190), row("cursor", spent: 41, deadline: 170)]))
    #expect(state.total == 451 && abs(state.usedPercent! - 9.02) < 1e-9)
    #expect(state.resetsAt == december && state.warning == nil && state.freshnessDeadline == 170)
    #expect(state.members == [SharedBudgetMember(provider: "claude", spent: 410, problem: nil),
                              SharedBudgetMember(provider: "cursor", spent: 41, problem: nil)])
    let partial = try #require(budget([row("claude", spent: 410, health: .partial), row("cursor", spent: 41)]))
    #expect(partial.total == 451)
}

@Test func sharedBudgetProblemsInOrder() throws {
    func problem(_ cursor: ProfileDisplay?, mains: [ProviderID: String] = mains) -> String? {
        let state = budget([row("claude", spent: 410)] + (cursor.map { [$0] } ?? []), mains: mains)
        return state?.members.last?.problem
    }
    #expect(problem(row("cursor", spent: 41, periodEnd: nil, health: .throttled)) == "Different billing period")
    #expect(problem(row("cursor", spent: 41, health: .throttled)) == nil)   // H7
    #expect(problem(row("cursor", spent: 41, health: .throttled, deadline: 100)) == "Stale")
    #expect(problem(row("cursor", spent: nil, health: .stale)) == "Stale")
    #expect(problem(row("cursor", spent: nil, health: .unauthenticated)) == "Needs sign-in")
    #expect(problem(row("cursor", spent: nil, health: .unavailable, message: "Connecting account")) == "Connecting…")
    #expect(problem(row("cursor", spent: 41, deadline: 100)) == "Stale")
    #expect(problem(row("cursor", spent: 41, deadline: nil)) == "Stale")
    #expect(problem(row("cursor", spent: nil, currency: "EUR")) == "No spend reported")
    #expect(problem(row("cursor", spent: 41, currency: "EUR", periodEnd: nil)) == "Different currency")
    #expect(problem(row("cursor", spent: 41, periodEnd: utc("2023-12-15"))) == "Different billing period")
    #expect(problem(row("cursor", spent: 41, periodEnd: nil)) == "Different billing period")
    #expect(problem(nil) == "Connecting…")
    #expect(problem(row("cursor", spent: 41), mains: ["claude": "claude-default"]) == "Off")
    let mismatch = try #require(budget([row("claude", spent: 410), row("cursor", spent: 41, periodEnd: utc("2023-12-15"))]))
    #expect(mismatch.total == nil && mismatch.usedPercent == nil && mismatch.freshnessDeadline == nil)
    #expect(mismatch.warning == "Total unavailable: Cursor Different billing period")
    let stale = try #require(budget([row("claude", spent: 410, health: .stale), row("cursor", spent: 41, health: .throttled)]))
    #expect(stale.warning == "Total unavailable: Claude Stale" && stale.members[0].spent == nil)
}

@Test func sharedBudgetAmountAndConfigRules() throws {
    let rows = [row("claude", spent: 410), row("cursor", spent: 41)]
    for amount in [nil, Decimal(0), Decimal(-5)] {
        var unset = config; unset.amount = amount
        let state = try #require(budget(rows, unset))
        #expect(state.total == 451 && state.usedPercent == nil && state.warning == "Set the budget amount in Settings")
    }
    var both = config; both.amount = nil
    #expect(budget([row("claude", spent: 410)], both)?.warning == "Total unavailable: Cursor Connecting…")
    var off = config; off.enabled = false
    #expect(budget(rows, off) == nil)
    var empty = config; empty.members = []
    #expect(budget(rows, empty) == nil)
    var claudeOnly = config; claudeOnly.members = ["claude"]
    #expect(budget(rows, claudeOnly)?.total == 410)
    var fifteenth = config; fifteenth.resetDay = .day(15)
    #expect(budget(rows, fifteenth)?.resetsAt == utc("2023-12-15"))
    #expect(budget(rows, fifteenth)?.warning == "Total unavailable: Claude Different billing period")
}

@Test func sharedBudgetCountsOnlyMainAccounts() throws {
    let rows = [row("claude", id: "claude-work", spent: 9000), row("claude", spent: 410), row("cursor", spent: 41),
                row("cursor", id: "cursor-other", spent: 7)]
    #expect(budget(rows)?.total == 451)
    #expect(budget(rows, mains: ["claude": "claude-work", "cursor": "cursor-default"])?.total == 9041)
}

// MARK: - C6 projectDisplay with a budget

private func display(_ percents: [(ProviderID, Double)]) -> MonitorDisplay {
    var rows: [ProfileDisplay] = [], candidates: [PresentationCandidate] = []
    for (index, (provider, percent)) in percents.enumerated() {
        let metric = UsageMetric(id: "spend", label: "Monthly spend", usedPercent: percent, resetsAt: december)
        let r = row(provider, spent: provider == "claude" ? 410 : 41, generation: index + 1, metrics: [metric])
        rows.append(r)
        candidates.append(PresentationCandidate(metric: RankedMetric(snapshot: r.snapshot!, metric: metric),
                                                freshnessDeadline: 190, snapshotGeneration: index + 1))
    }
    candidates.sort { ranksBefore($0.metric, $1.metric) }
    return MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil)
}
private func project(_ display: MonitorDisplay, budget: SharedBudgetState?, count: Int = 3,
                     wall: Date = mid, mono: TimeInterval = 100) -> PresentationState {
    var observations: [Int: SnapshotExpirations] = [:]
    return projectDisplay(display, count: count, wallNow: wall, monotonicNow: mono, observations: &observations, budget: budget)
}

@Test func budgetCandidateRanksAmongMembers() throws {
    let value = display([("claude", 12), ("cursor", 5)])
    let state = try #require(budget(value.profiles))
    let projected = project(value, budget: state)
    #expect(projected.selected.map(\.providerID) == ["claude", "budget", "cursor"])
    let shared = projected.selected[1]
    #expect(shared.accountID == "shared" && shared.accountLabel == "Shared budget" && shared.fetchedAt == mid)
    #expect(shared.metric == UsageMetric(id: "spend:shared", label: "Shared budget", usedPercent: state.usedPercent, resetsAt: december))
    #expect(projected.accessibilitySummary.contains("budget, Shared budget, Shared budget, 9.02 percent"))
    #expect(project(value, budget: state, count: 1).selected.map(\.providerID) == ["claude"])
    #expect(project(value, budget: state, count: 2).selected.map(\.providerID) == ["claude", "budget"])
    var exact = config; exact.amount = 4510
    let tied = display([("claude", 10), ("cursor", 10)])
    let ten = try #require(budget(tied.profiles, exact))
    #expect(ten.usedPercent == 10)
    #expect(project(tied, budget: ten).selected.map(\.providerID) == ["budget", "claude", "cursor"])
}

@Test func budgetCandidateLeavesAtDeadlineAndReset() throws {
    let value = display([("claude", 12), ("cursor", 5)])
    let base = try #require(budget(value.profiles))
    let early = SharedBudgetState(config: base.config, members: base.members, total: base.total, usedPercent: base.usedPercent,
                                  resetsAt: base.resetsAt, freshnessDeadline: 150, warning: nil)
    #expect(project(value, budget: early, mono: 149.9).selected.contains { $0.providerID == "budget" })
    #expect(!project(value, budget: early, mono: 150).selected.contains { $0.providerID == "budget" })
    let soon = SharedBudgetState(config: base.config, members: base.members, total: base.total, usedPercent: base.usedPercent,
                                 resetsAt: mid.addingTimeInterval(60), freshnessDeadline: 190, warning: nil)
    #expect(!project(value, budget: soon, wall: mid.addingTimeInterval(60)).selected.contains { $0.providerID == "budget" })
    let unknown = SharedBudgetState(config: base.config, members: base.members, total: nil, usedPercent: nil,
                                    resetsAt: base.resetsAt, freshnessDeadline: nil, warning: "x")
    #expect(project(value, budget: unknown).selected.map(\.providerID) == ["claude", "cursor"])
    let plain = project(value, budget: nil)
    #expect(plain.selected.map(\.providerID) == ["claude", "cursor"] && !plain.accessibilitySummary.contains("Shared budget"))
    var observations: [Int: SnapshotExpirations] = [:]
    let legacy = projectDisplay(value, count: 3, wallNow: mid, monotonicNow: 100, observations: &observations)
    #expect(legacy.selected == plain.selected && legacy.accessibilitySummary == plain.accessibilitySummary)
}

@Test func budgetCandidateIsStableAsTheWallClockAdvances() throws {   // H1
    let value = display([("claude", 12), ("cursor", 5)])
    func selected(_ wall: Date, _ mono: TimeInterval) throws -> [RankedMetric] {
        project(value, budget: try #require(budget(value.profiles, wall: wall, mono: mono)), wall: wall, mono: mono).selected
    }
    let first = try selected(mid, 100), later = try selected(mid.addingTimeInterval(30), 130)
    #expect(first == later && first.contains { $0.providerID == "budget" && $0.fetchedAt == mid })
}

@Test func budgetReadsAliasOwnersAndNominalDeadlines() throws {   // H2, H6
    let owner = row("claude", id: "claude-owner", spent: 410)
    let alias = ProfileDisplay(profile: AccountProfile(id: "claude-default", providerID: "claude", label: "Default",
                                                       source: .claudeDefaultDiscovery),
                               snapshot: nil, health: .healthy, message: "Alias of Owner", fetchedAge: 0, aliasOf: "claude-owner")
    #expect(budget([alias, owner, row("cursor", spent: 41)])?.total == 451)
    #expect(budget([alias, row("cursor", spent: 41)])?.members.first?.problem == "Connecting…")
    let value = display([("claude", 12), ("cursor", 5)])
    let nominal = MonitorDisplay(profiles: value.profiles, candidates: value.candidates.map {
        PresentationCandidate(metric: $0.metric, freshnessDeadline: 190, snapshotGeneration: $0.snapshotGeneration,
                              nominalDeadline: $0.metric.providerID == "claude" ? 120 : 160)
    }, revision: 1, nextDisplayDeadline: nil)
    let state = try #require(budget(value.profiles))
    #expect(budgetCandidate(state, candidates: nominal.candidates, wallNow: mid, monotonicNow: 100)?.nominalDeadline == 120)
    #expect(budgetCandidate(state, candidates: [], wallNow: mid, monotonicNow: 100)?.nominalDeadline == 190)
}

@Test func budgetConfigurationIsValidated() {   // H3
    let loaded = SharedBudgetConfig(enabled: true, amount: -1, currency: "USD", members: ["cursor", "codex", "cursor", "claude"],
                                    resetDay: .day(5)).validated
    #expect(loaded == SharedBudgetConfig(enabled: true, amount: nil, currency: "USD", members: ["cursor", "claude"], resetDay: .day(5)))
    #expect(SharedBudgetConfig(enabled: true, amount: 5, currency: "EUR", members: ["claude"], resetDay: .day(5)).validated
            == SharedBudgetConfig(enabled: false, amount: nil, currency: "USD", members: ["claude", "cursor"], resetDay: .default))
    var twice = config; twice.members = ["claude", "claude", "cursor"]
    #expect(budget([row("claude", spent: 410), row("cursor", spent: 41)], twice)?.total == 451)
}

// MARK: - C8 provider code

@Test func budgetProviderCodeIsDistinguishable() {
    #expect(providerCodes["budget"] == "SB" && providerGlyph(for: "budget") == "SB")
    #expect(providerName("budget") == "Shared budget")
    for (provider, code) in providerCodes where provider != "budget" {
        #expect(providerCodesAreDistinguishable("SB", code), "\(provider)")
    }
}

// MARK: - I4 Monitor

private struct BIClock: MonitorClock {
    func wallNow() -> Date { mid }
    func monotonicNow() -> TimeInterval { 100 }
}
private struct BIKeychain: KeychainReading {
    func claudeCredential() -> KeychainResult {
        .found(Data(#"{"claudeAiOauth":{"accessToken":"invented-budget","expiresAt":1900000000000}}"#.utf8))
    }
}
private struct BINoFiles: CredentialFileReading {
    func read(path: String) throws -> Data { throw CredentialFailure.missing }
}
private struct BITransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(status: 200, headers: [:], body: Data("{\(observedSpend),\(observedExtra)}".utf8))
    }
}

@Test func monitorDecodesClaudeSpendWithConfiguredResetDay() async {
    func resetAfterFetch(_ day: MonthlyResetDay?) async -> Date? {
        let monitor = Monitor(clock: BIClock(), credentials: CredentialStore(files: BINoFiles(), keychain: BIKeychain()),
                              transport: BITransport())
        if let day { await monitor.setSpendResetDay(day, for: "claude") }
        await monitor.setProfiles([AccountProfile(id: "claude-default", providerID: "claude", label: "Default",
                                                  source: .claudeDefaultDiscovery)])
        await monitor.settle()
        let snapshot = await monitor.display().profiles.first?.snapshot
        await monitor.stop()
        return snapshot?.spend?.periodEnd
    }
    #expect(await resetAfterFetch(nil) == december)
    #expect(await resetAfterFetch(.day(15)) == utc("2023-12-15"))
    #expect(await resetAfterFetch(.lastDay) == utc("2023-11-30"))
}
