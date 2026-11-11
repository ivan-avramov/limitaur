import AppKit
import SwiftUI
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
    /// User code overrides; an overridden provider draws its code as text, never its bundle image.
    var providerCodes: [String: String] = [:] { didSet { needsDisplay = true } }
    private func glyph(for provider: ProviderID) -> String { providerGlyph(for: provider, overrides: providerCodes) }
    private func mask(for provider: ProviderID) -> CGImage? {
        normalizedProviderCode(providerCodes[provider.rawValue.lowercased()] ?? "") == nil ? ProviderGlyphImages.mask(for: provider) : nil
    }
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
    /// The usual provider font, or for a code wider than `width` (say "WW") the largest smaller size that fits.
    static func providerFont(_ text: String, width: CGFloat) -> NSFont {
        var font = text.count > 1 ? pairGlyphFont : glyphFont
        while font.pointSize > 4, (text as NSString).size(withAttributes: [.font: font]).width > width {
            font = NSFont.systemFont(ofSize: font.pointSize - 0.25, weight: .bold)
        }
        return font
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
    private func drawGlyphs(provider: ProviderID, code: String, in slot: NSRect, color: NSColor, allowImage: Bool) {
        let rects = Self.glyphRects(in: slot)
        if allowImage, let mask = mask(for: provider) {
            Self.draw(mask: mask, color: color, centeredIn: rects.provider)
        } else {
            let text = glyph(for: provider)
            Self.draw(text: text, font: Self.providerFont(text, width: rects.provider.width), color: color, centeredIn: rects.provider)
        }
        Self.draw(text: code, font: code.count > 1 ? Self.pairFont : Self.codeFont, color: color, centeredIn: rects.code)
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
            if Self.layout == .logo, index < selected.count, let mask = mask(for: selected[index].providerID) {
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
                let provider = unavailableProviders[missing], code = glyph(for: provider)
                let rects = Self.glyphRects(in: glyphArea)
                Self.draw(text: code, font: Self.providerFont(code, width: rects.provider.width),
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
                drawGlyphs(provider: ranked.providerID, code: code, in: glyphArea, color: .labelColor, allowImage: false)
            case .jar, .logo:
                // Above the fill line the glyphs sit on the opaque track: light on the dark-mode
                // track, dark on the light-mode track. Inside the fill they take the contrast
                // colour for that severity. Neither depends on what is behind the status item.
                NSGraphicsContext.saveGraphicsState()
                NSRect(x: bar.minX, y: bar.minY + fillHeight, width: bar.width, height: bar.height - fillHeight).clip()
                drawGlyphs(provider: ranked.providerID, code: code, in: bar,
                                color: isDark ? NSColor(calibratedWhite: 0.93, alpha: 1) : NSColor(calibratedWhite: 0.1, alpha: 1), allowImage: true)
                NSGraphicsContext.restoreGraphicsState()
                if fillHeight > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    fillRect.clip()
                    drawGlyphs(provider: ranked.providerID, code: code, in: bar, color: contrastColor(for: ranked.metric.usedPercent), allowImage: true)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
        }
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
    let dropdownModel = DropdownModel()
    private lazy var dropdownHost: NSHostingController<DropdownPanel> = {
        let host = NSHostingController(rootView: DropdownPanel(model: dropdownModel))
        host.sizingOptions = .preferredContentSize
        return host
    }()
    private(set) var settings: SettingsModel!
    private var lastStatusRows: [ProfileDisplay] = []
    private var profiles: [AccountProfile] = []
    private var cadence: Timer?
    /// One-shot refresh at the shared budget's reset and freshness deadline, re-armed when either changes.
    private var budgetRefresh: Timer?
    private var budgetRefreshKey: (Date, TimeInterval?)?
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
    /// Local display settings; demo neither loads nor stores them.
    private var claudeResetDay: MonthlyResetDay = .default
    private var budgetConfig = SettingsModel.defaultBudget
    /// The applied provider code overrides, stored as `providerCodes`.
    private(set) var providerCodes: [String: String] = [:]
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
        if !demo {
            claudeResetDay = defaults.string(forKey: "claudeSpendResetDay").flatMap(MonthlyResetDay.init(storage:)) ?? .default
            budgetConfig = defaults.data(forKey: "sharedBudget")
                .flatMap { try? JSONDecoder().decode(SharedBudgetConfig.self, from: $0) }?.validated ?? SettingsModel.defaultBudget
            providerCodes = validatedProviderCodes(defaults.dictionary(forKey: "providerCodes")?.compactMapValues { $0 as? String } ?? [:])
        }
        self.monitor = demo ? Monitor(credentials: CredentialStore(files: DemoCredentialFiles(), keychain: DemoKeychain(),
                                                                         cursorKeychain: DemoKeychain()),
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
        }, accounts: { [weak self] in
            guard let self else { return }
            popover.performClose(nil)
            settingsPresenter(settings)
        }, quit: { [weak self] in
            Task { @MainActor in
                await self?.monitor.stop()
                NSApp.terminate(nil)
            }
        })
        if let actionRouter, actionRouter.demo == demo { router = actionRouter }
        else { router = liveRouter }
        dropdownModel.demo = demo
        rings.providerCodes = providerCodes; dropdownModel.providerCodes = providerCodes
        settings = makeSettings()
    }
    /// The Settings model over the current profile list; every change goes through the save path.
    private func makeSettings() -> SettingsModel {
        SettingsModel(profiles: profiles, indicatorCount: count, nudgeEnabled: nudgeOn, editable: !demo,
                      claudeResetDay: claudeResetDay, budget: budgetConfig,
                      onProfiles: { [weak self] list in self?.profiles = list; self?.saveProfiles() },
                      onIndicatorCount: { [weak self] in self?.selectCount($0) },
                      onNudge: { [weak self] in self?.setNudge($0) },
                      onConnect: { [weak self] in self?.router.connect($0) },
                      onAbout: { [weak self] in self?.showAbout() },
                      onClaudeResetDay: { [weak self] in self?.setClaudeResetDay($0) },
                      onBudget: { [weak self] in self?.setBudget($0) },
                      providerCodes: providerCodes, onProviderCodes: { [weak self] in self?.setProviderCodes($0) })
    }
    /// Applies at once to the status item and the dropdown; the Settings model already holds it.
    private func setProviderCodes(_ codes: [String: String]) {
        providerCodes = validatedProviderCodes(codes)
        if !demo { defaults.set(providerCodes, forKey: "providerCodes") }
        rings.providerCodes = providerCodes
        dropdownModel.providerCodes = providerCodes
        item.button?.needsDisplay = true
    }
    private func setClaudeResetDay(_ day: MonthlyResetDay) {
        claudeResetDay = day
        if !demo { defaults.set(day.storage, forKey: "claudeSpendResetDay") }
        Task { await monitor.setSpendResetDay(day, for: "claude") }
    }
    private func setBudget(_ config: SharedBudgetConfig) {
        budgetConfig = config
        if !demo, let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: "sharedBudget") }
        refreshProjection(rebuild: true)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        if demo, let demoAppearance, let appearance = NSAppearance(named: demoAppearance) {
            NSApp.appearance = appearance
            item.button?.appearance = appearance
            rings.appearance = appearance
            dropdownHost.view.appearance = appearance
        }
        installStatusDrawing()
        popover.contentViewController = dropdownHost
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
            settings = makeSettings()
            if let statisticsPath {
                var protectedPaths = [CredentialStore.defaultCodexPath, CredentialStore.defaultClaudePath]
                for profile in profiles {
                    switch profile.source {
                    case .codexFile(let path), .claudeFile(let path): protectedPaths.append(path)
                    case .claudeDefaultDiscovery, .cursorDefaultDiscovery: break
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
            let initial = persistence.load(["claude", "codex", "cursor"])
            let resetDay = claudeResetDay
            Task {
                await monitor.setPolling(initial); await restoreNudge()
                await monitor.setSpendResetDay(resetDay, for: "claude"); await monitor.setProfiles(profiles)
            }
            scheduleCadence()
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: NSNotification.Name("NSSystemClockDidChangeNotification"), object: nil)
        }
    }
    func updateDropdown(_ rows: [ProfileDisplay]) {
        dropdownModel.rows = rows
        pushStatuses(rows)
    }
    private func pushStatuses(_ rows: [ProfileDisplay]) {
        guard !sameDropdownRows(lastStatusRows, rows) else { return }
        lastStatusRows = rows
        settings.updateStatuses(rows)
    }
    func pressDropdownButton(_ title: String) { dropdownModel.perform(title) }
    func hasDropdownButton(_ title: String) -> Bool { dropdownModel.actionTitles().contains(title) }
    func routeConnect(_ id: String) { router.connect(id) }
    func configureDropdownActions() {
        dropdownModel.refresh = { [weak self] in self?.router.refresh() }
        dropdownModel.connect = { [weak self] id in self?.router.connect(id) }
        dropdownModel.settings = { [weak self] in self?.openSettings() }
        dropdownModel.quit = { [weak self] in self?.router.quit() }
    }
    /// Demo presents the read-only Settings window directly; the router keeps its demo guard.
    private func openSettings() {
        guard demo else { return router.accounts() }
        popover.performClose(nil)
        settingsPresenter(settings)
    }
    /// Not visible for an accessory app, but gives Settings its standard key equivalents.
    private func installMainMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(), submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            item.submenu = submenu
            menu.addItem(item)
        }
        func entry(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command,
                   mine: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            if mine { item.target = self }
            return item
        }
        add("Limitaur", [entry("About Limitaur", #selector(menuAbout), "", mine: true), .separator(),
                         entry("Settings…", #selector(menuSettings), ",", mine: true), .separator(),
                         entry("Quit Limitaur", #selector(menuQuit), "q", mine: true)])
        add("Edit", [entry("Undo", Selector(("undo:")), "z"), entry("Redo", Selector(("redo:")), "z", [.command, .shift]),
                     .separator(), entry("Cut", #selector(NSText.cut(_:)), "x"), entry("Copy", #selector(NSText.copy(_:)), "c"),
                     entry("Paste", #selector(NSText.paste(_:)), "v"), entry("Select All", #selector(NSText.selectAll(_:)), "a")])
        add("Window", [entry("Close", #selector(NSWindow.performClose(_:)), "w")])
        NSApp.mainMenu = menu
    }
    @objc private func menuAbout() { showAbout() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuQuit() { router.quit() }
    func prepareDemo() { guard demo else { return }; configureDropdownActions(); installDemo() }
    func performDropdownButton(_ title: String) { dropdownModel.perform(title) }
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
        cadence?.invalidate(); budgetRefresh?.invalidate(); streamTask?.cancel(); Task { await monitor.stop() }
        nudger?.waitForCompletion(upTo: 5)
        terminateProcesses()
    }
    /// The only writer of `nudge.lastAttempts`: the monitor calls it on every change of its attempt map.
    nonisolated static func attemptWriter(_ defaults: UserDefaults) -> @Sendable ([String: Date]) -> Void {
        nonisolated(unsafe) let store = defaults   // UserDefaults is thread-safe
        return { store.set(try? JSONEncoder().encode($0), forKey: "nudge.lastAttempts") }
    }
    private var nudgeOn: Bool { defaults.object(forKey: "claudeNudgeEnabled") == nil || defaults.bool(forKey: "claudeNudgeEnabled") }   // an absent key means on
    func restoreNudge() async {
        await monitor.restoreNudgeAttempts(storedAttempts)
        await monitor.setNudgeEnabled(nudgeOn)
    }
    private func setNudge(_ enabled: Bool) {
        guard !demo else { return }
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
                dropdownModel.now = lastPresentationWall ?? Date()
                updateDropdown(lastProjection.profiles); lastDropdownRows = lastProjection.profiles
            }
            // Measure before showing, so the first open appears at its final height.
            dropdownHost.view.layoutSubtreeIfNeeded()
            popover.contentSize = dropdownHost.view.fittingSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            dropdownHost.view.window?.makeKey()
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
    /// Presents the Settings window; tests inject a probe. Demo reaches it without the router.
    var settingsPresenter: (SettingsModel) -> Void = { SettingsWindowController.show($0) }
    /// Presents the About panel; tests inject a probe. The default activates the
    /// accessory app so the standard panel comes to the front.
    var aboutPresenter: ([NSApplication.AboutPanelOptionKey: Any]) -> Void = { options in
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
    private func showAbout() { aboutPresenter(AppVersion.aboutPanelOptions()) }
    private func apply(_ value: MonitorDisplay) {
        guard value.revision >= latestRevision else { return }
        latestRevision = value.revision
        lastDisplay = value
        let changed = intervalsDiffer(dropdownModel.polling, value.polling)
        dropdownModel.polling = value.polling
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
        var projected = projectDisplay(value, count: count, wallNow: wall,
                                       monotonicNow: mono, observations: &observations)
        // The budget reads the projected, stale-marked rows, then joins the ranking.
        let budget = sharedBudget(budgetConfig, rows: projected.profiles, mainProfileIDs: settings.mainProfileIDs,
                                  wallNow: wall, monotonicNow: mono)
        if budget != nil {
            projected = projectDisplay(value, count: count, wallNow: wall, monotonicNow: mono,
                                       observations: &observations, budget: budget)
        }
        if dropdownModel.budget != budget { dropdownModel.budget = budget }
        armBudgetRefresh(budget, wall: wall, mono: mono)
        settings.updateReportedLimits(projected.profiles)
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
            dropdownModel.now = wall
            updateDropdown(projected.profiles)
            lastDropdownRows = projected.profiles
        } else { pushStatuses(projected.profiles) }
    }
    private func armBudgetRefresh(_ budget: SharedBudgetState?, wall: Date, mono: TimeInterval) {
        let key = budget.map { ($0.resetsAt, $0.freshnessDeadline) }
        guard !demo, key?.0 != budgetRefreshKey?.0 || key?.1 != budgetRefreshKey?.1 else { return }
        budgetRefresh?.invalidate(); budgetRefresh = nil; budgetRefreshKey = key
        guard let budget else { return }
        let waits = [budget.resetsAt.timeIntervalSince(wall), budget.freshnessDeadline.map { $0 - mono }].compactMap { $0 }
        guard let wait = waits.filter({ $0 > 0 && $0.isFinite }).min() else { return }
        let timer = Timer(timeInterval: min(wait, 30 * 24 * 60 * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.budgetRefresh = nil; self?.budgetRefreshKey = nil
                self?.refreshProjection(); self?.requestLocalDisplay()
            }
        }
        budgetRefresh = timer
        RunLoop.main.add(timer, forMode: .common)
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
        // The read-only Settings model shows the demo's own profiles; apply feeds it these rows.
        profiles = rows.map(\.profile)
        settings = makeSettings()
        lastStatusRows = []
        let display = MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil, polling: demoPolling)
        apply(display)
        if let lastProjection { dropdownModel.now = now; updateDropdown(lastProjection.profiles) }
    }
}
