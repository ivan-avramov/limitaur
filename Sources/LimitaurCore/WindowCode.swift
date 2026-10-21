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

/// Two-letter provider codes shown above the window code. Every pair of codes must be
/// distinguishable at menu-bar size: see `providerCodesAreDistinguishable`.
/// Unknown providers use their first two letters, which the test does not vouch for.
public let providerCodes: [String: String] = [
    "claude": "CL", "codex": "CX", "gemini": "GM", "cursor": "CU", "copilot": "GH",
    "grok": "XA", "mistral": "MS", "perplexity": "PX", "deepseek": "DS", "meta": "MA",
    "microsoft": "MC", "cohere": "CE", "windsurf": "WI", "replit": "RP", "amazon": "AQ",
    "huggingface": "HF", "together": "TG", "groq": "GQ", "openrouter": "OR", "kimi": "KM",
    "qwen": "AL", "fireworks": "FW"
]

/// Unknown providers fall back to their first two letters; a fallback that is not
/// distinguishable from a reserved code degrades to its first letter plus `?`.
public func providerGlyph(for provider: ProviderID) -> String {
    if let code = providerCodes[provider.rawValue.lowercased()] { return code }
    let letters = String(provider.rawValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(2))
    guard letters.count == 2 else { return letters.isEmpty ? "??" : letters + "?" }
    if providerCodes.values.contains(where: { !providerCodesAreDistinguishable(letters, $0) }) {
        return String(letters.prefix(1)) + "?"
    }
    return letters
}

/// Letters that read alike in a small bold sans face share a class. Two codes are
/// distinguishable when at least one position holds letters from different classes.
public func letterConfusionClass(_ character: Character) -> Int {
    let classes: [Set<Character>] = [
        ["C", "G", "O", "Q", "D", "0", "6"], ["I", "L", "J", "T", "1"], ["E", "F"], ["M", "N", "W"],
        ["B", "R", "P", "8", "3", "9"], ["U", "V", "Y"], ["K", "X"], ["S", "5"], ["Z", "2"], ["A", "4"], ["H"]
    ]
    guard let upper = character.uppercased().first else { return -1 }
    return classes.firstIndex(where: { $0.contains(upper) }) ?? -1
}

/// Unclassified characters count as their own class: two codes differ at a position only
/// when the classes differ, or both characters are unclassified and not equal.
public func providerCodesAreDistinguishable(_ a: String, _ b: String) -> Bool {
    guard a.count == b.count else { return true }
    return zip(a, b).contains { x, y in
        let cx = letterConfusionClass(x), cy = letterConfusionClass(y)
        return cx != cy || (cx == -1 && x != y)
    }
}

private func initial(of text: String) -> String? {
    text.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() }
}
