import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Revision 3: R3.1 (case at every entry point), R3.4 (fit), and the earlier "override beats the bundle image" rule.
// R3.2, R3.3 and R3.5 have no view-inspection seam and are not tested. Uses PCProbe from PCSettingsModelTests.swift.

// MARK: R3.1 (UI part)

@Suite @MainActor struct PCRevision3SettingsTests {
    // R, R3.1: lookalike(for:) never reports the provider itself, in any case of the id or state of the codes.
    @Test func lookalikeNeverReportsTheProviderItself() {
        let model = PCProbe().model()
        model.setProviderCode("cursor", "GL"); model.setProviderCode("budget", "OL")
        for provider in ["claude", "Claude", "CLAUDE", "codex", "Cursor", "CURSOR", "cursor", "budget", "Budget"] as [ProviderID] {
            let found = model.lookalike(for: provider)
            #expect(found?.rawValue != provider.rawValue.lowercased() && found?.rawValue != provider.rawValue, "\(provider): \(String(describing: found))")
        }
        #expect(model.lookalike(for: "Cursor") == "claude" && model.lookalike(for: "BUDGET") == "claude")
        #expect(model.lookalike(for: "Claude") == "cursor")
    }
    // R, R3.1: the reset check (R2.2) and the duplicate payload hold for any case of the id; overrides stay under lowercase keys.
    @Test func resetAndDuplicateIgnoreIdCase() {
        let probe = PCProbe(), model = probe.model(codes: ["claude": "AB", "cursor": "CL"])
        #expect(model.setProviderCode("CLAUDE", "") == .duplicate("cursor"))
        #expect(model.setProviderCode("Claude", "cl") == .duplicate("cursor"))
        #expect(model.setProviderCode("Codex", "ab") == .duplicate("claude"))
        #expect(model.providerCodes == ["claude": "AB", "cursor": "CL"] && probe.calls.isEmpty)
        #expect(model.setProviderCode("Codex", "zz") == .saved("ZZ"))
        #expect(Set(model.providerCodes.keys) == ["claude", "cursor", "codex"])
        #expect(model.setProviderCode("CODEX", "") == .reset)
        #expect(model.providerCodes.keys.allSatisfy { $0 == $0.lowercased() })
    }
    // R, R3.1: raw keys differing only in case reach the model as "no override" for that provider.
    @Test func initialKeysDifferingInCaseDropTheOverride() {
        let model = PCProbe().model(codes: ["Cursor": "CR", "cursor": "ZZ", "codex": "QQ"])
        #expect(model.providerCodes == ["codex": "QQ"] && model.code(for: "cursor") == "CU")
    }
}

// MARK: R3.4 fit

@MainActor private func pcr3Bitmap(_ view: NSView) -> NSBitmapImageRep {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}
private func pcr3Pixels(_ rep: NSBitmapImageRep, columns: (Int) -> Bool) -> [SIMD4<Double>] {
    (0..<rep.pixelsWide).filter(columns).flatMap { x in (0..<rep.pixelsHigh).map { y in
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!, a = Double(c.alphaComponent)
        return SIMD4(Double(c.redComponent) * a, Double(c.greenComponent) * a, Double(c.blueComponent) * a, a)
    } }
}
/// Horizontal extent in points of a slot's glyph area: right of the bar in the beside layout, the whole slot otherwise.
@MainActor private func pcr3Area(_ index: Int) -> ClosedRange<CGFloat> {
    let beside = RingView.layout == .beside
    let minX = CGFloat(4 + index * (beside ? 24 : 21)), width: CGFloat = beside ? 19 : 18
    return (beside ? minX + 6 : minX)...(minX + width)
}
private func pcr3Ranked(_ provider: ProviderID, _ percent: Double?) -> RankedMetric {
    let snapshot = UsageSnapshot(providerID: provider, accountID: "a", accountLabel: "A", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 metrics: [UsageMetric(id: "session", label: "session", usedPercent: percent)])
    return RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0])
}
@MainActor private func pcr3View(dark: Bool, count: Int = 2, selected: [RankedMetric] = [], unavailable: [ProviderID] = [], codes: [String: String] = [:]) -> RingView {
    let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 22))
    view.count = count; view.selected = selected; view.unavailableProviders = unavailable; view.providerCodes = codes
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    return view
}
@MainActor private func pcr3WithLayout(_ layout: RingView.Layout, _ body: () -> Void) {
    _ = NSApplication.shared
    let previous = RingView.layout; RingView.layout = layout; defer { RingView.layout = previous }
    body()
}
private let pcr3Wide = ["WW", "MM", "W0", "ww"]

@Suite(.serialized) @MainActor struct PCRevision3FitTests {
    // R, R3.4: in the unhealthy marker a code wider than its glyph area draws no ink outside that area, in every layout and appearance.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
    func markerDrawsNoInkOutsideItsArea(layout: RingView.Layout, dark: Bool) {
        pcr3WithLayout(layout) {
            for code in pcr3Wide {
                for auth in [false, true] {
                    let view = pcr3View(dark: dark, count: 1, unavailable: ["cursor"], codes: ["cursor": code])
                    if auth { view.signInProviders = ["cursor"] }
                    let rep = pcr3Bitmap(view), scale = CGFloat(rep.pixelsWide) / view.bounds.width, area = pcr3Area(0)
                    let outside = pcr3Pixels(rep) { CGFloat($0) < area.lowerBound * scale || CGFloat($0) >= area.upperBound * scale }
                    #expect(outside.allSatisfy { $0.w == 0 }, "\(layout) \(code) auth \(auth): ink outside the glyph area")
                    let inside = pcr3Pixels(rep) { CGFloat($0) >= area.lowerBound * scale && CGFloat($0) < area.upperBound * scale }
                    #expect(inside.contains { $0.w > 0 }, "\(code) still draws inside the area")
                }
            }
        }
    }
    // R, R3.4: in a ranked slot an over-wide code changes nothing outside its glyph area: bars and neighbours are as with the default code.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
    func rankedSlotChangesNothingOutsideItsArea(layout: RingView.Layout, dark: Bool) {
        pcr3WithLayout(layout) {
            let selected = [pcr3Ranked("cursor", 40), pcr3Ranked("codex", 85)]
            let baseRep = pcr3Bitmap(pcr3View(dark: dark, selected: selected))
            for code in pcr3Wide {
                let view = pcr3View(dark: dark, selected: selected, codes: ["cursor": code])
                let rep = pcr3Bitmap(view), scale = CGFloat(rep.pixelsWide) / view.bounds.width, area = pcr3Area(0)
                let outside: (Int) -> Bool = { CGFloat($0) < area.lowerBound * scale || CGFloat($0) >= area.upperBound * scale }
                #expect(pcr3Pixels(rep, columns: outside) == pcr3Pixels(baseRep, columns: outside), "\(layout) \(code)")
                #expect(pcr3Pixels(rep) { _ in true } != pcr3Pixels(baseRep) { _ in true }, "\(code) is drawn")
            }
        }
    }
    // R, R3.4: the marker case, same equality: with an over-wide code only the glyph area differs from the default rendering.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo])
    func markerChangesNothingOutsideItsArea(layout: RingView.Layout) {
        pcr3WithLayout(layout) {
            let base = pcr3Bitmap(pcr3View(dark: false, selected: [pcr3Ranked("codex", 40)], unavailable: ["cursor"]))
            for code in pcr3Wide {
                let view = pcr3View(dark: false, selected: [pcr3Ranked("codex", 40)], unavailable: ["cursor"], codes: ["cursor": code])
                let rep = pcr3Bitmap(view), scale = CGFloat(rep.pixelsWide) / view.bounds.width, area = pcr3Area(1)
                let outside: (Int) -> Bool = { CGFloat($0) < area.lowerBound * scale || CGFloat($0) >= area.upperBound * scale }
                #expect(pcr3Pixels(rep, columns: outside) == pcr3Pixels(base, columns: outside), "\(layout) \(code)")
            }
        }
    }
    // I, R3.4: a code that fits is drawn exactly as before: pixel-identical to the reserved twin in the marker and in a ranked slot.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
    func fittingCodesAreDrawnAsBefore(layout: RingView.Layout, dark: Bool) {
        pcr3WithLayout(layout) {
            for (code, twin) in [("RP", "replit"), ("GM", "gemini"), ("MS", "mistral")] as [(String, ProviderID)] {
                #expect(ProviderGlyphImages.mask(for: twin) == nil)
                let marker = pcr3Pixels(pcr3Bitmap(pcr3View(dark: dark, unavailable: ["cursor"], codes: ["cursor": code]))) { _ in true }
                #expect(marker == pcr3Pixels(pcr3Bitmap(pcr3View(dark: dark, unavailable: [twin]))) { _ in true }, "marker \(code)")
                let ranked = pcr3Pixels(pcr3Bitmap(pcr3View(dark: dark, selected: [pcr3Ranked("cursor", 40)], codes: ["cursor": code]))) { _ in true }
                #expect(ranked == pcr3Pixels(pcr3Bitmap(pcr3View(dark: dark, selected: [pcr3Ranked(twin, 40)]))) { _ in true }, "ranked \(code)")
            }
        }
    }
    // N, R3.4: an over-wide code shrinks rather than being clipped: it differs from a fitting code and from nothing at all.
    @Test func wideCodeDiffersFromFittingAndDefault() {
        pcr3WithLayout(.beside) {
            let plain = pcr3Pixels(pcr3Bitmap(pcr3View(dark: false, unavailable: ["cursor"]))) { _ in true }
            let wide = pcr3Pixels(pcr3Bitmap(pcr3View(dark: false, unavailable: ["cursor"], codes: ["cursor": "WW"]))) { _ in true }
            let fits = pcr3Pixels(pcr3Bitmap(pcr3View(dark: false, unavailable: ["cursor"], codes: ["cursor": "RP"]))) { _ in true }
            #expect(wide != plain && wide != fits)
        }
    }
}

// MARK: override beats the bundle image

/// A temporary bundle with providers/<id>.png (a solid square); the previous bundle is restored by `restore`.
@MainActor private func pcr3InstallImageBundle(for id: String) throws -> (restore: () -> Void, bundle: Bundle) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("limitaur-synthetic-" + UUID().uuidString)
    let directory = root.appendingPathComponent("providers")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for x in 0..<32 { for y in 0..<32 { rep.setColor(x > 6 && x < 26 && y > 6 && y < 26 ? .black : .clear, atX: x, y: y) } }
    try #require(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(id + ".png"))
    let bundle = try #require(Bundle(url: root))
    let previous = ProviderGlyphImages.bundle
    ProviderGlyphImages.bundle = bundle
    return ({ ProviderGlyphImages.bundle = previous; try? FileManager.default.removeItem(at: root) }, bundle)
}

@Suite(.serialized) @MainActor struct PCRevision3BundleImageTests {
    private func render(_ layout: RingView.Layout, dark: Bool, codes: [String: String]) -> [SIMD4<Double>] {
        var result: [SIMD4<Double>] = []
        pcr3WithLayout(layout) {
            result = pcr3Pixels(pcr3Bitmap(pcr3View(dark: dark, selected: [pcr3Ranked("cursor", 40)], codes: codes))) { _ in true }
        }
        return result
    }
    // I/N: the injected bundle really supplies a mask for the provider, and removing it restores the text rendering.
    @Test func injectedBundleSuppliesAndRestores() throws {
        _ = NSApplication.shared
        #expect(ProviderGlyphImages.mask(for: "cursor") == nil)
        let (restore, _) = try pcr3InstallImageBundle(for: "cursor")
        #expect(ProviderGlyphImages.mask(for: "cursor") != nil)
        restore()
        #expect(ProviderGlyphImages.mask(for: "cursor") == nil, "the previous bundle is back and the cache cleared")
    }
    // N: without an override the image replaces the letters (jar and logo layouts); with one, the code is drawn as text.
    @Test(arguments: [RingView.Layout.jar, .logo], [false, true])
    func overrideBeatsTheBundleImage(layout: RingView.Layout, dark: Bool) throws {
        _ = NSApplication.shared
        let text = render(layout, dark: dark, codes: [:]), overriddenText = render(layout, dark: dark, codes: ["cursor": "RP"])
        let (restore, _) = try pcr3InstallImageBundle(for: "cursor"); defer { restore() }
        let withImage = render(layout, dark: dark, codes: [:])
        #expect(withImage != text, "the default rendering uses the image")
        let overridden = render(layout, dark: dark, codes: ["cursor": "RP"])
        #expect(overridden == overriddenText, "an override draws text exactly as it does without any image")
        #expect(overridden != withImage)
    }
    // I: an unusable override is no override, so the image still shows.
    @Test func unusableOverrideKeepsTheImage() throws {
        _ = NSApplication.shared
        let (restore, _) = try pcr3InstallImageBundle(for: "cursor"); defer { restore() }
        let plain = render(.jar, dark: false, codes: [:])
        for codes in [["cursor": "???"], ["cursor": ""], ["claude": "ZZ"]] {
            #expect(render(.jar, dark: false, codes: codes) == plain, "\(codes)")
        }
    }
    // I: the beside layout is letters-only, with or without an image, and an override is drawn there too.
    @Test func besideLayoutIgnoresTheImage() throws {
        _ = NSApplication.shared
        let text = render(.beside, dark: false, codes: [:]), overridden = render(.beside, dark: false, codes: ["cursor": "RP"])
        let (restore, _) = try pcr3InstallImageBundle(for: "cursor"); defer { restore() }
        #expect(render(.beside, dark: false, codes: [:]) == text && render(.beside, dark: false, codes: ["cursor": "RP"]) == overridden)
    }
}
