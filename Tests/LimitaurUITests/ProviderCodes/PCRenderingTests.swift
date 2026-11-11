import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Criterion C7 (RingView draws the override, not the default). Sampling follows the UnhealthyMarker and LabelledBars suites.
// The bundle-image rule ("an override beats Resources/providers") cannot be exercised: the test bundle ships no provider
// images, so every `ProviderGlyphImages.mask` is nil here; each test asserts that precondition.

@MainActor private func pcView(_ count: Int, dark: Bool, selected: [RankedMetric] = [], unavailable: [ProviderID] = [],
                               signIn: Set<ProviderID> = [], codes: [String: String]? = nil) -> RingView {
    let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 22))
    view.count = count; view.selected = selected; view.unavailableProviders = unavailable; view.signInProviders = signIn
    if let codes { view.providerCodes = codes }
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    return view
}
@MainActor private func pcBitmap(_ view: NSView) -> NSBitmapImageRep {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}
private func pcPixels(_ rep: NSBitmapImageRep, _ rect: NSRect) -> [SIMD4<Double>] {
    let scale = CGFloat(rep.pixelsHigh) / 22
    return (Int(rect.minX * scale)..<Int(rect.maxX * scale)).flatMap { x in
        (Int(rect.minY * scale)..<Int(rect.maxY * scale)).map { y in
            let c = rep.colorAt(x: x, y: rep.pixelsHigh - 1 - y)!.usingColorSpace(.sRGB)!, a = Double(c.alphaComponent)
            return SIMD4(Double(c.redComponent) * a, Double(c.greenComponent) * a, Double(c.blueComponent) * a, a)
        }
    }
}
@MainActor private func pcSlot(_ index: Int) -> NSRect {
    let beside = RingView.layout == .beside
    return NSRect(x: CGFloat(4 + index * (beside ? 24 : 21)), y: beside ? 2 : 1, width: beside ? 19 : 18, height: beside ? 18 : 20)
}
private func pcRanked(_ provider: ProviderID, _ percent: Double?) -> RankedMetric {
    let snapshot = UsageSnapshot(providerID: provider, accountID: "a", accountLabel: "A", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 metrics: [UsageMetric(id: "session", label: "session", usedPercent: percent)])
    return RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0])
}
@MainActor private func pcSlotPixels(_ view: RingView, _ index: Int = 0) -> [SIMD4<Double>] { pcPixels(pcBitmap(view), pcSlot(index)) }
@MainActor private func pcNoImages(_ providers: [ProviderID]) { for p in providers { #expect(ProviderGlyphImages.mask(for: p) == nil, "\(p)") } }

@MainActor private func pcWithLayout(_ layout: RingView.Layout, _ body: () -> Void) {
    _ = NSApplication.shared
    let previous = RingView.layout; RingView.layout = layout; defer { RingView.layout = previous }
    body()
}

// Serialized: RingView.layout is process-wide.
@Suite(.serialized) @MainActor struct PCRenderingTests {
    // N, I: no overrides by default, and setting them redraws.
    @Test func defaultsAndRedrawOnSet() {
        _ = NSApplication.shared
        let view = RingView(frame: NSRect(x: 0, y: 0, width: 27, height: 22))
        #expect(view.providerCodes.isEmpty)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.needsDisplay = false; view.providerCodes = ["cursor": "CR"]; #expect(view.needsDisplay)
        view.needsDisplay = false; view.providerCodes = [:]; #expect(view.needsDisplay)
    }
    // N, C7: an override changes the unhealthy marker's code; the pixels equal those of a provider whose reserved code is the override.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
    func unhealthyMarkerUsesTheOverride(layout: RingView.Layout, dark: Bool) {
        pcWithLayout(layout) {
            pcNoImages(["cursor", "claude", "replit", "gemini"])
            for (provider, code, twin) in [("cursor", "RP", "replit"), ("claude", "GM", "gemini")] as [(ProviderID, String, ProviderID)] {
                for auth in [false, true] {
                    let signIn: (ProviderID) -> Set<ProviderID> = { auth ? [$0] : [] }
                    let plain = pcSlotPixels(pcView(1, dark: dark, unavailable: [provider], signIn: signIn(provider)))
                    let overridden = pcSlotPixels(pcView(1, dark: dark, unavailable: [provider], signIn: signIn(provider), codes: [provider.rawValue: code]))
                    let reference = pcSlotPixels(pcView(1, dark: dark, unavailable: [twin], signIn: signIn(twin)))
                    #expect(overridden != plain, "\(provider) \(code) auth \(auth)")
                    #expect(overridden == reference, "same pixels as the reserved \(code) of \(twin)")
                }
            }
        }
    }
    // N, C7: a ranked (healthy) slot draws the override too.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
    func rankedSlotUsesTheOverride(layout: RingView.Layout, dark: Bool) {
        pcWithLayout(layout) {
            pcNoImages(["codex", "replit"])
            for percent in [0.0, 40, 85, 97] {
                let plain = pcSlotPixels(pcView(1, dark: dark, selected: [pcRanked("codex", percent)]))
                let overridden = pcSlotPixels(pcView(1, dark: dark, selected: [pcRanked("codex", percent)], codes: ["codex": "RP"]))
                let reference = pcSlotPixels(pcView(1, dark: dark, selected: [pcRanked("replit", percent)]))
                #expect(overridden != plain, "\(percent)")
                #expect(overridden == reference, "\(percent): the override reads like the reserved RP")
            }
        }
    }
    // N, C7: a one-character override renders as one character, identically for any provider, and differs from the default.
    @Test(arguments: [RingView.Layout.beside, .jar], [false, true])
    func oneCharacterOverride(layout: RingView.Layout, dark: Bool) {
        pcWithLayout(layout) {
            let a = pcSlotPixels(pcView(1, dark: dark, unavailable: ["cursor"], codes: ["cursor": "7"]))
            let b = pcSlotPixels(pcView(1, dark: dark, unavailable: ["claude"], codes: ["claude": "7"]))
            let lower = pcSlotPixels(pcView(1, dark: dark, unavailable: ["claude"], codes: ["claude": " 7 "]))
            #expect(a == b && b == lower)
            #expect(a != pcSlotPixels(pcView(1, dark: dark, unavailable: ["cursor"])))
        }
    }
    // I, C7: an override for another provider, an absent provider, the default itself or an unusable value changes no pixel.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
    func unrelatedAndUnusableOverridesChangeNothing(layout: RingView.Layout, dark: Bool) {
        pcWithLayout(layout) {
            let selected = [pcRanked("codex", 40), pcRanked("claude", 85)]
            let base = pcBitmap(pcView(4, dark: dark, selected: selected, unavailable: ["cursor"], signIn: ["cursor"]))
            let bounds = pcView(4, dark: dark).bounds
            for codes in [["budget": "ZZ"], ["gemini": "ZZ"], ["cursor": "CU"], ["cursor": "???"], ["cursor": ""], ["cursor": "é"], ["codex": "CX", "claude": " cl "]] {
                let other = pcBitmap(pcView(4, dark: dark, selected: selected, unavailable: ["cursor"], signIn: ["cursor"], codes: codes))
                #expect(pcPixels(base, bounds) == pcPixels(other, bounds), "\(codes)")
            }
        }
    }
    // N, C7: an override changes only its provider's slot; the other slots stay pixel-identical.
    @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
    func overrideTouchesOnlyItsSlot(layout: RingView.Layout, dark: Bool) {
        pcWithLayout(layout) {
            let selected = [pcRanked("codex", 40), pcRanked("claude", 85)]
            let base = pcBitmap(pcView(4, dark: dark, selected: selected, unavailable: ["cursor"]))
            let changed = pcBitmap(pcView(4, dark: dark, selected: selected, unavailable: ["cursor"], codes: ["claude": "ZQ"]))
            #expect(pcPixels(base, pcSlot(0)) == pcPixels(changed, pcSlot(0)))
            #expect(pcPixels(base, pcSlot(1)) != pcPixels(changed, pcSlot(1)))
            #expect(pcPixels(base, pcSlot(2)) == pcPixels(changed, pcSlot(2)))
            #expect(pcPixels(base, pcSlot(3)) == pcPixels(changed, pcSlot(3)))
        }
    }
    // N, C7: removing the override restores the default rendering exactly.
    @Test func removingTheOverrideRestoresTheDefault() {
        pcWithLayout(.beside) {
            let view = pcView(1, dark: false, unavailable: ["cursor"])
            let before = pcSlotPixels(view)
            view.providerCodes = ["cursor": "RP"]
            #expect(pcSlotPixels(view) != before)
            view.providerCodes = [:]
            #expect(pcSlotPixels(view) == before)
        }
    }
}
