import Foundation

/// Learned poll interval of one provider: raised by throttling, lowered by a daily probe, never hunting.
public struct PollingPolicy: Sendable, Equatable, Codable {
    public static let floor: TimeInterval = 30, ceiling: TimeInterval = 120, step: TimeInterval = 10
    public static let probeWait: TimeInterval = 86_400, cleanRequired = 5
    public static let revertWindow: TimeInterval = 3_600, blockDuration: TimeInterval = 7 * 86_400
    public struct Reduction: Sendable, Equatable, Codable { public var from, to: TimeInterval; public var at: Date }
    public private(set) var interval: TimeInterval = 50
    public private(set) var consecutiveClean = 0
    public private(set) var lastChange: Date?
    public private(set) var lastReduction: Reduction?
    public private(set) var blockedUntil: [Int: Date] = [:]
    private enum CodingKeys: String, CodingKey { case interval, lastChange, lastReduction, blockedUntil }
    public init() {}

    public mutating func recordClean(now: Date, reductionAllowed: Bool) -> Bool {
        blockedUntil = blockedUntil.filter { $0.value > now }
        if lastChange == nil { lastChange = now }
        if let changed = lastChange, now < changed { lastChange = now; consecutiveClean = 0; return false }
        consecutiveClean = min(consecutiveClean + 1, Self.cleanRequired)
        let lower = interval - Self.step
        guard reductionAllowed, consecutiveClean >= Self.cleanRequired, let changed = lastChange,
              now.timeIntervalSince(changed) >= Self.probeWait, lower >= Self.floor,
              blockedUntil[Int(lower)] == nil else { return false }
        lastReduction = Reduction(from: interval, to: lower, at: now)
        interval = lower; consecutiveClean = 0; lastChange = now
        return true
    }
    public mutating func recordThrottle(now: Date, retryAfter: TimeInterval?) -> Bool {
        let before = interval
        let raw = retryAfter.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        let r = (raw / Self.step).rounded(.up) * Self.step
        if let reduction = lastReduction, now.timeIntervalSince(reduction.at) >= 0,
           now.timeIntervalSince(reduction.at) < Self.revertWindow {
            interval = min(Self.ceiling, max(interval, reduction.from, r))
            blockedUntil[Int(reduction.to)] = now.addingTimeInterval(Self.blockDuration)
            lastReduction = nil
        } else {
            interval = min(Self.ceiling, max(interval + Self.step, r))
        }
        consecutiveClean = 0; lastChange = now
        return interval != before
    }
    public mutating func recordOther() { consecutiveClean = 0 }

    public static func decode(_ data: Data, now: Date) -> PollingPolicy {
        func valid(_ v: TimeInterval) -> Bool { v >= floor && v <= ceiling && v.truncatingRemainder(dividingBy: step) == 0 }
        guard var p = try? JSONDecoder().decode(PollingPolicy.self, from: data), valid(p.interval),
              p.lastReduction.map({ valid($0.from) && valid($0.to) && $0.to == $0.from - step }) ?? true,
              p.blockedUntil.keys.allSatisfy({ valid(TimeInterval($0)) }) else { return PollingPolicy() }
        p.lastChange = p.lastChange.map { min($0, now) }
        if let r = p.lastReduction { p.lastReduction?.at = min(r.at, now) }
        let limit = now.addingTimeInterval(blockDuration)
        p.blockedUntil = p.blockedUntil.filter { $0.value > now }.mapValues { min($0, limit) }
        return p
    }
}

/// Period of the app's cycle tick; the policy interval is enforced by the monitor's gate, not by the timer.
package let cycleTick: TimeInterval = 10

package func fetchedLine(age: TimeInterval, interval: TimeInterval?) -> String {
    guard age.isFinite, age >= 0, age < Double(Int.max) else { return "  Fetched time unavailable" }
    let polls = interval.flatMap { $0.isFinite && $0 >= 0 && $0 < Double(Int.max) ? " · polls every \(Int($0))s" : nil } ?? ""
    return "  Fetched \(Int(age))s ago" + polls
}

/// Line of a row that has no fetch age (connecting, denied, suspended, a new entity after a rotation).
package func pollsLine(interval: TimeInterval) -> String { "  Polls every \(Int(interval))s" }

/// The dropdown is rebuilt when a displayed provider interval differs; counter-only changes never rebuild it.
package func intervalsDiffer(_ left: [String: PollingPolicy], _ right: [String: PollingPolicy]) -> Bool {
    left.mapValues(\.interval) != right.mapValues(\.interval)
}

/// In-memory policies carried by the demo's synthetic display.
package let demoPolling: [String: PollingPolicy] = ["claude": PollingPolicy(), "codex": PollingPolicy()]

package protocol PollingStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

/// Loads each provider's policy once and writes it back only when its encoded form differs from the bytes in storage.
package final class PollingPersistence {
    private let storage: any PollingStorage
    private var stored: [String: Data] = [:]
    package init(_ storage: any PollingStorage) { self.storage = storage }
    private static func encode(_ policy: PollingPolicy) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(policy)
    }
    package func load(_ providers: [String], now: Date = Date()) -> [String: PollingPolicy] {
        Dictionary(uniqueKeysWithValues: providers.map { name in
            let data = storage.data(forKey: "polling." + name)
            if let data { stored[name] = data }
            return (name, data.map { PollingPolicy.decode($0, now: now) } ?? PollingPolicy())
        })
    }
    package func save(_ policies: [String: PollingPolicy]) {
        for (name, policy) in policies {
            guard let data = Self.encode(policy), stored[name] != data else { continue }
            storage.set(data, forKey: "polling." + name); stored[name] = data
        }
    }
}
