import Foundation

/// One-character label for a quota metric's window, derived from the metric alone.
/// `5` session or up to six hours, `W` weekly or seven days, `M` thirty days, the first
/// letter of a model-scoped display name, `$` spend or metered, `?` when unknown. Never empty.
public func windowCode(for metric: UsageMetric) -> String {
    let kind = metric.id.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init)?.lowercased() ?? ""
    switch kind {
    case "session", "five_hour": return "5"
    case "weekly", "weekly_all", "seven_day": return "W"
    case "spend", "extra_usage": return "$"
    case "weekly_scoped": return initial(of: metric.label) ?? "W"
    default: break
    }
    if let seconds = metric.windowDuration, seconds > 0 {
        if seconds <= 6 * 3600 { return "5" }
        if abs(seconds - 7 * 86400) <= 86400 { return "W" }
        if abs(seconds - 30 * 86400) <= 2 * 86400 { return "M" }
    }
    let label = metric.label.lowercased()
    if label.contains("session") || label.contains("5h") { return "5" }
    if label.contains("week") || label.contains("7d") { return "W" }
    if label.contains("month") || label.contains("30d") { return "M" }
    if label.contains("spend") || label.contains("credit") || label.contains("$") { return "$" }
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
