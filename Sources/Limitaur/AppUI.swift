import AppKit
import LimitaurCore
import Darwin
import CoreFoundation

@MainActor protocol IndicatorPreferenceStore: AnyObject {
    func loadCount() -> Int
    func saveCount(_ count: Int)
}

@MainActor final class DefaultsIndicatorStore: IndicatorPreferenceStore {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func loadCount() -> Int {
        guard let number = defaults.object(forKey: "indicatorCount") as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return 3 }
        return indicatorCount(Int(number.stringValue))
    }
    func saveCount(_ count: Int) { defaults.set(indicatorCount(count), forKey: "indicatorCount") }
}

@MainActor final class MemoryIndicatorStore: IndicatorPreferenceStore {
    private var value: Int
    init(_ value: Int = 3) { self.value = indicatorCount(value) }
    func loadCount() -> Int { value }
    func saveCount(_ count: Int) { value = indicatorCount(count) }
}

private struct DemoCredentialFiles: CredentialFileReading {
    func read(path: String) throws -> Data { throw CredentialFailure.missing }
}
private struct DemoKeychain: KeychainReading {
    func claudeCredential() -> KeychainResult { .notFound }
}
private struct DemoTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw TransportFailure.network }
}

/// Demo presentation remains at one synthetic instant for its real 300-second lifetime.
/// Explicitly supplied presentation clocks still advance in redraw tests.
private struct FrozenDemoClock: MonitorClock {
    let wall: Date
    let monotonic: TimeInterval
    init(base: any MonitorClock) {
        wall = base.wallNow()
        monotonic = base.monotonicNow()
    }
    func wallNow() -> Date { wall }
    func monotonicNow() -> TimeInterval { monotonic }
}

@MainActor final class AppActionRouter {
    let demo: Bool
    private let refreshBody: () -> Void
    private let connectBody: (String) -> Void
    private let accountsBody: () -> Void
    private let quitBody: () -> Void
    init(demo: Bool, refresh: @escaping () -> Void, connect: @escaping (String) -> Void,
         accounts: @escaping () -> Void, quit: @escaping () -> Void) {
        self.demo = demo; refreshBody = refresh; connectBody = connect
        accountsBody = accounts; quitBody = quit
    }
    func refresh() { if !demo { refreshBody() } }
    func connect(_ id: String) { if !demo { connectBody(id) } }
    func accounts() { if !demo { accountsBody() } }
    func quit() { quitBody() }
}

/// Loads optional monochrome provider images from the bundle's providers/ directory and turns
/// each into a CoreGraphics image mask whose unmasked samples are the image's opaque pixels.
@MainActor enum ProviderGlyphImages {
    private static var cache: [String: CGImage?] = [:]
    /// Bundle searched for providers/<id>.png; tests inject a temporary bundle. Setting it clears the cache.
    static var bundle: Bundle = .main { didSet { cache = [:] } }
    static func mask(for provider: ProviderID) -> CGImage? {
        if let cached = cache[provider.rawValue] { return cached }
        let url = bundle.url(forResource: provider.rawValue, withExtension: "png", subdirectory: "providers")
        let mask = url.flatMap { NSImage(contentsOf: $0) }.flatMap(shapeMask)
        cache[provider.rawValue] = mask
        return mask
    }
    /// Alpha-only bitmap: 255 everywhere, then the image punched out, so a mask sample of 0
    /// (the shape) is where CoreGraphics paints when the mask is used as a clip.
    private static func shapeMask(_ image: NSImage) -> CGImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              source.width > 0, source.height > 0, source.width <= 1024, source.height <= 1024,
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return nil }
        let frame = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.setFillColor(gray: 1, alpha: 1); context.fill(frame)
        context.setBlendMode(.destinationOut)
        context.draw(source, in: frame)
        guard let bytes = context.data else { return nil }
        let data = Data(bytes: bytes, count: context.bytesPerRow * source.height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(maskWidth: source.width, height: source.height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: context.bytesPerRow, provider: provider, decode: nil, shouldInterpolate: true)
    }
}

@MainActor final class RingView: NSView {
    /// Slot layout. `jar`: glyphs inside a filled jar. `beside`: a narrow bar with the glyphs
    /// stacked to its right in the plain foreground colour.
    enum Layout { case jar, beside, logo }
    static var layout: Layout = .beside
    static let leftPad: CGFloat = 4, rightPad: CGFloat = 4
    static var slotWidth: CGFloat { layout == .beside ? 19 : 18 }
    static var slotHeight: CGFloat { layout == .beside ? 18 : 20 }
    static var gap: CGFloat { layout == .beside ? 5 : 3 }
    static let barWidth: CGFloat = 5
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    static func statusWidth(for count: Int) -> CGFloat {
        let n = CGFloat(indicatorCount(count))
        return slotWidth * n + gap * (n - 1) + leftPad + rightPad
    }
    var count = 3 { didSet { needsDisplay = true } }
    var selected: [RankedMetric] = [] { didSet { needsDisplay = true } }
    /// Providers that are configured but not healthy; the first empty slots carry their codes.
    var unavailableProviders: [ProviderID] = [] { didSet { needsDisplay = true } }
    /// Subset of `unavailableProviders` whose marker shows the authentication glyph.
    var signInProviders: Set<ProviderID> = [] { didSet { needsDisplay = true } }
    var appearanceChanged: (() -> Void)?
    var willDraw: (() -> Void)?
    override var isFlipped: Bool { false }
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(false) }
    required init?(coder: NSCoder) { super.init(coder: coder); setAccessibilityElement(false) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        appearanceChanged?()
    }
    private static let glyphFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)
    private static let codeFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    private static let pairFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)
    private static let pairGlyphFont = NSFont.systemFont(ofSize: 8, weight: .bold)
    /// Opaque neutral track: dark in dark mode, light in light mode, so the foreground-tinted
    /// fill always contrasts with it and nothing behind the status item bleeds through.
    private var track: NSColor {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.42, alpha: 1) : NSColor(calibratedWhite: 0.5, alpha: 1)
    }
    private static let logoTrack = NSColor(calibratedWhite: 0.45, alpha: 1)
    private static let centreFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .heavy)
    private static let centrePairFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .heavy)

    /// Glyph boxes inside a slot rect: provider on top, window code below.
    static func glyphRects(in slot: NSRect) -> (provider: NSRect, code: NSRect) {
        (NSRect(x: slot.minX, y: slot.midY, width: slot.width, height: slot.height / 2),
         NSRect(x: slot.minX, y: slot.minY, width: slot.width, height: slot.height / 2))
    }
    private static func draw(text: String, font: NSFont, color: NSColor, centeredIn rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
    /// Paints `color` through the logo's shape only, never the whole box.
    private static func draw(mask: CGImage, color: NSColor, centeredIn rect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let side = min(rect.width, rect.height) - 1
        let target = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        cg.saveGState()
        cg.clip(to: target, mask: mask)
        color.setFill(); target.fill()
        cg.restoreGState()
    }
    /// `allowImage` is false for the beside layout, which is letters-only by contract.
    private static func drawGlyphs(provider: ProviderID, code: String, in slot: NSRect, color: NSColor, allowImage: Bool) {
        let rects = glyphRects(in: slot)
        if allowImage, let mask = ProviderGlyphImages.mask(for: provider) {
            draw(mask: mask, color: color, centeredIn: rects.provider)
        } else {
            let glyph = providerGlyph(for: provider)
            draw(text: glyph, font: glyph.count > 1 ? pairGlyphFont : glyphFont, color: color, centeredIn: rects.provider)
        }
        draw(text: code, font: code.count > 1 ? pairFont : codeFont, color: color, centeredIn: rects.code)
    }
    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    /// Near-black or near-white, whichever contrasts with the fill for this severity. The normal
    /// fill is the label colour, white in dark mode and black in light mode; yellow is bright; red is dark.
    func contrastColor(for percent: Double?) -> NSColor {
        let light = NSColor(calibratedWhite: 0.95, alpha: 1), dark = NSColor(calibratedWhite: 0.1, alpha: 1)
        switch severity(percent) {
        case .warning: return dark
        case .critical: return light
        case .normal, .unknown: return isDark ? dark : light
        }
    }
    private static func fillColor(for percent: Double?) -> NSColor {
        switch severity(percent) {
        case .normal: return .labelColor
        case .warning: return .systemYellow
        case .critical: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }
    /// The provider's logo shape as the gauge: dim track, fill rising to the percent, window
    /// code centred in a contrasting colour. Used only when a logo image is present.
    private func drawLogoGauge(_ ranked: RankedMetric, mask: CGImage, in slot: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let side = min(slot.width, slot.height)
        let box = NSRect(x: slot.midX - side / 2, y: slot.midY - side / 2, width: side, height: side)
        let code = windowCode(for: ranked.metric) + (scopeInitial(for: ranked.metric) ?? "")
        let fill = ringFill(ranked.metric.usedPercent)
        let fillHeight = fill.map { $0 > 0 ? max(0.5, box.height * CGFloat($0)) : 0 } ?? 0
        let fillColor = Self.fillColor(for: ranked.metric.usedPercent)
        cg.saveGState()
        cg.clip(to: box, mask: mask)
        Self.logoTrack.setFill(); box.fill()
        if fillHeight > 0 {
            fillColor.setFill()
            NSRect(x: box.minX, y: box.minY, width: box.width, height: fillHeight).fill()
        }
        cg.restoreGState()
        let font = code.count > 1 ? Self.centrePairFont : Self.centreFont
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: box.minX, y: box.minY + fillHeight, width: box.width, height: box.height - fillHeight).clip()
        Self.draw(text: code, font: font, color: NSColor(calibratedWhite: 0.1, alpha: 1), centeredIn: box)
        NSGraphicsContext.restoreGraphicsState()
        if fillHeight > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: box.minX, y: box.minY, width: box.width, height: fillHeight).clip()
            Self.draw(text: code, font: font, color: contrastColor(for: ranked.metric.usedPercent), centeredIn: box)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        willDraw?()
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
        for index in 0..<indicatorCount(count) {
            let slot = NSRect(x: Self.leftPad + CGFloat(index) * (Self.slotWidth + Self.gap),
                              y: bounds.midY - Self.slotHeight / 2, width: Self.slotWidth, height: Self.slotHeight)
            if Self.layout == .logo, index < selected.count, let mask = ProviderGlyphImages.mask(for: selected[index].providerID) {
                drawLogoGauge(selected[index], mask: mask, in: slot)
                continue
            }
            let bar = Self.layout == .beside ? NSRect(x: slot.minX, y: slot.minY, width: Self.barWidth, height: slot.height) : slot
            let radius: CGFloat = Self.layout == .beside ? 1.5 : 3
            let outline = NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius)
            let glyphArea = Self.layout == .beside
                ? NSRect(x: bar.maxX + 1, y: slot.minY, width: slot.width - Self.barWidth - 1, height: slot.height) : bar
            // A provider that is not healthy takes an empty slot without a track: its code over
            // "×" (authentication) or "…" (anything else), so it cannot read as a usage bar.
            let missing = index - selected.count
            if missing >= 0, missing < unavailableProviders.count {
                let provider = unavailableProviders[missing], code = providerGlyph(for: provider)
                let rects = Self.glyphRects(in: glyphArea)
                Self.draw(text: code, font: code.count > 1 ? Self.pairGlyphFont : Self.glyphFont,
                          color: .secondaryLabelColor, centeredIn: rects.provider)
                Self.draw(text: signInProviders.contains(provider) ? "×" : "…", font: Self.codeFont,
                          color: .secondaryLabelColor, centeredIn: rects.code)
                continue
            }
            track.setFill(); outline.fill()
            guard index < selected.count, let fill = ringFill(selected[index].metric.usedPercent) else {
                let dash = NSBezierPath()
                dash.lineWidth = 1
                dash.move(to: NSPoint(x: bar.minX + 1.5, y: bar.midY))
                dash.line(to: NSPoint(x: bar.maxX - 1.5, y: bar.midY))
                NSColor.secondaryLabelColor.setStroke()
                dash.stroke()
                continue
            }
            let ranked = selected[index]
            let code = windowCode(for: ranked.metric) + (scopeInitial(for: ranked.metric) ?? "")
            let fillHeight = fill > 0 ? max(0.5, bar.height * CGFloat(fill)) : 0
            let fillRect = NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: fillHeight)
            let fillColor = Self.fillColor(for: ranked.metric.usedPercent)
            if fillHeight > 0 {
                NSGraphicsContext.saveGraphicsState()
                outline.addClip()
                fillColor.setFill(); fillRect.fill()
                // A 1-point edge in a contrasting colour marks the level even where the fill's
                // luminance is close to the track's (red or yellow on grey in light mode).
                if fillHeight < bar.height {
                    contrastColor(for: ranked.metric.usedPercent).setFill()
                    NSRect(x: bar.minX, y: fillRect.maxY - 1, width: bar.width, height: 1).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            switch Self.layout {
            case .beside:
                Self.drawGlyphs(provider: ranked.providerID, code: code, in: glyphArea, color: .labelColor, allowImage: false)
            case .jar, .logo:
                // Above the fill line the glyphs sit on the opaque track: light on the dark-mode
                // track, dark on the light-mode track. Inside the fill they take the contrast
                // colour for that severity. Neither depends on what is behind the status item.
                NSGraphicsContext.saveGraphicsState()
                NSRect(x: bar.minX, y: bar.minY + fillHeight, width: bar.width, height: bar.height - fillHeight).clip()
                Self.drawGlyphs(provider: ranked.providerID, code: code, in: bar,
                                color: isDark ? NSColor(calibratedWhite: 0.93, alpha: 1) : NSColor(calibratedWhite: 0.1, alpha: 1), allowImage: true)
                NSGraphicsContext.restoreGraphicsState()
                if fillHeight > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    fillRect.clip()
                    Self.drawGlyphs(provider: ranked.providerID, code: code, in: bar, color: contrastColor(for: ranked.metric.usedPercent), allowImage: true)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
        }
    }
}

@MainActor private final class FlippedDocumentView: NSView { override var isFlipped: Bool { true } }

@MainActor final class DropdownView: NSView {
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let document = FlippedDocumentView()
    var refreshAction: (() -> Void)?
    var reconnectAction: ((String) -> Void)?
    var settingsAction: (() -> Void)?
    var quitAction: (() -> Void)?
    var renderNow: Date?
    var polling: [String: PollingPolicy] = [:]
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        document.addSubview(stack)
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        sizeDocument()
    }
    private func sizeDocument() {
        let width = max(1, max(scroll.contentSize.width, bounds.width - 16))
        let height = max(scroll.contentSize.height, ceil(stack.fittingSize.height))
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        if document.frame != frame { document.frame = frame }
        if stack.frame != document.bounds { stack.frame = document.bounds }
    }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    private func line(_ value: String, bold: Bool = false, tooltip: String? = nil, color: NSColor? = nil) {
        let field = NSTextField(labelWithString: value)
        field.font = bold ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 11)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = tooltip
        if let color { field.textColor = color }
        field.setAccessibilityLabel(tooltip.map { value + ", " + $0 } ?? value)
        stack.addArrangedSubview(field)
    }
    private func button(_ title: String, action: @escaping () -> Void) {
        let control = NSButton(title: title, target: nil, action: nil)
        control.bezelStyle = .texturedRounded
        control.setAccessibilityLabel(title)
        control.action = #selector(press(_:)); control.target = self
        actions[ObjectIdentifier(control)] = action
        stack.addArrangedSubview(control)
    }
    func focusFirstButton() {
        guard let control = stack.arrangedSubviews.compactMap({ $0 as? NSButton }).first else { return }
        window?.makeFirstResponder(control)
    }
    private var actions: [ObjectIdentifier: () -> Void] = [:]
    @objc private func press(_ sender: NSButton) { actions[ObjectIdentifier(sender)]?() }
    func performButton(_ title: String) {
        (stack.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.title == title })?.performClick(nil)
    }
    func hasButton(_ title: String) -> Bool {
        stack.arrangedSubviews.compactMap { $0 as? NSButton }.contains { $0.title == title }
    }
    func update(_ rows: [ProfileDisplay], demo: Bool = false) {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        actions.removeAll()
        if demo { line("Demo data", bold: true) }
        var currentProvider = ""
        if rows.isEmpty { line("No enabled accounts", bold: true) }
        for row in rows {
            let provider = row.profile.providerID.rawValue.capitalized
            if provider != currentProvider { line(provider, bold: true); currentProvider = provider }
            line("\(row.profile.label) · \(row.health.rawValue)", bold: true)
            let interval = polling[row.profile.providerID.rawValue]?.interval
            let fetchAge = row.fetchedAge.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            if let snapshot = row.snapshot {
                if snapshot.metrics.isEmpty { line("Quota metrics unavailable") }
                for metric in snapshot.metrics {
                    if let observations = metric.conflictingObservations {
                        line("  \(metric.label): conflicted · usage unknown")
                        for observation in observations {
                            let amount = String(format: "%.2f%%", observation.usedPercent)
                            let reset = observation.resetsAt.map(resetText) ?? "reset unknown"
                            let absolute = observation.resetsAt.flatMap(displayableResetDate).map {
                                DateFormatter.localizedString(from: $0, dateStyle: .full, timeStyle: .long)
                            }
                            line("    Observed \(amount) · \(reset)", tooltip: absolute)
                        }
                        continue
                    }
                    let percent = metric.usedPercent.map { String(format: "%.2f%%", $0) } ?? "unknown"
                    let time = row.expirations.metrics.contains(metric.id) ? "reset due" :
                        (metric.resetsAt.map { resetText($0) } ?? "reset unknown")
                    let absolute = metric.resetsAt.flatMap(displayableResetDate).map {
                        DateFormatter.localizedString(from: $0, dateStyle: .full, timeStyle: .long)
                    }
                    let color: NSColor? = switch severity(metric.usedPercent) {
                    case .warning: .systemYellow
                    case .critical: .systemRed
                    default: nil
                    }
                    line("  \(metric.label): \(percent) · \(time)", tooltip: absolute, color: color)
                }
                for (index, balance) in snapshot.balances.enumerated() {
                    let unknown: String
                    switch balance.state {
                    case .known, .unknown: unknown = "unknown"
                    case .unavailable: unknown = "unavailable"
                    case .inapplicable: unknown = "not applicable"
                    }
                    let amount = balance.unlimited ? "unlimited" : balance.remaining.map { "\($0) \(balance.currency ?? "credits")" } ?? unknown
                    let expiry = row.expirations.balances.contains(index) ? " · expired (cached amount)" :
                        (balance.expiresAt.map { " · " + expiryText($0) } ?? " · expiry unknown")
                    line("  \(balance.label): \(amount)\(expiry)")
                }
                for amount in snapshot.informationalAmounts {
                    line("  \(amount.label): \(amount.amount) \(amount.currency)")
                }
                if let credits = snapshot.resetCredits {
                    let cached = row.expirations.credits.isEmpty ? "" : " (reported; some details expired)"
                    line("  Earned resets: \(credits.availableCount.map(String.init) ?? "unknown") available\(cached)")
                    line("  Applicable: \(credits.applicableCount.map(String.init) ?? "unknown")")
                    if let details = credits.details {
                        for (index, credit) in details.enumerated() {
                            let expiry = row.expirations.credits.contains(index) ? "expired (cached detail)" :
                                (credit.expiresAt.map(expiryText) ?? "expiry unknown")
                            line("    \(credit.label): \(expiry)")
                        }
                    } else { line("  Reset detail and expiry unknown") }
                }
                for capability in snapshot.capabilities { line("  \(capability)") }
                if let age = fetchAge { line(fetchedLine(age: age, interval: interval)) }
                for warning in snapshot.warnings { line("  \(warning)") }
            }
            if fetchAge == nil, let interval { line(pollsLine(interval: interval)) }
            if let message = row.message { line("  \(message)") }
            if row.health == .unauthenticated && !demo {
                button("Connect / Authorize \(row.profile.label)") { [weak self] in self?.reconnectAction?(row.profile.id) }
            }
        }
        button("Refresh") { [weak self] in self?.refreshAction?() }
        button("Settings") { [weak self] in self?.settingsAction?() }
        button("Quit") { [weak self] in self?.quitAction?() }
        sizeDocument()
        document.needsLayout = true
        document.needsDisplay = true
    }
    private func resetText(_ date: Date) -> String {
        resetCountdownText(resetAt: date, now: renderNow ?? Date())
    }
    private func expiryText(_ date: Date) -> String {
        guard displayableResetDate(date) != nil else { return "expiry unknown" }
        let value = resetText(date)
        return value == "reset due" ? "expired" : "expires \(value)"
    }
}

extension UserDefaults: PollingStorage {}

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    private let monitor: Monitor
    private var pollingPersistence: PollingPersistence?
    private let presentationClock: any MonitorClock
    private let countStore: any IndicatorPreferenceStore
    private var count: Int
    private let item = NSStatusBar.system.statusItem(withLength: RingView.statusWidth(for: 3))
    private let rings = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: 3), height: 22))
    private let popover = NSPopover()
    private let dropdown = DropdownView(frame: NSRect(x: 0, y: 0, width: 340, height: 420))
    private var profiles: [AccountProfile] = []
    private var cadence: Timer?
    private var streamTask: Task<Void, Never>?
    private var lastDisplay: MonitorDisplay?
    private var lastProjection: PresentationState?
    private var lastPresentationWall: Date?
    private var latestRevision: UInt64 = 0
    private var observations: [Int: SnapshotExpirations] = [:]
    private var localQueryPending = false
    private var lastDropdownRows: [ProfileDisplay] = []
    private var router: AppActionRouter!
    private var statusDrawingInstalled = false
    private let demo: Bool
    private let demoAppearance: NSAppearance.Name?
    private let statisticsPath: String?
    private var statisticsOutput: StatisticsOutput?
    private let defaults: UserDefaults
    private let nudger: (any SessionNudging)?
    private let storedAttempts: [String: Date]
    /// Seams for tests: the process termination and the nudge toggle.
    var terminateProcesses: () -> Void = { ProcessRegistry.shared.terminateAll() }
    var nudgeToggled: ((Bool) -> Void)?
    init(demo: Bool = false, demoAppearance: NSAppearance.Name? = nil, statisticsPath: String? = nil,
         monitor: Monitor? = nil, presentationClock: (any MonitorClock)? = nil,
         demoClockSource: any MonitorClock = SystemMonitorClock(),
         countStore: (any IndicatorPreferenceStore)? = nil, actionRouter: AppActionRouter? = nil,
         defaults: UserDefaults = .standard, nudger: (any SessionNudging)? = ClaudeCLINudger()) {
        self.demo = demo; self.demoAppearance = demoAppearance
        self.statisticsPath = statisticsPath
        self.defaults = defaults; self.nudger = demo ? nil : nudger
        storedAttempts = defaults.data(forKey: "nudge.lastAttempts").flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        self.monitor = demo ? Monitor(credentials: CredentialStore(files: DemoCredentialFiles(), keychain: DemoKeychain()),
                                      transport: DemoTransport())
            : (monitor ?? Monitor(reactiveRecheck: true, terminateChildren: { ProcessRegistry.shared.terminateAll() }, nudger: nudger,
                                  attemptStore: Self.attemptWriter(defaults)))
        if let presentationClock { self.presentationClock = presentationClock }
        else if demo { self.presentationClock = FrozenDemoClock(base: demoClockSource) }
        else { self.presentationClock = SystemMonitorClock() }
        let selectedStore: any IndicatorPreferenceStore = demo ? MemoryIndicatorStore() : (countStore ?? DefaultsIndicatorStore())
        self.countStore = selectedStore
        self.count = indicatorCount(selectedStore.loadCount())
        super.init()
        let liveRouter = AppActionRouter(demo: demo, refresh: { [weak self] in
            Task { await self?.monitor.manualRefresh() }
        }, connect: { [weak self] id in
            Task { await self?.monitor.reconnect(id) }
        }, accounts: { [weak self] in self?.showSettings() }, quit: { [weak self] in
            Task { @MainActor in
                await self?.monitor.stop()
                NSApp.terminate(nil)
            }
        })
        if let actionRouter, actionRouter.demo == demo { router = actionRouter }
        else { router = liveRouter }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if demo, let demoAppearance, let appearance = NSAppearance(named: demoAppearance) {
            NSApp.appearance = appearance
            item.button?.appearance = appearance
            rings.appearance = appearance
            dropdown.appearance = appearance
        }
        installStatusDrawing()
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = dropdown
        popover.behavior = .transient
        configureDropdownActions()
        if demo {
            installDemo()
            DispatchQueue.main.async { [weak self] in self?.toggle() }
            Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in
                Task { @MainActor in NSApp.terminate(nil) }
            }
        }
        else {
            profiles = loadProfiles()
            if let statisticsPath {
                var protectedPaths = [CredentialStore.defaultCodexPath, CredentialStore.defaultClaudePath]
                for profile in profiles {
                    switch profile.source {
                    case .codexFile(let path), .claudeFile(let path): protectedPaths.append(path)
                    case .claudeDefaultDiscovery: break
                    }
                }
                do {
                    statisticsOutput = try StatisticsOutput(path: statisticsPath, forbiddenPaths: protectedPaths)
                } catch {
                    try? FileHandle.standardError.write(contentsOf: Data("Statistics output unavailable\n".utf8))
                    exit(2)
                }
            }
            streamTask = Task {
                let changes = await monitor.changes()
                for await value in changes {
                    self.apply(value)
                    if let writer = self.statisticsOutput {
                        let counts = await monitor.statistics()
                        do { try writer.write(counts) }
                        catch {
                            try? FileHandle.standardError.write(contentsOf: Data("Statistics output unavailable\n".utf8))
                            await monitor.stop()
                            exit(2)
                        }
                    }
                }
            }
            let persistence = PollingPersistence(UserDefaults.standard)
            pollingPersistence = persistence
            let initial = persistence.load(["claude", "codex"])
            Task { await monitor.setPolling(initial); await restoreNudge(); await monitor.setProfiles(profiles) }
            scheduleCadence()
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: NSNotification.Name("NSSystemClockDidChangeNotification"), object: nil)
        }
    }
    func updateDropdown(_ rows: [ProfileDisplay]) { dropdown.update(rows, demo: demo) }
    func pressDropdownButton(_ title: String) { dropdown.performButton(title) }
    func hasDropdownButton(_ title: String) -> Bool { dropdown.hasButton(title) }
    func routeConnect(_ id: String) { router.connect(id) }
    func configureDropdownActions() {
        dropdown.refreshAction = { [weak self] in self?.router.refresh() }
        dropdown.reconnectAction = { [weak self] id in self?.router.connect(id) }
        dropdown.settingsAction = { [weak self] in self?.showSettingsMenu() }
        dropdown.quitAction = { [weak self] in self?.router.quit() }
    }
    func prepareDemo() { guard demo else { return }; configureDropdownActions(); installDemo() }
    func performDropdownButton(_ title: String) { dropdown.performButton(title) }
    var presentedCount: Int { count }
    var statusWidth: CGFloat { item.length }
    var currentPresentation: PresentationState? { lastProjection }
    var statusDrawingView: RingView { rings }
    var statusTooltip: String? { item.button?.toolTip }
    var statusAccessibilitySummary: String? { item.button?.accessibilityLabel() }
    func receiveDisplay(_ value: MonitorDisplay) { apply(value) }
    func installStatusDrawing() {
        guard !statusDrawingInstalled else { return }
        statusDrawingInstalled = true
        item.button?.addSubview(rings)
        rings.appearanceChanged = { [weak self] in self?.refreshProjection(); self?.requestLocalDisplay() }
        rings.willDraw = { [weak self] in self?.validateBeforeStatusDraw() }
        item.button?.action = #selector(toggle)
        item.button?.target = self
        resizeStatusItem()
    }
    func applicationWillTerminate(_ notification: Notification) {
        cadence?.invalidate(); streamTask?.cancel(); Task { await monitor.stop() }
        nudger?.waitForCompletion(upTo: 5)
        terminateProcesses()
    }
    /// The only writer of `nudge.lastAttempts`: the monitor calls it on every change of its attempt map.
    nonisolated static func attemptWriter(_ defaults: UserDefaults) -> @Sendable ([String: Date]) -> Void {
        nonisolated(unsafe) let store = defaults   // UserDefaults is thread-safe
        return { store.set(try? JSONEncoder().encode($0), forKey: "nudge.lastAttempts") }
    }
    private var nudgeOn: Bool { defaults.object(forKey: "claudeNudgeEnabled") as? Bool ?? true }   // an absent key means on
    func restoreNudge() async {
        await monitor.restoreNudgeAttempts(storedAttempts)
        await monitor.setNudgeEnabled(nudgeOn)
    }
    @objc private func toggleNudge(_ sender: NSMenuItem) {
        guard !demo else { return }
        let enabled = sender.state != .on
        defaults.set(enabled, forKey: "claudeNudgeEnabled")
        nudgeToggled?(enabled)
        Task { await monitor.setNudgeEnabled(enabled) }
    }
    private func scheduleCadence() {
        cadence?.invalidate()
        let timer = Timer(timeInterval: cycleTick, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.monitor.refresh() }
        }
        timer.tolerance = cadenceTolerance
        cadence = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            refreshProjection()
            requestLocalDisplay()
            if let lastProjection {
                dropdown.renderNow = lastPresentationWall
                updateDropdown(lastProjection.profiles); lastDropdownRows = lastProjection.profiles
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            dropdown.window?.makeKey()
            dropdown.focusFirstButton()
            if !demo { Task { await monitor.dropdownOpened() } }
        }
    }
    @objc private func sleep() { Task { await monitor.sleep() } }
    @objc private func wake() {
        refreshProjection()
        Task { await monitor.wake(); requestLocalDisplay() }
    }
    @objc private func clockChanged() {
        refreshProjection()
        Task { await monitor.clockChanged(); requestLocalDisplay() }
    }
    private func requestLocalDisplay() {
        guard !demo, !localQueryPending else { return }
        localQueryPending = true
        Task {
            let result = await monitor.displayOnly()
            localQueryPending = false
            apply(result)
        }
    }
    private func resizeStatusItem() {
        let width = RingView.statusWidth(for: count)
        item.length = width
        rings.count = count
        rings.frame = NSRect(x: 0, y: 0, width: width, height: item.button?.bounds.height ?? 22)
        item.button?.needsDisplay = true
    }
    func selectCount(_ value: Int) {
        guard (1...8).contains(value) else { return }
        count = value
        countStore.saveCount(value)
        resizeStatusItem()
        refreshProjection()
        requestLocalDisplay()
    }
    @objc private func selectCountMenuItem(_ sender: NSMenuItem) { selectCount(sender.tag) }
    @objc private func openAccounts() { router.accounts() }
    /// Presents the About panel; tests inject a probe. The default activates the
    /// accessory app so the standard panel comes to the front.
    var aboutPresenter: ([NSApplication.AboutPanelOptionKey: Any]) -> Void = { options in
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
    @objc private func showAbout() { aboutPresenter(AppVersion.aboutPanelOptions()) }
    func settingsMenu() -> NSMenu {
        let menu = NSMenu(title: "Settings")
        menu.autoenablesItems = false
        let indicators = NSMenuItem(title: "Indicators", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Indicators")
        for number in 1...8 {
            let option = NSMenuItem(title: String(number), action: #selector(selectCountMenuItem(_:)), keyEquivalent: "")
            option.target = self; option.tag = number
            option.state = number == count ? .on : .off
            submenu.addItem(option)
        }
        menu.setSubmenu(submenu, for: indicators)
        menu.addItem(indicators)
        menu.addItem(.separator())
        let accounts = NSMenuItem(title: "Accounts…", action: #selector(openAccounts), keyEquivalent: "")
        accounts.target = self; accounts.isEnabled = !demo
        menu.addItem(accounts)
        let about = NSMenuItem(title: "About Limitaur…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let nudge = NSMenuItem(title: "Run claude when the Claude session has expired", action: #selector(toggleNudge(_:)), keyEquivalent: "")
        nudge.target = self; nudge.isEnabled = !demo
        nudge.state = nudgeOn ? .on : .off
        menu.addItem(nudge)
        return menu
    }
    private func showSettingsMenu() {
        settingsMenu().popUp(positioning: nil, at: NSPoint(x: 12, y: dropdown.bounds.midY), in: dropdown)
    }
    private func apply(_ value: MonitorDisplay) {
        guard value.revision >= latestRevision else { return }
        latestRevision = value.revision
        lastDisplay = value
        let changed = intervalsDiffer(dropdown.polling, value.polling)
        dropdown.polling = value.polling
        pollingPersistence?.save(value.polling)
        refreshProjection(rebuild: changed)
    }
    private func validateBeforeStatusDraw() {
        guard lastDisplay != nil else { return }
        let previous = lastProjection
        refreshProjection()
        guard let current = lastProjection else { return }
        if previous == nil || previous?.selected != current.selected ||
           previous?.providerWarning != current.providerWarning || previous?.unavailableProviders != current.unavailableProviders ||
           previous?.signInProviders != current.signInProviders ||
           previous?.accessibilitySummary != current.accessibilitySummary ||
           !sameDropdownRows(previous?.profiles ?? [], current.profiles) {
            requestLocalDisplay()
        }
    }
    private func refreshProjection(rebuild: Bool = false) {
        guard let value = lastDisplay else { return }
        let wall = presentationClock.wallNow(), mono = presentationClock.monotonicNow()
        let before = observations
        let projected = projectDisplay(value, count: count, wallNow: wall,
                                       monotonicNow: mono, observations: &observations)
        lastPresentationWall = wall
        if observations != before {
            let seen = observations
            Task { await monitor.observePresentationExpirations(seen) }
        }
        lastProjection = projected
        if rings.selected != projected.selected { rings.selected = projected.selected }
        if rings.unavailableProviders != projected.unavailableProviders { rings.unavailableProviders = projected.unavailableProviders }
        if rings.signInProviders != projected.signInProviders { rings.signInProviders = projected.signInProviders }
        if item.button?.accessibilityLabel() != projected.accessibilitySummary {
            item.button?.setAccessibilityLabel(projected.accessibilitySummary)
        }
        if item.button?.toolTip != projected.accessibilitySummary {
            item.button?.toolTip = projected.accessibilitySummary
            rings.toolTip = projected.accessibilitySummary
        }
        if popover.isShown && (rebuild || !sameDropdownRows(lastDropdownRows, projected.profiles)) {
            dropdown.renderNow = wall
            updateDropdown(projected.profiles)
            lastDropdownRows = projected.profiles
        }
    }
    private func sameDropdownRows(_ left: [ProfileDisplay], _ right: [ProfileDisplay]) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.profile == b.profile && a.snapshot == b.snapshot && a.health == b.health &&
            a.message == b.message && a.expirations == b.expirations &&
            a.fetchedAge.map { floor($0 / 60) } == b.fetchedAge.map { floor($0 / 60) }
        }
    }
    private func loadProfiles() -> [AccountProfile] {
        if let data = UserDefaults.standard.data(forKey: "profiles"),
           let saved = try? JSONDecoder().decode([AccountProfile].self, from: data) {
            return normalizedProfiles(saved)
        }
        return [
            AccountProfile(id: "codex-default", providerID: "codex", label: "Default", source: .codexFile(CredentialStore.defaultCodexPath)),
            AccountProfile(id: "claude-default", providerID: "claude", label: "Default", source: .claudeDefaultDiscovery)
        ]
    }
    private func saveProfiles() {
        guard !demo else { return }
        profiles = normalizedProfiles(profiles)
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "profiles") }
        Task { await monitor.setProfiles(profiles) }
    }
    private func showSettings() {
        guard !demo else { return }
        var draft = profiles
        while true {
            let alert = NSAlert()
            alert.messageText = "Accounts"
            alert.informativeText = "Paths and labels are saved locally. Connect authorizes an existing Claude Keychain item. When the Claude session has expired, Limitaur runs claude (at most hourly) so Claude Code renews it; turn this off in Settings if unwanted."
            let container = NSStackView()
            container.orientation = .vertical; container.spacing = 7
            var controls: [(String, NSButton, NSTextField, NSPopUpButton, NSTextField, NSButton)] = []
            for profile in draft {
                let enabled = NSButton(checkboxWithTitle: profile.providerID.rawValue.capitalized, target: nil, action: nil)
                enabled.state = profile.enabled ? .on : .off
                let label = NSTextField(string: profile.label)
                label.placeholderString = "Account label"
                label.setAccessibilityLabel("\(profile.providerID.rawValue) account label")
                let mode = NSPopUpButton(frame: .zero, pullsDown: false)
                if profile.providerID == "claude" {
                    mode.addItems(withTitles: ["Existing Keychain item", "Credential file"])
                    mode.selectItem(at: profile.source == .claudeDefaultDiscovery ? 0 : 1)
                } else { mode.addItem(withTitle: "Credential file") }
                mode.setAccessibilityLabel("Credential source")
                let path: String
                switch profile.source {
                case .codexFile(let p), .claudeFile(let p): path = p
                case .claudeDefaultDiscovery: path = ""
                }
                let source = NSTextField(string: path)
                source.placeholderString = "Absolute file path, if selected"
                source.setAccessibilityLabel("Credential file path")
                let remove = NSButton(checkboxWithTitle: "Remove", target: nil, action: nil)
                let fields: [NSView] = [enabled, label, mode, source, remove]
                for view in fields { container.addArrangedSubview(view) }
                controls.append((profile.id, enabled, label, mode, source, remove))
            }
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: min(360, max(115, CGFloat(draft.count) * 124))))
            scroll.hasVerticalScroller = true
            scroll.documentView = container
            container.frame = NSRect(x: 0, y: 0, width: 320, height: max(scroll.contentSize.height, ceil(container.fittingSize.height)))
            alert.accessoryView = scroll
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Add Codex")
            alert.addButton(withTitle: "Add Claude")
            let result = alert.runModal()
            if result == .alertSecondButtonReturn { return }
            var invalid = false
            var removed = Set<String>()
            for (id, enabled, label, mode, source, remove) in controls {
                if remove.state == .on { removed.insert(id); continue }
                guard let index = draft.firstIndex(where: { $0.id == id }) else { continue }
                let value = source.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[index].enabled = enabled.state == .on
                draft[index].label = label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if draft[index].providerID == "claude" && mode.indexOfSelectedItem == 0 {
                    draft[index].source = .claudeDefaultDiscovery
                } else {
                    if !value.hasPrefix("/") { invalid = true }
                    draft[index].source = draft[index].providerID == "codex" ? .codexFile(value) : .claudeFile(value)
                }
            }
            draft.removeAll { removed.contains($0.id) }
            if result == .alertFirstButtonReturn {
                if invalid { NSSound.beep(); continue }
                profiles = draft
                saveProfiles()
                return
            }
            let provider: ProviderID = result == .alertThirdButtonReturn ? "codex" : "claude"
            draft.append(AccountProfile(id: UUID().uuidString, providerID: provider, label: "New account",
                                        source: provider == "codex" ? .codexFile(CredentialStore.defaultCodexPath) : .claudeDefaultDiscovery,
                                        enabled: false))
        }
    }
    private func installDemo() {
        let now = presentationClock.wallNow()
        let freshUntil = presentationClock.monotonicNow() + 90
        let baseSnapshots = [
            UsageSnapshot(providerID: "codex", accountID: "demo", accountLabel: "Demo", fetchedAt: now,
                          metrics: [UsageMetric(id: "5h", label: "5h window", usedPercent: 25, resetsAt: now.addingTimeInterval(3600)),
                                    UsageMetric(id: "week", label: "Weekly", usedPercent: 85, resetsAt: now.addingTimeInterval(86400))],
                          balances: [CreditBalance(label: "Provider credits", remaining: Decimal(3))],
                          resetCredits: ResetCreditSummary(availableCount: 2, applicableCount: 1, details: nil)),
            UsageSnapshot(providerID: "claude", accountID: "demo", accountLabel: "Demo", fetchedAt: now,
                          metrics: [UsageMetric(id: "session", label: "Session", usedPercent: 98, resetsAt: now.addingTimeInterval(600))])
        ]
        var snapshots: [UsageSnapshot] = baseSnapshots
        for index in 0..<8 {
            let providerID: ProviderID = index.isMultiple(of: 2) ? ProviderID("codex") : ProviderID("claude")
            let accountID: AccountID = AccountID("demo-\(index)")
            let accountLabel: String = "Demo \(index + 1)"
            let resetAt: Date = now.addingTimeInterval(TimeInterval(1800 + index * 300))
            let metric: UsageMetric = UsageMetric(id: "window-\(index)", label: "Window \(index + 1)",
                                                  usedPercent: Double(10 + index * 5), resetsAt: resetAt)
            let balance: CreditBalance = CreditBalance(label: "Provider credits", remaining: Decimal(index))
            let snapshot: UsageSnapshot = UsageSnapshot(providerID: providerID, accountID: accountID,
                                                        accountLabel: accountLabel, fetchedAt: now,
                                                        metrics: [metric], balances: [balance])
            snapshots.append(snapshot)
        }
        var rows: [ProfileDisplay] = []
        for snapshot in snapshots {
            let source: CredentialSource = snapshot.providerID == "codex" ? .codexFile("/demo") : .claudeFile("/demo")
            let profileID: String = snapshot.providerID.rawValue + "-" + snapshot.accountID.rawValue
            let profile: AccountProfile = AccountProfile(id: profileID, providerID: snapshot.providerID,
                                                         label: snapshot.accountLabel, source: source)
            let row: ProfileDisplay = ProfileDisplay(profile: profile, snapshot: snapshot,
                                                     health: .healthy, message: nil, fetchedAge: 0,
                                                     freshnessDeadline: freshUntil,
                                                     snapshotGeneration: rows.count + 1)
            rows.append(row)
        }
        rows.sort { left, right in
            if left.profile.providerID != right.profile.providerID {
                return left.profile.providerID < right.profile.providerID
            }
            return left.profile.id < right.profile.id
        }
        let identity = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, Int)? in
            guard let generation = row.snapshotGeneration, let snapshot = row.snapshot else { return nil }
            return (snapshot.providerID.rawValue + "\u{1f}" + snapshot.accountID.rawValue, generation)
        })
        let candidates = rankMetrics(snapshots, wallNow: now, maximumCount: 8).compactMap { metric -> PresentationCandidate? in
            let key = metric.providerID.rawValue + "\u{1f}" + metric.accountID.rawValue
            guard let generation = identity[key] else { return nil }
            return PresentationCandidate(metric: metric, freshnessDeadline: freshUntil, snapshotGeneration: generation)
        }
        let display = MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil, polling: demoPolling)
        apply(display)
        if let lastProjection { dropdown.renderNow = now; updateDropdown(lastProjection.profiles) }
    }
}
