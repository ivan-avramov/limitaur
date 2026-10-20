import Foundation

public struct ProviderID: Hashable, Codable, Sendable, Comparable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct AccountID: Hashable, Codable, Sendable, Comparable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum KnownState: String, Codable, Sendable { case known, unknown, unavailable, inapplicable }

public struct QuotaObservation: Codable, Sendable, Equatable {
    public var usedPercent: Double
    public var resetsAt: Date?
    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }
}

public struct UsageMetric: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var usedPercent: Double?
    public var resetsAt: Date?
    public var windowDuration: TimeInterval?
    public var scopeLabel: String?
    public var conflictingObservations: [QuotaObservation]?
    public init(id: String, label: String, usedPercent: Double?, resetsAt: Date? = nil,
                windowDuration: TimeInterval? = nil, scopeLabel: String? = nil,
                conflictingObservations: [QuotaObservation]? = nil) {
        self.id = id; self.label = label; self.usedPercent = validatedPercent(usedPercent)
        self.resetsAt = resetsAt; self.windowDuration = windowDuration; self.scopeLabel = scopeLabel
        self.conflictingObservations = conflictingObservations
    }
}

public struct CreditBalance: Codable, Sendable, Equatable {
    public var label: String
    public var remaining: Decimal?
    public var currency: String?
    public var expiresAt: Date?
    public var unlimited: Bool
    public var state: KnownState
    public init(label: String, remaining: Decimal?, currency: String? = nil, expiresAt: Date? = nil,
                unlimited: Bool = false, state: KnownState = .known) {
        self.label = label; self.remaining = remaining; self.currency = currency
        self.expiresAt = expiresAt; self.unlimited = unlimited; self.state = state
    }
}

public struct InformationalAmount: Codable, Sendable, Equatable {
    public var label: String
    public var amount: Decimal
    public var currency: String
    public init(label: String, amount: Decimal, currency: String) {
        self.label = label; self.amount = amount; self.currency = currency
    }
}

public struct ResetCredit: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var expiresAt: Date?
    public init(id: String, label: String, expiresAt: Date?) {
        self.id = id; self.label = label; self.expiresAt = expiresAt
    }
}

public struct ResetCreditSummary: Codable, Sendable, Equatable {
    public var availableCount: Int?
    public var applicableCount: Int?
    public var details: [ResetCredit]?
    public init(availableCount: Int?, applicableCount: Int?, details: [ResetCredit]?) {
        self.availableCount = availableCount; self.applicableCount = applicableCount; self.details = details
    }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var providerID: ProviderID
    public var accountID: AccountID
    public var accountLabel: String
    public var fetchedAt: Date
    public var metrics: [UsageMetric]
    public var balances: [CreditBalance]
    public var informationalAmounts: [InformationalAmount]
    public var resetCredits: ResetCreditSummary?
    public var capabilities: [String]
    public var partial: Bool
    public var warnings: [String]
    public init(providerID: ProviderID, accountID: AccountID, accountLabel: String, fetchedAt: Date,
                metrics: [UsageMetric], balances: [CreditBalance] = [], informationalAmounts: [InformationalAmount] = [], resetCredits: ResetCreditSummary? = nil,
                capabilities: [String] = [], partial: Bool = false, warnings: [String] = []) {
        self.providerID = providerID; self.accountID = accountID; self.accountLabel = accountLabel
        self.fetchedAt = fetchedAt; self.metrics = metrics; self.balances = balances
        self.informationalAmounts = informationalAmounts
        self.resetCredits = resetCredits; self.capabilities = capabilities
        self.partial = partial; self.warnings = warnings
    }
}

public enum Severity: String, Codable, Sendable { case normal, warning, critical, unknown }
public func validatedPercent(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
}
public func severity(_ value: Double?) -> Severity {
    guard let value = validatedPercent(value) else { return .unknown }
    if value > 95 { return .critical }
    if value > 80 { return .warning }
    return .normal
}
public func ringFill(_ value: Double?) -> Double? { validatedPercent(value).map { min($0 / 100, 1) } }

/// DateFormatter's supported calendar range is years 1 through 9999. Keep
/// provider-supplied timestamps outside that range out of both countdowns and
/// localized absolute-date formatting.
public func displayableResetDate(_ date: Date) -> Date? {
    let timestamp = date.timeIntervalSince1970
    guard timestamp.isFinite, timestamp >= -62_135_596_800,
          timestamp <= 253_402_300_799 else { return nil }
    return date
}

public func resetCountdownText(resetAt date: Date, now: Date) -> String {
    guard displayableResetDate(date) != nil, now.timeIntervalSince1970.isFinite else {
        return "reset time unavailable"
    }
    let seconds = date.timeIntervalSince(now)
    guard seconds.isFinite else { return "reset time unavailable" }
    if seconds <= 0 { return "reset due" }
    if seconds < 3600 { return "in \(Int(ceil(seconds / 60)))m" }
    guard seconds / 3600 < Double(Int.max) else { return "reset time unavailable" }
    return "in \(Int(ceil(seconds / 3600)))h"
}

/// The UI's cadence is never below the scheduler's 30-second minimum.
public func pollInterval(jitter: Double) -> TimeInterval {
    guard jitter.isFinite else { return 30 }
    return 30 + min(1.5, max(0, jitter))
}

public struct RankedMetric: Sendable, Equatable {
    public var providerID: ProviderID
    public var accountID: AccountID
    public var accountLabel: String
    public var metric: UsageMetric
    public var fetchedAt: Date
    public init(snapshot: UsageSnapshot, metric: UsageMetric) {
        providerID = snapshot.providerID; accountID = snapshot.accountID
        accountLabel = snapshot.accountLabel; self.metric = metric; fetchedAt = snapshot.fetchedAt
    }
}

public enum Health: String, Codable, Sendable { case healthy, partial, unauthenticated, unavailable, throttled, failed, stale }

public func indicatorCount(_ value: Int?) -> Int {
    guard let value, (1...8).contains(value) else { return 3 }
    return value
}

public func rankMetrics(_ snapshots: [UsageSnapshot], wallNow: Date,
                        elapsedAges: [String: TimeInterval] = [:], health: [String: Health] = [:],
                        maximumCount: Int = 3) -> [RankedMetric] {
    var seen = Set<String>()
    var all: [RankedMetric] = []
    for snapshot in snapshots {
        let key = snapshot.providerID.rawValue + "\u{1f}" + snapshot.accountID.rawValue
        let age = elapsedAges[key] ?? max(0, wallNow.timeIntervalSince(snapshot.fetchedAt))
        guard age >= 0, age < 90, health[key] != .stale else { continue }
        for metric in snapshot.metrics {
            guard validatedPercent(metric.usedPercent) != nil,
                  metric.resetsAt.map({ wallNow < $0 }) ?? true else { continue }
            let identity = key + "\u{1f}" + metric.id
            if seen.insert(identity).inserted { all.append(RankedMetric(snapshot: snapshot, metric: metric)) }
        }
    }
    return Array(all.sorted {
        let left = $0.metric.usedPercent ?? 0, right = $1.metric.usedPercent ?? 0
        if left != right { return left > right }
        let a = [$0.providerID.rawValue, $0.accountID.rawValue, $0.metric.id]
        let b = [$1.providerID.rawValue, $1.accountID.rawValue, $1.metric.id]
        return a.lexicographicallyPrecedes(b)
    }.prefix(indicatorCount(maximumCount)))
}
