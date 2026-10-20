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

@MainActor final class RingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    static func statusWidth(for count: Int) -> CGFloat { CGFloat(4 * indicatorCount(count) + 2 * (indicatorCount(count) - 1) + 16) }
    var count = 3 { didSet { needsDisplay = true } }
    var selected: [RankedMetric] = [] { didSet { needsDisplay = true } }
    var providerWarning = false { didSet { needsDisplay = true } }
    var stale = false { didSet { needsDisplay = true } }
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
    override func draw(_ dirtyRect: NSRect) {
        willDraw?()
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
        for index in 0..<indicatorCount(count) {
            let rect = NSRect(x: 4 + CGFloat(index * 6), y: bounds.midY - 8, width: 4, height: 16)
            NSColor(calibratedWhite: 0.22, alpha: 0.8).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            guard index < selected.count, let fill = ringFill(selected[index].metric.usedPercent) else {
                let dash = NSBezierPath()
                dash.lineWidth = 1
                dash.move(to: NSPoint(x: rect.minX, y: rect.midY))
                dash.line(to: NSPoint(x: rect.maxX, y: rect.midY))
                NSColor.secondaryLabelColor.setStroke()
                dash.stroke()
                continue
            }
            guard fill > 0 else { continue }
            let height = max(0.5, rect.height * CGFloat(fill))
            let bar = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            switch severity(selected[index].metric.usedPercent) {
            case .normal: NSColor.labelColor.setFill()
            case .warning: NSColor.systemYellow.setFill()
            case .critical: NSColor.systemRed.setFill()
            case .unknown: NSColor.secondaryLabelColor.setFill()
            }
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        }
        if providerWarning || stale {
            let marker = NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 5, y: bounds.maxY - 6, width: 4, height: 4))
            NSColor.systemOrange.setFill(); marker.fill()
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
                    let level = severity(metric.usedPercent).rawValue
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
                    line("  \(metric.label): \(percent) (\(level)) · \(time)", tooltip: absolute, color: color)
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
                if let age = row.fetchedAge, age.isFinite, age >= 0 {
                    line(age < Double(Int.max) ? "  Fetched \(Int(age))s ago" : "  Fetched time unavailable")
                }
                for warning in snapshot.warnings { line("  \(warning)") }
            }
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

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    private let monitor: Monitor
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
    init(demo: Bool = false, demoAppearance: NSAppearance.Name? = nil, statisticsPath: String? = nil,
         monitor: Monitor? = nil, presentationClock: (any MonitorClock)? = nil,
         demoClockSource: any MonitorClock = SystemMonitorClock(),
         countStore: (any IndicatorPreferenceStore)? = nil, actionRouter: AppActionRouter? = nil) {
        self.demo = demo; self.demoAppearance = demoAppearance
        self.statisticsPath = statisticsPath
        self.monitor = demo ? Monitor(credentials: CredentialStore(files: DemoCredentialFiles(), keychain: DemoKeychain()),
                                      transport: DemoTransport()) : (monitor ?? Monitor())
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
            Task { await monitor.setProfiles(profiles) }
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
    func applicationWillTerminate(_ notification: Notification) { cadence?.invalidate(); streamTask?.cancel(); Task { await monitor.stop() } }
    private func scheduleCadence() {
        cadence?.invalidate()
        let interval = pollInterval(jitter: Double.random(in: 0...1.5))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.monitor.refresh()
                self.scheduleCadence()
            }
        }
        timer.tolerance = 1
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
    func settingsMenu() -> NSMenu {
        let menu = NSMenu(title: "Settings")
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
        return menu
    }
    private func showSettingsMenu() {
        settingsMenu().popUp(positioning: nil, at: NSPoint(x: 12, y: dropdown.bounds.midY), in: dropdown)
    }
    private func apply(_ value: MonitorDisplay) {
        guard value.revision >= latestRevision else { return }
        latestRevision = value.revision
        lastDisplay = value
        refreshProjection()
    }
    private func validateBeforeStatusDraw() {
        guard lastDisplay != nil else { return }
        let previous = lastProjection
        refreshProjection()
        guard let current = lastProjection else { return }
        if previous == nil || previous?.selected != current.selected ||
           previous?.providerWarning != current.providerWarning ||
           previous?.accessibilitySummary != current.accessibilitySummary ||
           !sameDropdownRows(previous?.profiles ?? [], current.profiles) {
            requestLocalDisplay()
        }
    }
    private func refreshProjection() {
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
        let warning = projected.providerWarning
        let stale = projected.profiles.contains { $0.health == .stale }
        if rings.providerWarning != warning { rings.providerWarning = warning }
        if rings.stale != stale { rings.stale = stale }
        if item.button?.accessibilityLabel() != projected.accessibilitySummary {
            item.button?.setAccessibilityLabel(projected.accessibilitySummary)
        }
        if item.button?.toolTip != projected.accessibilitySummary {
            item.button?.toolTip = projected.accessibilitySummary
        }
        if popover.isShown && !sameDropdownRows(lastDropdownRows, projected.profiles) {
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
            alert.informativeText = "Paths and labels are saved locally. Connect authorizes an existing Claude Keychain item."
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
        let display = MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil)
        apply(display)
        if let lastProjection { dropdown.renderNow = now; updateDropdown(lastProjection.profiles) }
    }
}
