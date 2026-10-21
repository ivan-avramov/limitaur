import AppKit
import Foundation
import Testing
@testable import LimitaurCore
@testable import Limitaur

@MainActor private func render(_ metrics: [RankedMetric], count: Int = 3, dark: Bool = true, stale: Bool = false) -> Data {
    let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 22))
    view.count = count; view.selected = metrics; view.stale = stale
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])!
}

private func ranked(_ provider: ProviderID, id: String, label: String, percent: Double?) -> RankedMetric {
    let snapshot = UsageSnapshot(providerID: provider, accountID: "a", accountLabel: "A", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 metrics: [UsageMetric(id: id, label: label, usedPercent: percent)])
    return RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0])
}

@MainActor @Test func statusWidthGrowsWithJarsAndFitsCounts() {
    #expect(RingView.statusWidth(for: 1) == CGFloat(26))
    #expect(RingView.statusWidth(for: 3) == CGFloat(60))
    #expect(RingView.statusWidth(for: 8) == CGFloat(145))
    #expect(RingView.statusWidth(for: 0) == RingView.statusWidth(for: 3))
    #expect(RingView.statusWidth(for: 99) == RingView.statusWidth(for: 3))
}

@MainActor @Test func jarRenderingReflectsGlyphsFillAndAppearance() {
    _ = NSApplication.shared
    let claudeSession = ranked("claude", id: "session:::", label: "session", percent: 21)
    let claudeWeekly = ranked("claude", id: "weekly_all:::", label: "weekly", percent: 21)
    let codexSession = ranked("codex", id: "session:::", label: "session", percent: 21)
    let full = ranked("claude", id: "session:::", label: "session", percent: 100)
    let unknown = ranked("claude", id: "session:::", label: "session", percent: nil)
    let base = render([claudeSession])
    #expect(base != render([claudeWeekly]), "window code must change pixels")
    #expect(base != render([codexSession]), "provider glyph must change pixels")
    #expect(base != render([full]), "fill level must change pixels")
    #expect(base != render([unknown]), "unavailable slot must differ from a known value")
    #expect(base != render([claudeSession], dark: false), "appearance must change pixels")
    #expect(render([claudeSession]) == base, "rendering is deterministic")
    #expect(render([], stale: true) != render([]), "health marker must change pixels")
}

@MainActor @Test func providerGlyphImageIsOptionalAndCached() {
    #expect(ProviderGlyphImages.image(for: "codex", bundle: Bundle(for: Anchor.self)) == nil)
    #expect(ProviderGlyphImages.image(for: "codex", bundle: Bundle(for: Anchor.self)) == nil)
}
private final class Anchor {}
