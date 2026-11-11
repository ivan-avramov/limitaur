import Foundation
import Testing
@testable import LimitaurCore

// Shared helpers for the shared-budget tests. Every value is synthetic.
func sbUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}
let sbNow = sbUTC(2026, 11, 10, 12)

/// The specification's observed shape; `overrides` replace keys, `NSNull()` writes a JSON null.
func sbSpend(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var spend: [String: Any] = [
        "enabled": true, "percent": 15, "severity": "normal",
        "used": ["amount_minor": 41000, "currency": "USD", "exponent": 2],
        "limit": ["amount_minor": 500000, "currency": "USD", "exponent": 2],
        "cap": ["money": NSNull(), "credits": ["amount_minor": 500000, "exponent": 2]],
        "balance": NSNull(), "auto_reload": NSNull(), "disabled_reason": NSNull()]
    spend.merge(overrides) { $1 }
    return spend
}
func sbExtra(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var extra: [String: Any] = ["is_enabled": true, "monthly_limit": 500000, "used_credits": 41000.0,
                                "utilization": 8.2, "currency": "USD", "decimal_places": 2]
    extra.merge(overrides) { $1 }
    return extra
}
/// A full usage response in the modern envelope (see Fixtures/claude-modern.json) with the given spend and extra_usage.
func sbClaudeBody(spend: Any? = sbSpend(), extra: Any? = sbExtra()) -> Data {
    var root: [String: Any] = ["limits": [["kind": "session", "group": "all", "percent": 25,
                                           "resets_at": "2026-11-10T15:00:00.000+00:00", "is_active": true]],
                               "five_hour": ["utilization": 1]]
    if let spend { root["spend"] = spend }
    if let extra { root["extra_usage"] = extra }
    return try! JSONSerialization.data(withJSONObject: root)
}
func sbDecodeClaude(_ data: Data = sbClaudeBody(), day: MonthlyResetDay? = nil) throws -> UsageSnapshot {
    if let day {
        return try UsageDecoder.decode(provider: "claude", data: data, accountID: "acct", accountLabel: "Label", now: sbNow, spendResetDay: day)
    }
    return try UsageDecoder.decode(provider: "claude", data: data, accountID: "acct", accountLabel: "Label", now: sbNow)
}
func sbAmounts(_ snapshot: UsageSnapshot) -> [String: InformationalAmount] {
    Dictionary(uniqueKeysWithValues: snapshot.informationalAmounts.map { ($0.label, $0) })
}

// Shared-budget rows: wall clock 2023-11-15, monotonic 100, every cycle ends 2023-12-01.
let sbWall = sbUTC(2023, 11, 15), sbCycleEnd = sbUTC(2023, 12, 1), sbMono: TimeInterval = 100
let sbMains: [ProviderID: String] = ["claude": "claude-default", "cursor": "cursor-default"]

func sbSummary(_ spent: Decimal, limit: Decimal? = 5000, currency: String = "USD", end: Date? = sbCycleEnd) -> SpendSummary {
    SpendSummary(spent: spent, limit: limit, currency: currency, periodEnd: end)
}
func sbRow(_ provider: ProviderID, id: String? = nil, health: Health = .healthy, spend: SpendSummary?,
           deadline: TimeInterval? = 190, enabled: Bool = true) -> ProfileDisplay {
    let id = id ?? provider.rawValue + "-default"
    let profile = AccountProfile(id: id, providerID: provider, label: "Default",
                                 source: provider == "cursor" ? .cursorDefaultDiscovery : .claudeDefaultDiscovery, enabled: enabled)
    let snapshot = UsageSnapshot(providerID: provider, accountID: AccountID(id), accountLabel: "Default", fetchedAt: sbWall,
                                 metrics: [], spend: spend)
    return ProfileDisplay(profile: profile, snapshot: snapshot, health: health, message: nil, fetchedAge: 0,
                          freshnessDeadline: deadline, snapshotGeneration: 1)
}
func sbConfig(enabled: Bool = true, amount: Decimal? = 5000, currency: String = "USD",
              members: [ProviderID] = ["claude", "cursor"], day: MonthlyResetDay = .default) -> SharedBudgetConfig {
    SharedBudgetConfig(enabled: enabled, amount: amount, currency: currency, members: members, resetDay: day)
}
func sbBudget(_ rows: [ProfileDisplay], _ config: SharedBudgetConfig = sbConfig(), mains: [ProviderID: String] = sbMains,
              mono: TimeInterval = sbMono) -> SharedBudgetState? {
    sharedBudget(config, rows: rows, mainProfileIDs: mains, wallNow: sbWall, monotonicNow: mono)
}
/// The success trace: Claude 410.00 and Cursor 41.00, both healthy.
func sbTracedRows() -> [ProfileDisplay] {
    [sbRow("claude", spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41), deadline: 150)]
}
