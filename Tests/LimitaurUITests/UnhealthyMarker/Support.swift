import AppKit
import Foundation
@testable import LimitaurCore
@testable import Limitaur

@MainActor func umView(_ count: Int, _ dark: Bool, _ metrics: [RankedMetric] = [], _ unavailable: [ProviderID] = [], _ signIn: Set<ProviderID> = []) -> RingView {
    let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 22))
    view.count = count; view.selected = metrics; view.unavailableProviders = unavailable; view.signInProviders = signIn
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    return view
}
@MainActor func umBitmap(_ view: NSView) -> NSBitmapImageRep {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}
// Copied sampling convention from LabelledBarsTests; compare every premultiplied RGBA pixel, not just sums.
func umPixels(_ rep: NSBitmapImageRep, _ rect: NSRect) -> [SIMD4<Double>] {
    let scale = CGFloat(rep.pixelsHigh) / 22
    return (Int(rect.minX * scale)..<Int(rect.maxX * scale)).flatMap { x in
        (Int(rect.minY * scale)..<Int(rect.maxY * scale)).map { y in
            let c = rep.colorAt(x: x, y: rep.pixelsHigh - 1 - y)!.usingColorSpace(.sRGB)!, a = Double(c.alphaComponent)
            return SIMD4(Double(c.redComponent) * a, Double(c.greenComponent) * a, Double(c.blueComponent) * a, a)
        }
    }
}
func umAlpha(_ rep: NSBitmapImageRep, _ rect: NSRect) -> Double { umPixels(rep, rect).reduce(0) { $0 + $1.w } }
@MainActor func umSlot(_ index: Int) -> NSRect {
    let beside = RingView.layout == .beside
    return NSRect(x: CGFloat(4 + index * (beside ? 24 : 21)), y: beside ? 2 : 1, width: beside ? 19 : 18, height: beside ? 18 : 20)
}
func umRanked(_ percent: Double?) -> RankedMetric {
    let snapshot = UsageSnapshot(providerID: "codex", accountID: "a", accountLabel: "A", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 metrics: [UsageMetric(id: "session", label: "session", usedPercent: percent)])
    return RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0])
}
@MainActor final class UMReference: NSView {
    var runs: [(String, NSFont, NSRect)] = []
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (text, font, rect) in runs {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
            }
        }
    }
}
