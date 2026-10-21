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
/// Sum of brightness over a point rect, for layouts that paint glyphs in a contrast colour.
private func brightnessSum(_ rep: NSBitmapImageRep, _ rect: NSRect) -> Double {
    let scale = CGFloat(rep.pixelsHigh) / 22
    var total = 0.0
    for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            if let color = rep.colorAt(x: x, y: rep.pixelsHigh - 1 - y)?.usingColorSpace(.sRGB) {
                total += Double((0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent) * color.alphaComponent)
            }
        }
    }
    return total
}
private func brightness(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> CGFloat {
    let scale = CGFloat(rep.pixelsHigh) / 22
    guard let color = rep.colorAt(x: Int(x * scale), y: rep.pixelsHigh - 1 - Int(y * scale))?.usingColorSpace(.sRGB) else { return -1 }
    return (0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent) * color.alphaComponent
}
@MainActor private func withLayout<T>(_ layout: RingView.Layout, _ body: () throws -> T) rethrows -> T {
    let previous = RingView.layout
    RingView.layout = layout
    defer { RingView.layout = previous }
    return try body()
}
private extension RankedMetric {
    func filled(to percent: Double) -> RankedMetric {
        var copy = self; copy.metric.usedPercent = percent; return copy
    }
}
private func halves(_ rect: NSRect) -> (top: NSRect, bottom: NSRect) {
    (NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
     NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
}

@MainActor @Test func activeLayoutIsLettersBesideTheBar() {
    #expect(RingView.layout == .beside)
}

@MainActor @Test func statusWidthGrowsWithSlotsAndFitsCounts() {
    #expect(RingView.statusWidth(for: 1) == CGFloat(31))
    #expect(RingView.statusWidth(for: 3) == CGFloat(79))
    #expect(RingView.statusWidth(for: 8) == CGFloat(199))
    #expect(RingView.statusWidth(for: 0) == RingView.statusWidth(for: 3))
    #expect(RingView.statusWidth(for: 99) == RingView.statusWidth(for: 3))
    withLayout(.jar) { #expect(RingView.statusWidth(for: 3) == CGFloat(72)) }
}

@MainActor @Test(arguments: [RingView.Layout.beside, .jar]) func renderingReflectsGlyphsFillAndAppearance(layout: RingView.Layout) {
    _ = NSApplication.shared
    withLayout(layout) {
        let claudeSession = ranked("claude", id: "session:::", label: "session", percent: 21)
        let claudeWeekly = ranked("claude", id: "weekly_all:::", label: "weekly", percent: 21)
        let codexSession = ranked("codex", id: "session:::", label: "session", percent: 21)
        let fable = ranked("claude", id: "weekly_scoped:g:m:s:h", label: "Fable", percent: 21)
        let full = ranked("claude", id: "session:::", label: "session", percent: 100)
        let unknown = ranked("claude", id: "session:::", label: "session", percent: nil)
        let base = render([claudeSession])
        #expect(base != render([claudeWeekly]), "window code must change pixels")
        #expect(base != render([codexSession]), "provider code must change pixels")
        #expect(render([claudeWeekly]) != render([fable]), "scope initial must change pixels")
        #expect(base != render([full]), "fill level must change pixels")
        #expect(base != render([unknown]), "unavailable slot must differ from a known value")
        #expect(base != render([claudeSession], dark: false), "appearance must change pixels")
        #expect(render([claudeSession]) == base, "rendering is deterministic")
        #expect(render([], stale: true) != render([]), "health marker must change pixels")
        #expect(render([claudeSession, codexSession, claudeWeekly]) != render([claudeSession, claudeSession, claudeSession]),
                "each slot draws its own glyphs")
    }
}

@MainActor @Test func besideLayoutKeepsProviderCodeAboveWindowCodeAndClearOfTheBar() {
    _ = NSApplication.shared
    let claudeSession = ranked("claude", id: "session:::", label: "session", percent: 100)
    let claudeWeekly = ranked("claude", id: "weekly_all:::", label: "weekly", percent: 100)
    let codexSession = ranked("codex", id: "session:::", label: "session", percent: 100)
    let a = bitmap([claudeSession]), b = bitmap([claudeWeekly]), c = bitmap([codexSession])
    let bar = NSRect(x: 4, y: 2, width: 5, height: 18)
    let column = NSRect(x: 10, y: 2, width: 13, height: 18)
    #expect(alphaSum(a, bar) == alphaSum(b, bar) && alphaSum(a, bar) == alphaSum(c, bar), "bar pixels do not depend on the glyphs")
    #expect(alphaSum(a, halves(column).bottom) != alphaSum(b, halves(column).bottom), "window code is in the bottom half")
    #expect(alphaSum(a, halves(column).top) == alphaSum(b, halves(column).top))
    #expect(alphaSum(a, halves(column).top) != alphaSum(c, halves(column).top), "provider code is in the top half")
    #expect(alphaSum(a, halves(column).bottom) == alphaSum(c, halves(column).bottom))
    // Full bar is a solid block of the fill colour: letters are beside it, not knocked out of it.
    let scale = Double(a.pixelsHigh) / 22
    #expect(alphaSum(a, bar.insetBy(dx: 1, dy: 2)) > Double((bar.width - 2) * (bar.height - 4)) * scale * scale * 0.97)
}

@MainActor @Test func jarLayoutPaintsContrastingGlyphsInTheirOwnHalvesOfAFullJar() {
    _ = NSApplication.shared
    withLayout(.jar) {
        // 100% is critical (red, light glyphs); use a normal fill so dark-mode fill is white and glyphs dark.
        let claudeSession = ranked("claude", id: "session:::", label: "session", percent: 100).filled(to: 80)
        let claudeWeekly = ranked("claude", id: "weekly_all:::", label: "weekly", percent: 100).filled(to: 80)
        let codexSession = ranked("codex", id: "session:::", label: "session", percent: 100).filled(to: 80)
        let a = bitmap([claudeSession]), b = bitmap([claudeWeekly]), c = bitmap([codexSession])
        // 80% fill: the bottom 16 of 20 points are white, glyphs dark; the top band is track.
        let filled = NSRect(x: 4, y: 1, width: 18, height: 16)
        let solid = Double(filled.width * filled.height) * Double(a.pixelsHigh * a.pixelsHigh) / (22 * 22)
        #expect(alphaSum(a, filled) > solid * 0.97, "jar is opaque: glyphs are painted, not knocked out")
        #expect(brightnessSum(a, filled) < solid * 0.97, "dark glyphs must darken a white (dark mode) fill")
        #expect(brightnessSum(a, halves(filled).bottom) != brightnessSum(b, halves(filled).bottom))
        #expect(brightnessSum(a, halves(filled).top) == brightnessSum(b, halves(filled).top))
        #expect(brightnessSum(a, halves(filled).top) != brightnessSum(c, halves(filled).top))
        #expect(brightnessSum(a, halves(filled).bottom) == brightnessSum(c, halves(filled).bottom))
    }
}

@MainActor @Test func providerGlyphImageReplacesLettersWhenPresent() throws {
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
    let codex = ranked("codex", id: "session:::", label: "session", percent: 80)
    try withLayout(.jar) {
        let withLogo = bitmap([codex])
        ProviderGlyphImages.bundle = .main
        let withLetters = bitmap([codex])
        let jar = NSRect(x: 4, y: 1, width: 18, height: 20)
        #expect(brightnessSum(withLogo, halves(jar).top) != brightnessSum(withLetters, halves(jar).top), "logo replaces the letters")
        #expect(brightnessSum(withLogo, halves(jar).bottom) == brightnessSum(withLetters, halves(jar).bottom), "code glyph unchanged")
        // A disc logo paints a disc, not the whole box: at 80% in dark mode the fill is white, the disc dark.
        let box = RingView.glyphRects(in: jar).provider.offsetBy(dx: 0, dy: -2)
        let centre = brightness(withLogo, x: box.midX, y: box.midY)
        let corner = brightness(withLogo, x: box.minX + 0.5, y: box.minY + 0.5)
        #expect(centre < 0.5 && corner > 0.5, "centre \(centre) corner \(corner)")
    }
}
