import Foundation

/// One-character label for a quota metric's window, derived from the metric alone.
/// A known window duration decides first: `5` up to six hours, `W` exactly seven days,
/// `M` 28–31 days, `?` any other duration. Without a duration the decoder's kind decides:
/// `5` session or five_hour, `W` weekly or seven_day, the first letter of a model-scoped
/// display name, `$` spend or metered. Otherwise whole-word label hints, else `?`. Never empty.
public func windowCode(for metric: UsageMetric) -> String {
    if let seconds = metric.windowDuration, seconds > 0 {
        if seconds <= 6 * 3600 { return "5" }
        if seconds == 7 * 86400 { return "W" }
        if (28 * 86400...31 * 86400).contains(seconds) { return "M" }
        return "?"
    }
    let kind = metric.id.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init)?.lowercased() ?? ""
    switch kind {
    case "session", "five_hour": return "5"
    case "weekly", "weekly_all", "seven_day": return "W"
    case "spend", "extra_usage": return "$"
    case "weekly_scoped": return initial(of: metric.label) ?? "W"
    default:
        if kind.hasPrefix("five_hour_") { return "5" }
        if kind.hasPrefix("seven_day_") { return "W" }
    }
    let words = Set(metric.label.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "$" }).map(String.init))
    if !words.isDisjoint(with: ["session", "5h"]) { return "5" }
    if !words.isDisjoint(with: ["week", "weekly", "7d"]) { return "W" }
    if !words.isDisjoint(with: ["month", "monthly", "30d"]) { return "M" }
    if !words.isDisjoint(with: ["spend", "credit", "credits", "$"]) { return "$" }
    return "?"
}

/// Default provider glyph: C for Claude, X for Codex, else the uppercased first letter.
public func providerGlyph(for provider: ProviderID) -> String {
    switch provider.rawValue.lowercased() {
    case "claude": return "C"
    case "codex": return "X"
    default: return initial(of: provider.rawValue) ?? "?"
    }
}

private func initial(of text: String) -> String? {
    text.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() }
}
