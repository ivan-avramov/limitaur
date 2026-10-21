import AppKit
import Foundation
import Testing
@testable import LimitaurCore
@testable import Limitaur

@MainActor private func bitmap(_ metrics: [RankedMetric], count: Int = 3, dark: Bool = true, stale: Bool = false) -> NSBitmapImageRep {
    let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 22))
    view.count = count; view.selected = metrics; view.stale = stale
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}
@MainActor private func render(_ metrics: [RankedMetric], count: Int = 3, dark: Bool = true, stale: Bool = false) -> Data {
    bitmap(metrics, count: count, dark: dark, stale: stale).representation(using: .png, properties: [:])!
}

private func ranked(_ provider: ProviderID, id: String, label: String, percent: Double?) -> RankedMetric {
    let snapshot = UsageSnapshot(providerID: provider, accountID: "a", accountLabel: "A", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 metrics: [UsageMetric(id: id, label: label, usedPercent: percent)])
    return RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0])
}

/// Sum of alpha over a point rect; row 0 of the bitmap is the top, and the bitmap may be scaled.
private func alphaSum(_ rep: NSBitmapImageRep, _ rect: NSRect) -> Double {
    let scale = CGFloat(rep.pixelsHigh) / 22
    var total = 0.0
    for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            total += Double(rep.colorAt(x: x, y: rep.pixelsHigh - 1 - y)?.alphaComponent ?? 0)
        }
    }
    return total
}
private func alpha(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> CGFloat {
    let scale = CGFloat(rep.pixelsHigh) / 22
    return rep.colorAt(x: Int(x * scale), y: rep.pixelsHigh - 1 - Int(y * scale))?.alphaComponent ?? -1
}
private let firstJar = NSRect(x: 4, y: 11 - 9, width: 14, height: 18)
private let topHalf = NSRect(x: firstJar.minX, y: firstJar.midY, width: firstJar.width, height: firstJar.height / 2)
private let bottomHalf = NSRect(x: firstJar.minX, y: firstJar.minY, width: firstJar.width, height: firstJar.height / 2)

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
    let three = render([claudeSession, codexSession, claudeWeekly])
    #expect(three != render([claudeSession, claudeSession, claudeSession]), "each jar draws its own glyphs")
}

@MainActor @Test func glyphsAreKnockedOutOfAFullJarInTheirOwnHalves() {
    _ = NSApplication.shared
    let claudeSession = ranked("claude", id: "session:::", label: "session", percent: 100)
    let claudeWeekly = ranked("claude", id: "weekly_all:::", label: "weekly", percent: 100)
    let codexSession = ranked("codex", id: "session:::", label: "session", percent: 100)
    let a = bitmap([claudeSession]), b = bitmap([claudeWeekly]), c = bitmap([codexSession])
    // Without the knockout a full jar is a solid block: every alpha equals the maximum.
    let scale = Double(a.pixelsHigh) / 22
    let solid = Double(firstJar.width * firstJar.height) * scale * scale
    #expect(alphaSum(a, firstJar) < solid * 0.97, "glyph holes must remove fill alpha")
    // Window code lives in the bottom half, provider glyph in the top half.
    #expect(alphaSum(a, bottomHalf) != alphaSum(b, bottomHalf))
    #expect(alphaSum(a, topHalf) == alphaSum(b, topHalf))
    #expect(alphaSum(a, topHalf) != alphaSum(c, topHalf))
    #expect(alphaSum(a, bottomHalf) == alphaSum(c, bottomHalf))
}

@MainActor @Test func providerGlyphImageReplacesLetterWhenPresent() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("limitaur-glyph-\(UUID().uuidString)/Glyph.app")
    let providers = root.appendingPathComponent("Contents/Resources/providers")
    try FileManager.default.createDirectory(at: providers, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.limitaur.test"], format: .xml, options: 0)
        .write(to: root.appendingPathComponent("Contents/Info.plist"))
    let logo = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
        NSColor.black.setFill(); NSBezierPath(ovalIn: rect).fill(); return true
    }
    let cg = logo.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: providers.appendingPathComponent("codex.png"))
    defer {
        ProviderGlyphImages.bundle = .main
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }
    #expect(ProviderGlyphImages.mask(for: "codex") == nil, "main bundle under test has no images")
    ProviderGlyphImages.bundle = try #require(Bundle(url: root))
    #expect(ProviderGlyphImages.mask(for: "codex") != nil)
    #expect(ProviderGlyphImages.mask(for: "claude") == nil)
    let codex = ranked("codex", id: "session:::", label: "session", percent: 100)
    let withLogo = bitmap([codex])
    ProviderGlyphImages.bundle = .main
    let withLetter = bitmap([codex])
    #expect(alphaSum(withLogo, topHalf) != alphaSum(withLetter, topHalf), "logo replaces the letter")
    #expect(alphaSum(withLogo, bottomHalf) == alphaSum(withLetter, bottomHalf), "code glyph unchanged")
    // A disc logo must knock out a disc, not the whole provider box: corners stay filled, centre is a hole.
    let box = NSRect(x: firstJar.minX + 1, y: firstJar.midY + 0.5, width: firstJar.width - 2, height: firstJar.height / 2 - 1.5)
    let centre = alpha(withLogo, x: box.midX, y: box.midY)
    let corner = alpha(withLogo, x: box.minX + 0.5, y: box.minY + 0.5)
    #expect(centre < 0.5 && corner > 0.5, "centre \(centre) corner \(corner)")
}
