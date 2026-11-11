import Foundation

/// A monthly reset at 00:00 UTC on a calendar day. Stored as "1"…"28" or "last".
public enum MonthlyResetDay: Codable, Sendable, Equatable {
    case day(Int) /* 1...28 */; case lastDay
}

public extension MonthlyResetDay {
    static let `default`: MonthlyResetDay = .day(1)

    init?(storage: String) {
        if storage == "last" { self = .lastDay; return }
        guard let day = Int(storage), (1...28).contains(day), String(day) == storage else { return nil }
        self = .day(day)
    }

    var storage: String {
        switch self {
        case .lastDay: "last"
        case .day(let n): String((1...28).contains(n) ? n : 1)
        }
    }

    /// The earliest reset strictly after `instant`.
    func nextReset(after instant: Date) -> Date {
        let (year, month) = Self.month(of: instant)
        let current = reset(year: year, month: month)
        return current > instant ? current : reset(year: year, month: month + 1)
    }

    /// The latest reset at or before `instant`.
    func periodStart(containing instant: Date) -> Date {
        let (year, month) = Self.month(of: instant)
        let current = reset(year: year, month: month)
        return current <= instant ? current : reset(year: year, month: month - 1)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func month(of instant: Date) -> (Int, Int) {
        let parts = calendar.dateComponents([.year, .month], from: instant)
        return (parts.year ?? 1970, parts.month ?? 1)
    }

    /// 00:00 UTC on this day of the month; `month` may run one outside 1…12.
    private func reset(year: Int, month: Int) -> Date {
        let calendar = Self.calendar
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let day: Int
        switch self {
        case .lastDay: day = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        case .day(let n): day = (1...28).contains(n) ? n : 1
        }
        return first.addingTimeInterval(TimeInterval(day - 1) * 86400)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let day = MonthlyResetDay(storage: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid reset day")
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
}

/// The user's own monthly budget across providers; no provider enforces it.
public struct SharedBudgetConfig: Codable, Sendable, Equatable {
    public var enabled: Bool; public var amount: Decimal?; public var currency: String   // "USD"
    public var members: [ProviderID]; public var resetDay: MonthlyResetDay
    public init(enabled: Bool, amount: Decimal?, currency: String, members: [ProviderID], resetDay: MonthlyResetDay) {
        self.enabled = enabled; self.amount = amount; self.currency = currency
        self.members = members; self.resetDay = resetDay
    }

    /// A loaded configuration: known members once each in first-seen order, a positive amount, and USD only.
    public var validated: SharedBudgetConfig {
        guard currency == "USD" else { return SharedBudgetConfig(enabled: false, amount: nil, currency: "USD",
                                                                 members: ["claude", "cursor"], resetDay: .default) }
        var next = self
        next.members = members.uniqued.filter { $0 == "claude" || $0 == "cursor" }
        if let amount, !(amount > 0) { next.amount = nil }
        return next
    }
}

private extension Array where Element == ProviderID {
    var uniqued: [ProviderID] { reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
}

public struct SharedBudgetMember: Sendable, Equatable {
    public let provider: ProviderID; public let spent: Decimal?; public let problem: String?
    public init(provider: ProviderID, spent: Decimal?, problem: String?) {
        self.provider = provider; self.spent = spent; self.problem = problem
    }
}

public struct SharedBudgetState: Sendable, Equatable {
    public let config: SharedBudgetConfig; public let members: [SharedBudgetMember]
    public let total: Decimal?; public let usedPercent: Double?; public let resetsAt: Date
    public let freshnessDeadline: TimeInterval?; public let warning: String?
    /// The usable members' snapshots, which date the budget and match its ranking candidates.
    public let memberSnapshots: [UsageSnapshot]
    public init(config: SharedBudgetConfig, members: [SharedBudgetMember], total: Decimal?, usedPercent: Double?,
                resetsAt: Date, freshnessDeadline: TimeInterval?, warning: String?, memberSnapshots: [UsageSnapshot] = []) {
        self.config = config; self.members = members; self.total = total; self.usedPercent = usedPercent
        self.resetsAt = resetsAt; self.freshnessDeadline = freshnessDeadline; self.warning = warning
        self.memberSnapshots = memberSnapshots
    }
}

/// Adds each member's reported spend from its main account's projected row. A total is shown only
/// when every member is fresh and reports spend in the budget's currency for the budget's period.
/// `mainProfileIDs` holds only enabled main accounts, so a missing entry reads "Off".
/// An alias reads its owner's row; a rate-limited row still counts while fresh.
public func sharedBudget(_ config: SharedBudgetConfig, rows: [ProfileDisplay], mainProfileIDs: [ProviderID: String],
                         wallNow: Date, monotonicNow: TimeInterval) -> SharedBudgetState? {
    guard config.enabled, !config.members.isEmpty else { return nil }
    let resetsAt = config.resetDay.nextReset(after: wallNow)
    var deadlines: [TimeInterval] = [], snapshots: [UsageSnapshot] = []
    let members = config.members.uniqued.map { provider -> SharedBudgetMember in
        func problem(_ text: String) -> SharedBudgetMember { SharedBudgetMember(provider: provider, spent: nil, problem: text) }
        func row(_ id: String) -> ProfileDisplay? { rows.first { $0.profile.id == id && $0.profile.providerID == provider } }
        guard let id = mainProfileIDs[provider] else { return problem("Off") }
        guard let main = row(id) else { return problem("Connecting…") }
        guard main.profile.enabled else { return problem("Off") }
        guard let row = main.aliasOf.map(row) ?? main else { return problem("Connecting…") }
        let status = AccountStatus(row: row)
        guard [.healthy, .partial, .throttled].contains(status) else { return problem(status.label) }
        guard let deadline = row.freshnessDeadline, monotonicNow < deadline else { return problem(AccountStatus.stale.label) }
        guard let snapshot = row.snapshot, let spend = snapshot.spend else { return problem("No spend reported") }
        guard spend.currency == config.currency else { return problem("Different currency") }
        guard spend.periodEnd == resetsAt else { return problem("Different billing period") }
        deadlines.append(deadline); snapshots.append(snapshot)
        return SharedBudgetMember(provider: provider, spent: spend.spent, problem: nil)
    }
    let failing = members.first { $0.spent == nil }
    let total = failing == nil ? members.compactMap(\.spent).reduce(0, +) : nil
    var percent: Double?, warning: String?
    if let failing {
        warning = "Total unavailable: \(providerName(failing.provider)) \(failing.problem ?? "")"
    } else if let total, let amount = config.amount, amount > 0 {
        percent = NSDecimalNumber(decimal: total / amount * 100).doubleValue
    } else {
        warning = "Set the budget amount in Settings"
    }
    return SharedBudgetState(config: config, members: members, total: total, usedPercent: percent, resetsAt: resetsAt,
                             freshnessDeadline: total == nil ? nil : deadlines.min(), warning: warning,
                             memberSnapshots: total == nil ? [] : snapshots)
}

/// The budget's ranking candidate while its percent is known, fresh and before its reset. It is dated by its
/// earliest member snapshot, so unchanged data projects equally, and is as fresh as its members' candidates.
func budgetCandidate(_ budget: SharedBudgetState?, candidates: [PresentationCandidate],
                     wallNow: Date, monotonicNow: TimeInterval) -> PresentationCandidate? {
    guard let budget, let percent = budget.usedPercent, let deadline = budget.freshnessDeadline,
          monotonicNow < deadline, wallNow < budget.resetsAt else { return nil }
    let metric = UsageMetric(id: "spend:shared", label: "Shared budget", usedPercent: percent, resetsAt: budget.resetsAt)
    let snapshot = UsageSnapshot(providerID: "budget", accountID: "shared", accountLabel: "Shared budget",
                                 fetchedAt: budget.memberSnapshots.map(\.fetchedAt).min() ?? wallNow, metrics: [metric])
    let nominal = candidates.filter { candidate in
        budget.memberSnapshots.contains { $0.providerID == candidate.metric.providerID && $0.accountID == candidate.metric.accountID }
    }.compactMap(\.nominalDeadline).min()
    return PresentationCandidate(metric: RankedMetric(snapshot: snapshot, metric: metric),
                                 freshnessDeadline: deadline, snapshotGeneration: nil, nominalDeadline: nominal ?? deadline)
}
