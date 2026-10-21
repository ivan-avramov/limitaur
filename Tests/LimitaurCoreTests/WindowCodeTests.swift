import Foundation
import Testing
@testable import LimitaurCore

private func metric(_ id: String, label: String = "x", duration: TimeInterval? = nil) -> UsageMetric {
    UsageMetric(id: id, label: label, usedPercent: 10, windowDuration: duration)
}

@Test func knownDurationDecidesBeforeKindOrLabel() {
    #expect(windowCode(for: metric("default:primary", label: "5h window", duration: 18_000)) == "5")
    #expect(windowCode(for: metric("default:secondary", label: "7d window", duration: 604_800)) == "W")
    #expect(windowCode(for: metric("default:other", label: "30d window", duration: 2_592_000)) == "M")
    #expect(windowCode(for: metric("x", label: "x", duration: 28 * 86_400)) == "M")
    #expect(windowCode(for: metric("x", label: "x", duration: 31 * 86_400)) == "M")
    #expect(windowCode(for: metric("x", label: "x", duration: 6 * 3600)) == "5")
    #expect(windowCode(for: metric("x", label: "15h window", duration: 54_000)) == "?", "no label fallback with a known duration")
    #expect(windowCode(for: metric("x", label: "17d window", duration: 17 * 86_400)) == "?")
    #expect(windowCode(for: metric("x", label: "27d window", duration: 27 * 86_400)) == "?")
    #expect(windowCode(for: metric("x", label: "130d window", duration: 130 * 86_400)) == "?")
    #expect(windowCode(for: metric("x", label: "8d window", duration: 8 * 86_400)) == "?")
    #expect(windowCode(for: metric("codex:review", label: "Code review · 1d window", duration: 86_400)) == "?")
    #expect(windowCode(for: metric("weekly:primary", label: "weekly · 5h window", duration: 18_000)) == "5", "Codex bucket named like a Claude kind")
    #expect(windowCode(for: metric("spend:primary", label: "spend · 7d window", duration: 604_800)) == "W")
    #expect(windowCode(for: metric("session", label: "x", duration: 2_592_000)) == "M")
}

@Test func kindDecidesWithoutDuration() {
    #expect(windowCode(for: metric("session:::", label: "session")) == "5")
    #expect(windowCode(for: metric("five_hour", label: "5h window")) == "5")
    #expect(windowCode(for: metric("five_hour_scoped", label: "five_hour_scoped")) == "5")
    #expect(windowCode(for: metric("weekly_all:::", label: "weekly")) == "W")
    #expect(windowCode(for: metric("seven_day", label: "7d window")) == "W")
    #expect(windowCode(for: metric("seven_day_opus", label: "seven_day_opus")) == "W", "legacy scoped key keeps its window, no guessed initial")
    #expect(windowCode(for: metric("weekly_scoped:g:model:surface:h", label: "Fable")) == "W")
    #expect(windowCode(for: metric("weekly_scoped:g:model:surface:h", label: "")) == "W")
    #expect(windowCode(for: metric("spend", label: "Spend")) == "$")
    #expect(windowCode(for: metric("extra_usage", label: "Extra usage")) == "$")
}

@Test func labelHintsMatchWholeWordsOnly() {
    #expect(windowCode(for: metric("x", label: "Weekly limit")) == "W")
    #expect(windowCode(for: metric("x", label: "Monthly spend")) == "M", "first matching rule wins in order 5, W, M, $")
    #expect(windowCode(for: metric("x", label: "Spend cap")) == "$")
    #expect(windowCode(for: metric("x", label: "15h window")) == "?", "15h is not the token 5h")
    #expect(windowCode(for: metric("x", label: "17d window")) == "?")
    #expect(windowCode(for: metric("x", label: "Code review")) == "?")
    #expect(windowCode(for: metric("", label: "")) == "?")
}

@Test func scopeInitialOnlyForModelScopedLimitsWithADisplayName() {
    #expect(scopeInitial(for: metric("weekly_scoped:g:model:surface:h", label: "Fable")) == "F")
    #expect(scopeInitial(for: metric("weekly_scoped:g:model:surface:h", label: "opus 4")) == "O")
    #expect(scopeInitial(for: metric("weekly_scoped:g:model:surface:h", label: "")) == nil)
    #expect(scopeInitial(for: metric("weekly_scoped:g:model:surface:h", label: "weekly_scoped")) == nil, "kind used as label is not a model name")
    #expect(scopeInitial(for: metric("weekly_all:::", label: "weekly")) == nil)
    #expect(scopeInitial(for: metric("session:::", label: "session")) == nil)
    #expect(scopeInitial(for: metric("seven_day_opus", label: "seven_day_opus")) == nil, "legacy key: no guessed initial")
    #expect(scopeInitial(for: metric("default:primary", label: "Fable", duration: 18_000)) == nil, "Codex windows are not model scoped")
}

@Test func providerGlyphsAreTwoLetterCodes() {
    #expect(providerGlyph(for: "claude") == "CL")
    #expect(providerGlyph(for: "codex") == "CX")
    #expect(providerGlyph(for: "Gemini") == "GM")
    #expect(providerGlyph(for: "zed") == "ZE", "unknown provider falls back to its first two letters")
    #expect(providerGlyph(for: "--") == "??")
}

@Test func providerCodesAreDistinguishable() {
    let codes = providerCodes.sorted { $0.key < $1.key }
    #expect(codes.count >= 20)
    for code in codes { #expect(code.value.count == 2 && code.value == code.value.uppercased(), "\(code.key)") }
    for (i, a) in codes.enumerated() {
        for b in codes[(i + 1)...] {
            #expect(a.value != b.value, "\(a.key) and \(b.key) share a code")
            #expect(providerCodesAreDistinguishable(a.value, b.value), "\(a.key) \(a.value) vs \(b.key) \(b.value)")
        }
    }
    #expect(!providerCodesAreDistinguishable("CL", "GL"), "same classes in both positions")
    #expect(!providerCodesAreDistinguishable("CL", "GI"))
    #expect(providerCodesAreDistinguishable("CL", "CX"))
    #expect(providerCodesAreDistinguishable("MS", "MA"))
}
