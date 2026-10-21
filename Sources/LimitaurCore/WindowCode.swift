import Foundation

/// One-character label for a quota metric's window, derived from the metric alone.
/// A known window duration decides first: `5` up to six hours, `W` exactly seven days,
/// `M` 28–31 days, `?` any other duration. Without a duration the decoder's kind decides:
/// `5` session or five_hour, `W` weekly, weekly_scoped or seven_day, `$` spend or metered.
/// Otherwise whole-word label hints, else `?`. Never empty. A model-scoped limit also has a
/// `scopeInitial(for:)`, shown to the right of this code.
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
    case "weekly", "weekly_all", "weekly_scoped", "seven_day": return "W"
    case "spend", "extra_usage": return "$"
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

/// Uppercased first letter of a model-scoped limit's display name (F for Fable), nil for
/// unscoped limits or when the decoder supplied no display name.
public func scopeInitial(for metric: UsageMetric) -> String? {
    let kind = metric.id.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init)?.lowercased() ?? ""
    guard kind == "weekly_scoped" || kind == "session_scoped" || kind == "five_hour_scoped" else { return nil }
    guard let letter = initial(of: metric.label), metric.label.lowercased() != kind else { return nil }
    return letter
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
