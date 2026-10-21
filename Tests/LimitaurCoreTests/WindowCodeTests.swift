import Foundation
import Testing
@testable import LimitaurCore

private func metric(_ id: String, label: String = "x", duration: TimeInterval? = nil) -> UsageMetric {
    UsageMetric(id: id, label: label, usedPercent: 10, windowDuration: duration)
}

@Test func windowCodesDeriveFromKindDurationAndLabelInThatOrder() {
    #expect(windowCode(for: metric("session:::", label: "session")) == "5")
    #expect(windowCode(for: metric("five_hour", label: "5h window")) == "5")
    #expect(windowCode(for: metric("weekly_all:::", label: "weekly")) == "W")
    #expect(windowCode(for: metric("seven_day", label: "7d window")) == "W")
    #expect(windowCode(for: metric("weekly_scoped:g:model:surface:h", label: "Fable")) == "F")
    #expect(windowCode(for: metric("weekly_scoped:g:model:surface:h", label: "opus 4")) == "O")
    #expect(windowCode(for: metric("weekly_scoped:g:model:surface:h", label: "")) == "W")
    #expect(windowCode(for: metric("spend", label: "Spend")) == "$")
    #expect(windowCode(for: metric("extra_usage", label: "Extra usage")) == "$")
    #expect(windowCode(for: metric("default:primary", label: "5h window", duration: 18_000)) == "5")
    #expect(windowCode(for: metric("default:secondary", label: "7d window", duration: 604_800)) == "W")
    #expect(windowCode(for: metric("default:secondary", label: "8d window", duration: 8 * 86_400)) == "W")
    #expect(windowCode(for: metric("default:other", label: "30d window", duration: 2_592_000)) == "M")
    #expect(windowCode(for: metric("codex:review", label: "Code review · 1d window", duration: 86_400)) == "?")
    #expect(windowCode(for: metric("codex:review", label: "Code review")) == "?")
    #expect(windowCode(for: metric("x", label: "Weekly limit")) == "W")
    #expect(windowCode(for: metric("x", label: "Monthly spend")) == "M")
    #expect(windowCode(for: metric("", label: "")) == "?")
    #expect(windowCode(for: metric("session", label: "x", duration: 2_592_000)) == "5", "kind wins over duration")
}

@Test func providerGlyphsAreSingleUppercaseCharacters() {
    #expect(providerGlyph(for: "claude") == "C")
    #expect(providerGlyph(for: "codex") == "X")
    #expect(providerGlyph(for: "cursor") == "C")
    #expect(providerGlyph(for: "9lives") == "9")
    #expect(providerGlyph(for: "--") == "?")
}
