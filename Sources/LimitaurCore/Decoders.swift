import Foundation
import CoreFoundation
import CryptoKit

public enum DecodeFailure: Error, Sendable { case invalidEnvelope }

private typealias Object = [String: Any]
private func object(_ value: Any?) -> Object? { value as? Object }
private func array(_ value: Any?) -> [Any]? { value as? [Any] }
private func string(_ value: Any?) -> String? { value as? String }
private func number(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
    let n = value.doubleValue
    return n.isFinite ? n : nil
}
private func boolean(_ value: Any?) -> Bool? {
    guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
    return value.boolValue
}
private func integer(_ value: Any?) -> Int? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
          let value = UInt64(n.stringValue), value <= UInt64(Int.max) else { return nil }
    return Int(value)
}
private func unix(_ value: Any?) -> Date? { number(value).map(Date.init(timeIntervalSince1970:)) }
private func iso(_ value: Any?) -> Date? {
    guard let raw = string(value) else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: raw) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
}
private func decimal(_ value: Any?) -> Decimal? {
    let raw: String
    if let s = value as? String { raw = s }
    else if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { raw = n.stringValue }
    else { return nil }
    let pattern = #"\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z"#
    guard raw.range(of: pattern, options: .regularExpression) != nil,
          let expected = decimalIdentity(raw) else { return nil }
    if expected.digits == "0" { return .zero }
    guard let parsed = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
    let output = NSDecimalNumber(decimal: parsed)
    guard output != .notANumber, let actual = decimalIdentity(output.stringValue),
          actual.negative == expected.negative, actual.digits == expected.digits,
          actual.power == expected.power else { return nil }
    return parsed
}
private func decimalIdentity(_ raw: String) -> (negative: Bool, digits: String, power: Int64)? {
    let parts = raw.lowercased().split(separator: "e", omittingEmptySubsequences: false)
    guard parts.count <= 2 else { return nil }
    var mantissa = String(parts[0])
    let negative = mantissa.first == "-"
    if mantissa.first == "-" || mantissa.first == "+" { mantissa.removeFirst() }
    let fraction = mantissa.split(separator: ".", omittingEmptySubsequences: false)
    let fractionalCount = fraction.count == 2 ? fraction[1].count : 0
    let combined = fraction.joined()
    var digits = combined.drop(while: { $0 == "0" })
    if digits.isEmpty { return (false, "0", 0) }
    let exponent = parts.count == 2 ? Int64(parts[1]) : 0
    guard let exponent, let count = Int64(exactly: fractionalCount) else { return nil }
    let (base, overflow) = exponent.subtractingReportingOverflow(count)
    guard !overflow else { return nil }
    var trailing: Int64 = 0
    while digits.last == "0" { digits.removeLast(); trailing += 1 }
    let (power, trailingOverflow) = base.addingReportingOverflow(trailing)
    guard !trailingOverflow else { return nil }
    return (negative, String(digits), power)
}
private func validContainer(_ root: Object, _ key: String, allowNull: Bool = true) -> Bool {
    guard let value = root[key] else { return false }
    return object(value) != nil || array(value) != nil || (allowNull && value is NSNull)
}
private func windowLabel(_ seconds: TimeInterval?, fallback: String) -> String {
    guard let seconds, seconds > 0 else { return fallback }
    if seconds.truncatingRemainder(dividingBy: 86400) == 0 { return "\(Int(seconds / 86400))d window" }
    if seconds.truncatingRemainder(dividingBy: 3600) == 0 { return "\(Int(seconds / 3600))h window" }
    return "\(Int(seconds / 60))m window"
}

public enum UsageDecoder {
    public static func decode(provider: ProviderID, data: Data, accountID: AccountID = "local",
                              accountLabel: String = "Default", now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? Object else { throw DecodeFailure.invalidEnvelope }
        switch provider.rawValue {
        case "codex": return try codex(root, accountID: accountID, accountLabel: accountLabel, now: now)
        case "claude": return try claude(root, accountID: accountID, accountLabel: accountLabel, now: now)
        default: throw DecodeFailure.invalidEnvelope
        }
    }

    private static func codex(_ root: Object, accountID: AccountID, accountLabel: String, now: Date) throws -> UsageSnapshot {
        let direct = ["rate_limit", "additional_rate_limits", "code_review_rate_limit", "credits", "model_usage", "rate_limit_reset_credits"]
        let modern = ["rateLimitsByLimitId", "rateLimits", "rateLimitResetCredits"]
        let recognized = (direct + modern).filter { root[$0] != nil }
        guard !recognized.isEmpty else { throw DecodeFailure.invalidEnvelope }
        if let modern = root["rateLimitsByLimitId"], object(modern) == nil { throw DecodeFailure.invalidEnvelope }
        for key in recognized {
            let value = root[key]!
            if key == "rateLimitsByLimitId" || key == "rateLimits" || key == "rate_limit" || key == "credits" || key == "model_usage" || key == "rate_limit_reset_credits" || key == "rateLimitResetCredits" || key == "code_review_rate_limit" {
                guard object(value) != nil || value is NSNull else { throw DecodeFailure.invalidEnvelope }
            } else if !validContainer(root, key) { throw DecodeFailure.invalidEnvelope }
        }
        var metrics: [UsageMetric] = [], balances: [CreditBalance] = [], capabilities: [String] = []
        var warnings: [String] = []
        var bad = 0, candidate = 0
        func addWindow(_ source: Any?, id: String, label: String, camel: Bool) {
            guard let source, !(source is NSNull) else { return }
            candidate += 1
            guard let row = object(source) else { bad += 1; return }
            let raw = number(row[camel ? "usedPercent" : "used_percent"])
            let duration = number(row[camel ? "windowDurationMins" : "limit_window_seconds"]).flatMap { value -> Double? in
                let seconds = camel ? value * 60 : value
                return seconds.isFinite && seconds >= 0 && seconds < Double(Int.max) ? seconds : nil
            }
            let resetKey = camel ? "resetsAt" : "reset_at"
            let reset = unix(row[resetKey])
            guard let percent = validatedPercent(raw) else { bad += 1; return }
            if let value = row[resetKey], !(value is NSNull), reset == nil { warnings.append("Reset time unavailable") }
            let sourceLabel = string(row["label"]) ?? string(row["limit_name"]) ?? label
            let durationLabel = windowLabel(duration, fallback: "")
            let displayLabel = durationLabel.isEmpty ? sourceLabel :
                ((label == "Primary" || label == "Secondary") && sourceLabel == label ? durationLabel : sourceLabel + " · " + durationLabel)
            metrics.append(UsageMetric(id: id, label: displayLabel, usedPercent: percent,
                                       resetsAt: reset, windowDuration: duration))
        }
        if root["rateLimitsByLimitId"] != nil || root["rateLimits"] != nil {
            if let byID = object(root["rateLimitsByLimitId"]) {
                for key in byID.keys.sorted().prefix(128) {
                    guard let bucket = object(byID[key]) else { bad += 1; candidate += 1; continue }
                    addWindow(bucket["primary"] ?? bucket["primaryWindow"], id: key + ":primary", label: key, camel: true)
                    addWindow(bucket["secondary"] ?? bucket["secondaryWindow"], id: key + ":secondary", label: key, camel: true)
                }
                if byID.count > 128 { warnings.append("Incomplete quota data") }
            } else if let legacy = object(root["rateLimits"]) {
                addWindow(legacy["primary"] ?? legacy["primaryWindow"], id: "default:primary", label: "Primary", camel: true)
                addWindow(legacy["secondary"] ?? legacy["secondaryWindow"], id: "default:secondary", label: "Secondary", camel: true)
            }
        } else if let rate = object(root["rate_limit"]) {
            addWindow(rate["primary_window"], id: "default:primary", label: "Primary", camel: false)
            addWindow(rate["secondary_window"], id: "default:secondary", label: "Secondary", camel: false)
        }
        if let extras = array(root["additional_rate_limits"]), !extras.isEmpty {
            warnings.append("Additional quota data unavailable")
        } else if root["additional_rate_limits"] != nil && !(root["additional_rate_limits"] is NSNull) && array(root["additional_rate_limits"]) == nil {
            warnings.append("Additional quota data unavailable")
        }
        if object(root["code_review_rate_limit"]) != nil { warnings.append("Code review quota data unavailable") }
        if let credits = object(root["credits"]) {
            let unlimited = boolean(credits["unlimited"]) ?? false
            let amount = decimal(credits["balance"])
            if let value = credits["balance"], !(value is NSNull), amount == nil { warnings.append("Credit amount unavailable") }
            for key in ["unlimited", "has_credits"] {
                if let value = credits[key], !(value is NSNull), boolean(value) == nil {
                    warnings.append("Credit status unavailable")
                }
            }
            if credits["balance"] != nil || credits["unlimited"] != nil || credits["has_credits"] != nil {
                balances.append(CreditBalance(label: "Provider credits", remaining: amount, unlimited: unlimited,
                                              state: unlimited || amount != nil ? .known : .unknown))
            }
        }
        if let models = object(root["model_usage"]) {
            for id in models.keys.sorted().prefix(128) {
                let row = object(models[id]) ?? [:]
                if let available = boolean(row["available"] ?? row["is_available"] ?? models[id]) {
                    capabilities.append("\(id): \(available ? "available" : "unavailable")")
                } else {
                    capabilities.append("\(id): availability unknown")
                    warnings.append("Model availability unavailable")
                }
            }
            if models.count > 128 { warnings.append("Incomplete model availability data") }
        }
        var resets: ResetCreditSummary?
        if let row = object(root["rate_limit_reset_credits"] ?? root["rateLimitResetCredits"]) {
            let camel = root["rateLimitResetCredits"] != nil
            let available = integer(row[camel ? "availableCount" : "available_count"])
            let applicable = integer(row[camel ? "applicableAvailableCount" : "applicable_available_count"])
            var details: [ResetCredit]?
            if camel, let entries = array(row["credits"]) {
                var parsed: [ResetCredit] = []
                for (index, item) in entries.prefix(128).enumerated() {
                    guard let item = object(item) else { warnings.append("Incomplete earned reset details"); continue }
                    let expiry = unix(item["expiresAt"])
                    if let value = item["expiresAt"], !(value is NSNull), expiry == nil {
                        warnings.append("Earned reset expiry unavailable")
                    }
                    parsed.append(ResetCredit(id: string(item["id"]) ?? "credit-\(index)",
                                              label: string(item["label"]) ?? "Earned reset", expiresAt: expiry))
                }
                details = parsed
                if entries.count > 128 { warnings.append("Incomplete earned reset details") }
            }
            resets = ResetCreditSummary(availableCount: available, applicableCount: applicable, details: details)
        }
        if candidate > 0 && bad == candidate && balances.isEmpty && resets == nil && capabilities.isEmpty {
            throw DecodeFailure.invalidEnvelope
        }
        if bad > 0 { warnings.append("Incomplete quota data") }
        if metrics.count > 128 { metrics = Array(metrics.prefix(128)); warnings.append("Incomplete quota data") }
        return UsageSnapshot(providerID: "codex", accountID: accountID, accountLabel: accountLabel,
                             fetchedAt: now, metrics: metrics, balances: balances, resetCredits: resets,
                             capabilities: capabilities, partial: !warnings.isEmpty, warnings: warnings)
    }

    private static func claude(_ root: Object, accountID: AccountID, accountLabel: String, now: Date) throws -> UsageSnapshot {
        let modern = root["limits"]
        if let modern, !(modern is NSNull), array(modern) == nil { throw DecodeFailure.invalidEnvelope }
        let scopedKeys = root.keys.filter {
            ($0.hasPrefix("seven_day_") || $0.hasPrefix("five_hour_")) && object(root[$0])?["utilization"] != nil
        }.sorted()
        let quotaKeys = ["five_hour", "seven_day"] + scopedKeys
        let independentKeys = ["spend", "extra_usage"]
        guard array(modern) != nil || quotaKeys.contains(where: { root[$0] != nil }) ||
              independentKeys.contains(where: { root[$0] != nil }) else { throw DecodeFailure.invalidEnvelope }
        for key in independentKeys where root[key] != nil {
            guard object(root[key]) != nil || root[key] is NSNull else { throw DecodeFailure.invalidEnvelope }
        }
        if array(modern) == nil {
            for key in quotaKeys where root[key] != nil {
                guard object(root[key]) != nil || root[key] is NSNull else { throw DecodeFailure.invalidEnvelope }
            }
        }
        var metrics: [UsageMetric] = [], warnings: [String] = []
        var amounts: [InformationalAmount] = []
        var candidate = 0, bad = 0
        var metricIndex: [String: Int] = [:]
        if let rows = array(modern) {
            for item in rows.prefix(128) {
                candidate += 1
                guard let row = object(item), let kind = string(row["kind"]),
                      let percent = validatedPercent(number(row["percent"])) else { bad += 1; continue }
                let group = string(row["group"]) ?? ""
                let scope = object(row["scope"]) ?? [:]
                let model = object(scope["model"]) ?? [:]
                let modelID = string(model["id"]) ?? ""
                let surface = string(scope["surface"]) ?? ""
                let label = string(model["display_name"]) ?? (group.isEmpty ? kind : group)
                let otherScope = scope.filter { $0.key != "model" && $0.key != "surface" }
                let extraData = (try? JSONSerialization.data(withJSONObject: otherScope, options: [.sortedKeys])) ?? Data()
                let extra = SHA256.hash(data: extraData).map { String(format: "%02x", $0) }.joined()
                let id = [kind, group, modelID, surface, extra].joined(separator: ":")
                let reset = iso(row["resets_at"])
                if let value = row["resets_at"], !(value is NSNull), reset == nil { warnings.append("Reset time unavailable") }
                let observation = QuotaObservation(usedPercent: percent, resetsAt: reset)
                if let index = metricIndex[id] {
                    var metric = metrics[index]
                    if metric.conflictingObservations?.contains(observation) == true ||
                       (metric.usedPercent == percent && metric.resetsAt == reset) { continue }
                    var observations = metric.conflictingObservations ?? [QuotaObservation(usedPercent: metric.usedPercent!, resetsAt: metric.resetsAt)]
                    observations.append(observation)
                    metric.usedPercent = nil
                    metric.resetsAt = nil
                    metric.conflictingObservations = observations
                    metrics[index] = metric
                    if !warnings.contains("Conflicting quota rows unavailable") { warnings.append("Conflicting quota rows unavailable") }
                } else {
                    metricIndex[id] = metrics.count
                    metrics.append(UsageMetric(id: id, label: label, usedPercent: percent,
                                               resetsAt: reset, scopeLabel: surface.isEmpty ? nil : surface))
                }
            }
            if rows.count > 128 { warnings.append("Incomplete quota data") }
        } else {
            let keys = [("five_hour", "5h window"), ("seven_day", "7d window")] + scopedKeys.map { ($0, $0) }
            for (key, label) in keys {
                guard let value = root[key], !(value is NSNull) else { continue }
                candidate += 1
                guard let row = object(value), let percent = validatedPercent(number(row["utilization"])) else { bad += 1; continue }
                let reset = iso(row["resets_at"])
                if let value = row["resets_at"], !(value is NSNull), reset == nil { warnings.append("Reset time unavailable") }
                metrics.append(UsageMetric(id: key, label: label, usedPercent: percent, resetsAt: reset))
            }
        }
        if let spendValue = root["spend"], !(spendValue is NSNull) {
            if let spend = object(root["spend"]), boolean(spend["enabled"]) == true {
                if let percent = validatedPercent(number(spend["percent"])) {
                    metrics.append(UsageMetric(id: "spend", label: "Spend", usedPercent: percent))
                } else {
                    warnings.append("Spend usage unavailable")
                }
                // Non-null limit and balance semantics are not verified for this direct endpoint.
                if ["limit", "balance", "cap"].contains(where: { spend[$0] != nil && !(spend[$0] is NSNull) }) {
                    warnings.append("Spend limit or balance metadata unavailable")
                }
                if let used = money(spend["used"]) {
                    amounts.append(InformationalAmount(label: "Spend used", amount: used.0, currency: used.1))
                } else if spend["used"] != nil && !(spend["used"] is NSNull) {
                    warnings.append("Spend units unavailable")
                }
            } else if let spend = object(root["spend"]), let enabled = spend["enabled"],
                      !(enabled is NSNull), boolean(enabled) == nil {
                warnings.append("Spend status unavailable")
            }
        } else if let extra = object(root["extra_usage"]), boolean(extra["is_enabled"]) == true {
            if let percent = validatedPercent(number(extra["utilization"])) {
                metrics.append(UsageMetric(id: "extra_usage", label: "Extra usage", usedPercent: percent))
            } else {
                warnings.append("Extra usage unavailable")
            }
            if ["monthly_limit", "used_credits"].contains(where: { extra[$0] != nil && !(extra[$0] is NSNull) }) {
                warnings.append("Extra usage amount units unavailable")
            }
        } else if let extra = object(root["extra_usage"]), let enabled = extra["is_enabled"],
                  !(enabled is NSNull), boolean(enabled) == nil {
            warnings.append("Extra usage status unavailable")
        }
        if candidate > 0 && bad == candidate { throw DecodeFailure.invalidEnvelope }
        if bad > 0 { warnings.append("Incomplete quota data") }
        if metrics.count > 128 { metrics = Array(metrics.prefix(128)); warnings.append("Incomplete quota data") }
        return UsageSnapshot(providerID: "claude", accountID: accountID, accountLabel: accountLabel,
                             fetchedAt: now, metrics: metrics, informationalAmounts: amounts,
                             partial: !warnings.isEmpty, warnings: warnings)
    }

    private static func money(_ value: Any?) -> (Decimal, String)? {
        guard let row = object(value), let amount = integer(row["amount_minor"]),
              let currency = string(row["currency"]), !currency.isEmpty,
              let exponent = integer(row["exponent"]), exponent <= 9 else { return nil }
        var divisor = Decimal(1)
        for _ in 0..<exponent { divisor *= 10 }
        return (Decimal(amount) / divisor, currency)
    }
}

