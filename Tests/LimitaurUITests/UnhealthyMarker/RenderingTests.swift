import AppKit
import Testing
@testable import LimitaurCore
@testable import Limitaur

@MainActor @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
func UnhealthyMarkerGeometryAndGlyphs(layout: RingView.Layout, dark: Bool) {
    _ = NSApplication.shared
    let previous = RingView.layout; RingView.layout = layout; defer { RingView.layout = previous }
    let slot = umSlot(0), area = layout == .beside ? NSRect(x: 10, y: 2, width: 13, height: 18) : slot
    let top = NSRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
    let bottom = NSRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
    let providers: [ProviderID] = ["claude", "codex", "q"] // A one-character ID still produces the two-character code Q?.
    var authentication: [NSBitmapImageRep] = [], other: [NSBitmapImageRep] = []
    for (provider, code) in zip(providers, ["CL", "CX", "Q?"]) {
        #expect(ProviderGlyphImages.mask(for: provider) == nil)
        for auth in [false, true] {
            let view = umView(1, dark, [], [provider], auth ? [provider] : []), bitmap = umBitmap(view)
            let reference = UMReference(frame: view.bounds); reference.appearance = view.appearance
            reference.runs = [(code, .systemFont(ofSize: 8, weight: .bold), top), (auth ? "×" : "…", .monospacedDigitSystemFont(ofSize: 9, weight: .bold), bottom)]
            #expect(umPixels(bitmap, slot) == umPixels(umBitmap(reference), slot), "exact code, status, colour and position; no dash")
            #expect(umAlpha(bitmap, NSRect(x: slot.minX, y: slot.minY, width: layout == .beside ? 5 : 1, height: slot.height)) == 0)
            if layout != .beside { #expect(umAlpha(bitmap, NSRect(x: slot.maxX - 1, y: slot.minY, width: 1, height: slot.height)) == 0) }
            #expect(umAlpha(bitmap, bottom) > 0)
            #expect(umPixels(bitmap, view.bounds) == umPixels(umBitmap(view), view.bounds))
            #expect(umPixels(bitmap, slot) != umPixels(umBitmap(umView(1, !dark, [], [provider], auth ? [provider] : [])), slot))
            if auth { authentication.append(bitmap) } else { other.append(bitmap) }
        }
    }
    for i in providers.indices {
        #expect(umAlpha(authentication[i], top) == umAlpha(other[i], top))
        #expect(umAlpha(authentication[i], bottom) != umAlpha(other[i], bottom))
        #expect(umAlpha(authentication[i], bottom) == umAlpha(authentication[0], bottom) && umAlpha(other[i], bottom) == umAlpha(other[0], bottom))
    }
    #expect(umAlpha(other[0], top) != umAlpha(other[1], top))
}
@MainActor @Test(arguments: [RingView.Layout.beside, .jar, .logo], [false, true])
func UnhealthyMarkerPreservesOtherSlots(layout: RingView.Layout, dark: Bool) {
    _ = NSApplication.shared
    let previous = RingView.layout; RingView.layout = layout; defer { RingView.layout = previous }
    for count in [1, 8] {
        let bounds = umView(count, dark).bounds
        #expect(bounds.width == CGFloat(layout == .beside ? 24 * count + 3 : 21 * count + 5))
        for metrics in [[], [umRanked(nil)], [umRanked(0), umRanked(85), umRanked(96)],
                        Array(repeating: umRanked(nil), count: count), Array(repeating: umRanked(40), count: count)] where metrics.count <= count {
            let base = umBitmap(umView(count, dark, metrics)), marked = umBitmap(umView(count, dark, metrics, ["claude"], ["claude"]))
            #expect(umPixels(base, bounds) == umPixels(umBitmap(umView(count, dark, metrics, [], ["claude"])), bounds))
            #expect(umPixels(marked, bounds) == umPixels(umBitmap(umView(count, dark, metrics, ["claude"], ["claude", "absent"])), bounds))
            for i in 0..<count where i != metrics.count { #expect(umPixels(base, umSlot(i)) == umPixels(marked, umSlot(i))) }
            if metrics.count < count { #expect(umPixels(base, umSlot(metrics.count)) != umPixels(marked, umSlot(metrics.count))) }
            let providers: [ProviderID] = ["claude", "codex", "gemini", "q", "cursor", "grok", "meta", "mistral", "copilot"]
            let overflow = umBitmap(umView(count, dark, metrics, providers, ["claude", "gemini"]))
            let clipped = umBitmap(umView(count, dark, metrics, Array(providers.prefix(count - metrics.count)), ["claude", "gemini"]))
            #expect(umPixels(overflow, bounds) == umPixels(clipped, bounds))
            for i in metrics.count..<count {
                let p = providers[i - metrics.count], reference = umBitmap(umView(1, dark, [], [p], ["claude", "gemini"]))
                #expect(umPixels(overflow, umSlot(i)) == umPixels(reference, umSlot(0)), "marker order starts after every ranked slot, including unknown fill")
            }
        }
    }
}
@MainActor @Test func UnhealthyMarkerSignInMutationInvalidatesDrawing() {
    _ = NSApplication.shared
    let view = RingView(frame: NSRect(x: 0, y: 0, width: 27, height: 22))
    let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = view
    defer { window.close() }
    #expect(view.signInProviders.isEmpty)
    view.needsDisplay = false; view.signInProviders = ["claude"]; #expect(view.needsDisplay)
    view.needsDisplay = false; view.signInProviders = []; #expect(view.needsDisplay)
}
