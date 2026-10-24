import AppKit
import Foundation
import Synchronization
import Testing
@testable import LimitaurCore
@testable import Limitaur

@MainActor private final class ActionProbe {
    var refreshes = 0
    var connections = 0
    var accounts = 0
    var quits = 0
    func router(demo: Bool) -> AppActionRouter {
        AppActionRouter(demo: demo, refresh: { self.refreshes += 1 },
                        connect: { _ in self.connections += 1 },
                        accounts: { self.accounts += 1 }, quit: { self.quits += 1 })
    }
}

@MainActor private final class CountStoreProbe: IndicatorPreferenceStore {
    var reads = 0
    var writes: [Int] = []
    private var value: Int
    init(_ value: Int) { self.value = value }
    func loadCount() -> Int { reads += 1; return value }
    func saveCount(_ count: Int) { writes.append(count); value = count }
}

@MainActor @Test func actualCountMenuUsesOnlyPresentationStore() {
    _ = NSApplication.shared
    let probe = ActionProbe(), store = CountStoreProbe(3)
    let controller = AppController(countStore: store, actionRouter: probe.router(demo: false))
    controller.configureDropdownActions()
    let menu = controller.settingsMenu()
    let options = menu.item(at: 0)!.submenu!
    #expect(options.numberOfItems == 8)
    #expect(options.item(at: 2)?.state == .on)
    let five = options.item(at: 4)!
    #expect(NSApp.sendAction(five.action!, to: five.target, from: five))
    #expect(controller.presentedCount == 5)
    #expect(controller.statusWidth == RingView.statusWidth(for: 5))
    #expect(store.writes == [5])
    #expect(probe.refreshes == 0 && probe.connections == 0 && probe.accounts == 0)
    controller.selectCount(8)
    controller.selectCount(1)
    #expect(controller.presentedCount == 1)
    #expect(store.writes == [5, 8, 1])
    #expect(probe.refreshes == 0)
}

@MainActor @Test func reachableDemoActionsStaySynthetic() {
    _ = NSApplication.shared
    let probe = ActionProbe(), store = CountStoreProbe(3)
    let controller = AppController(demo: true, countStore: store, actionRouter: probe.router(demo: true))
    controller.prepareDemo()
    controller.pressDropdownButton("Refresh")
    let unauthenticated = ProfileDisplay(
        profile: AccountProfile(id: "demo-unauthenticated", providerID: "claude", label: "Synthetic",
                                source: .claudeFile("/demo")), snapshot: nil,
        health: .unauthenticated, message: "Reconnect account", fetchedAge: nil)
    controller.updateDropdown([unauthenticated])
    #expect(!controller.hasDropdownButton("Connect / Authorize Synthetic"))
    controller.routeConnect("demo-unauthenticated")
    #expect(probe.refreshes == 0 && probe.connections == 0)
    let menu = controller.settingsMenu()
    #expect(menu.item(at: 2)?.isEnabled == false)
    let five = menu.item(at: 0)!.submenu!.item(at: 4)!
    #expect(NSApp.sendAction(five.action!, to: five.target, from: five))
    #expect(controller.presentedCount == 5)
    #expect(store.reads == 0 && store.writes.isEmpty)
    controller.pressDropdownButton("Quit")
    #expect(probe.quits == 1)
    #expect(probe.accounts == 0 && probe.refreshes == 0 && probe.connections == 0)
}

@MainActor @Test func defaultDemoFactoryStaysSyntheticAfterRealFreshnessWindow() throws {
    _ = NSApplication.shared
    let base = PresentationClock()
    let probe = ActionProbe(), store = CountStoreProbe(3)
    let controller = AppController(demo: true, demoClockSource: base, countStore: store,
                                   actionRouter: probe.router(demo: true))
    controller.installStatusDrawing()
    controller.prepareDemo()
    #expect(controller.currentPresentation?.selected.count == 3)
    #expect(controller.currentPresentation?.profiles.allSatisfy { $0.health == .healthy } == true)
    base.advance(299)
    let view = controller.statusDrawingView
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    #expect(controller.currentPresentation?.selected.count == 3)
    #expect(controller.currentPresentation?.profiles.allSatisfy { $0.health == .healthy } == true)
    let five = controller.settingsMenu().item(at: 0)!.submenu!.item(at: 4)!
    #expect(NSApp.sendAction(five.action!, to: five.target, from: five))
    #expect(controller.currentPresentation?.selected.count == 5)
    #expect(controller.currentPresentation?.profiles.allSatisfy { $0.health == .healthy } == true)
    controller.pressDropdownButton("Refresh")
    #expect(probe.refreshes == 0 && probe.connections == 0 && probe.accounts == 0)
    #expect(store.reads == 0 && store.writes.isEmpty)
}

@MainActor @Test func dropdownConnectAndRefreshFollowProductionRouter() {
    _ = NSApplication.shared
    let probe = ActionProbe()
    let controller = AppController(countStore: CountStoreProbe(3), actionRouter: probe.router(demo: false))
    controller.configureDropdownActions()
    let row = ProfileDisplay(profile: AccountProfile(id: "invented", providerID: "claude", label: "Synthetic",
                                                     source: .claudeFile("/invented")), snapshot: nil,
                             health: .unauthenticated, message: "Reconnect account", fetchedAge: nil)
    controller.updateDropdown([row])
    controller.pressDropdownButton("Connect / Authorize Synthetic")
    controller.pressDropdownButton("Refresh")
    #expect(probe.connections == 1 && probe.refreshes == 1)
    controller.selectCount(5)
    #expect(probe.connections == 1 && probe.refreshes == 1)
    let accounts = controller.settingsMenu().item(at: 2)!
    #expect(NSApp.sendAction(accounts.action!, to: accounts.target, from: accounts))
    #expect(probe.accounts == 1)
}

@MainActor @Test func indicatorPreferencesUseIsolatedIntegerStore() {
    let suite = "limitaur-synthetic-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DefaultsIndicatorStore(defaults)
    #expect(store.loadCount() == 3)
    for invalid in [0, 9, -1, true, "5", 2.5] as [Any] {
        defaults.set(invalid, forKey: "indicatorCount")
        #expect(store.loadCount() == 3)
    }
    store.saveCount(5)
    #expect(DefaultsIndicatorStore(defaults).loadCount() == 5)
    store.saveCount(100)
    #expect(store.loadCount() == 3)
}

private final class CountingFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    func read(path: String) throws -> Data {
        lock.lock(); reads += 1; lock.unlock()
        return Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return reads }
}
private struct EmptyKeychain: KeychainReading { func claudeCredential() -> KeychainResult { .denied } }
private actor CountingTransport: HTTPTransport {
    enum Mode { case healthy, throttled, pending }
    let mode: Mode
    private var calls = 0
    private var continuation: CheckedContinuation<HTTPResponse, Error>?
    init(_ mode: Mode) { self.mode = mode }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        calls += 1
        switch mode {
        case .healthy:
            return HTTPResponse(status: 200, headers: [:], body: Data(#"{"rate_limit":{"primary_window":{"used_percent":85}}}"#.utf8))
        case .throttled:
            return HTTPResponse(status: 429, headers: ["retry-after": "3600"], body: Data())
        case .pending:
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
    func count() -> Int { calls }
    func finish() {
        continuation?.resume(returning: HTTPResponse(status: 200, headers: [:],
                                                     body: Data(#"{"rate_limit":{"primary_window":{"used_percent":85}}}"#.utf8)))
        continuation = nil
    }
}

private final class PresentationClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall = Date(timeIntervalSince1970: 1_800_000_000)
    private var mono: TimeInterval = 100
    func wallNow() -> Date { lock.lock(); defer { lock.unlock() }; return wall }
    func monotonicNow() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return mono }
    func advance(_ seconds: TimeInterval) { lock.lock(); mono += seconds; lock.unlock() }
    func move(wall seconds: TimeInterval = 0, mono elapsed: TimeInterval = 0) {
        lock.lock(); wall.addTimeInterval(seconds); mono += elapsed; lock.unlock()
    }
}

@MainActor @Test func installedStatusDrawingRevalidatesWithoutExternalEvent() throws {
    _ = NSApplication.shared
    let clock = PresentationClock()
    let controller = AppController(presentationClock: clock, countStore: CountStoreProbe(3))
    controller.installStatusDrawing()
    let now = clock.wallNow()
    let snapshot = UsageSnapshot(providerID: "codex", accountID: "synthetic", accountLabel: "Synthetic",
                                 fetchedAt: now,
                                 metrics: [UsageMetric(id: "window", label: "Window", usedPercent: 80,
                                                       resetsAt: now.addingTimeInterval(5))],
                                 balances: [CreditBalance(label: "Credits", remaining: Decimal(4),
                                                          expiresAt: now.addingTimeInterval(5))],
                                 resetCredits: ResetCreditSummary(availableCount: 2, applicableCount: nil,
                                                                  details: [ResetCredit(id: "earned", label: "Earned",
                                                                                        expiresAt: now.addingTimeInterval(5))]))
    let row = ProfileDisplay(profile: AccountProfile(id: "synthetic", providerID: "codex", label: "Synthetic",
                                                     source: .codexFile("/invented")), snapshot: snapshot,
                             health: .healthy, message: nil, fetchedAge: 0,
                             freshnessDeadline: 190, snapshotGeneration: 1)
    let candidate = PresentationCandidate(metric: RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0]),
                                          freshnessDeadline: 190, snapshotGeneration: 1)
    controller.receiveDisplay(MonitorDisplay(profiles: [row], candidates: [candidate],
                                             revision: 999_999, nextDisplayDeadline: 105))
    #expect(controller.currentPresentation?.selected.count == 1)
    #expect(controller.currentPresentation?.profiles.first?.health == .healthy)
    func redraw() throws {
        let view = controller.statusDrawingView
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }
    clock.move(wall: 5, mono: 5)
    try redraw()
    #expect(controller.currentPresentation?.selected.isEmpty == true)
    #expect(controller.currentPresentation?.profiles.first?.health == .healthy)
    #expect(controller.currentPresentation?.profiles.first?.expirations.metrics.contains("window") == true)
    #expect(controller.currentPresentation?.profiles.first?.expirations.balances.contains(0) == true)
    #expect(controller.currentPresentation?.profiles.first?.expirations.credits.contains(0) == true)
    #expect(controller.statusTooltip == controller.currentPresentation?.accessibilitySummary)
    #expect(controller.statusAccessibilitySummary == controller.currentPresentation?.accessibilitySummary)
    clock.move(wall: -5)
    try redraw()
    #expect(controller.currentPresentation?.selected.isEmpty == true)
    #expect(controller.currentPresentation?.profiles.first?.expirations.credits.contains(0) == true)
    clock.move(mono: 85)
    try redraw()
    #expect(controller.currentPresentation?.selected.isEmpty == true)
    #expect(controller.currentPresentation?.profiles.first?.health == .stale)
    #expect(controller.currentPresentation?.providerWarning == true)
    #expect(controller.statusTooltip == controller.currentPresentation?.accessibilitySummary)
    #expect(controller.statusAccessibilitySummary == controller.currentPresentation?.accessibilitySummary)
}

@MainActor @Test func delayedDisplayCannotRestoreOldRevisionOrExpiredBars() async {
    _ = NSApplication.shared
    let clock = PresentationClock()
    let controller = AppController(presentationClock: clock, countStore: CountStoreProbe(3))
    let now = clock.wallNow()
    let current = UsageSnapshot(providerID: "codex", accountID: "selected", accountLabel: "Synthetic",
                                fetchedAt: now, metrics: [UsageMetric(id: "current", label: "Current", usedPercent: 70)])
    let older = UsageSnapshot(providerID: "codex", accountID: "selected", accountLabel: "Synthetic",
                              fetchedAt: now, metrics: [UsageMetric(id: "old", label: "Old", usedPercent: 99)])
    let profile = AccountProfile(id: "synthetic", providerID: "codex", label: "Synthetic", source: .codexFile("/invented"))
    func display(_ snapshot: UsageSnapshot, generation: Int, revision: UInt64) -> MonitorDisplay {
        let row = ProfileDisplay(profile: profile, snapshot: snapshot, health: .healthy, message: nil,
                                 fetchedAge: 0, freshnessDeadline: 190, snapshotGeneration: generation)
        let candidate = PresentationCandidate(metric: RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0]),
                                              freshnessDeadline: 190, snapshotGeneration: generation)
        return MonitorDisplay(profiles: [row], candidates: [candidate], revision: revision, nextDisplayDeadline: 190)
    }
    controller.receiveDisplay(display(current, generation: 2, revision: 1_000))
    controller.receiveDisplay(display(older, generation: 1, revision: 999))
    #expect(controller.currentPresentation?.selected.first?.metric.id == "current")
    clock.advance(90)
    controller.selectCount(5)
    #expect(controller.currentPresentation?.selected.isEmpty == true)
    #expect(controller.currentPresentation?.profiles.first?.health == .stale)
    #expect(controller.currentPresentation?.providerWarning == true)
    #expect(controller.currentPresentation?.accessibilitySummary.components(separatedBy: "unavailable slot").count == 6)
    for _ in 0..<20 { await Task.yield() }
    #expect(controller.currentPresentation?.selected.isEmpty == true)
}

@MainActor @Test func productionCountActionDoesNotReadCredentialsOrFetch() async {
    _ = NSApplication.shared
    for mode in [CountingTransport.Mode.healthy, .throttled, .pending] {
        let files = CountingFiles(), transport = CountingTransport(mode), clock = PresentationClock()
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: EmptyKeychain()),
                              transport: transport)
        await monitor.setProfiles([AccountProfile(id: "synthetic", providerID: "codex", label: "Synthetic",
                                                  source: .codexFile("/invented"))])
        var started = false
        for _ in 0..<1000 {
            if await transport.count() == 1 { started = true; break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(started)
        if mode != .pending { #expect(await monitor.settle()) }
        clock.advance(31) // Healthy mode is now eligible for another HTTP request.
        let beforeState = await monitor.presentationActionState(for: "synthetic")
        let beforeDisplay = await monitor.display()
        #expect(beforeState != nil)
        #expect(beforeState?.hasInFlightRequest == (mode == .pending))
        #expect(beforeState?.hasCachedSnapshot == (mode == .healthy))
        #expect(beforeState?.authPaused == false)
        if mode == .healthy { #expect(beforeState?.throttleUntil == 0) }
        if mode == .throttled { #expect((beforeState?.throttleUntil ?? 0) > clock.monotonicNow()) }
        let probe = ActionProbe(), store = CountStoreProbe(3)
        let controller = AppController(monitor: monitor, presentationClock: clock,
                                       countStore: store, actionRouter: probe.router(demo: false))
        controller.receiveDisplay(beforeDisplay)
        let five = controller.settingsMenu().item(at: 0)!.submenu!.item(at: 4)!
        #expect(NSApp.sendAction(five.action!, to: five.target, from: five))
        controller.selectCount(8)
        controller.selectCount(1)
        for _ in 0..<100 { await Task.yield() }
        let afterState = await monitor.presentationActionState(for: "synthetic")
        let afterDisplay = await monitor.display()
        #expect(beforeState == afterState)
        #expect(beforeDisplay.profiles.first?.snapshot == afterDisplay.profiles.first?.snapshot)
        #expect(beforeDisplay.profiles.first?.health == afterDisplay.profiles.first?.health)
        #expect(controller.presentedCount == 1)
        #expect(store.writes == [5, 8, 1])
        #expect(probe.refreshes == 0 && probe.connections == 0 && probe.accounts == 0)
        #expect(files.count() == 1)
        #expect(await transport.count() == 1)
        if mode == .pending { await transport.finish() }
        #expect(await monitor.settle())
        await monitor.stop()
    }
}

private final class NudgeOrderProbe: SessionNudging, @unchecked Sendable {
    let log = Mutex<[String]>([])
    func nudge() async -> NudgeOutcome { .ran(exitCode: 0) }
    func waitForCompletion(upTo: TimeInterval) { log.withLock { $0.append("wait \(Int(upTo))") } }
}

@MainActor @Test func nudgeSettingPersistenceAndQuitOrder() async throws {
    _ = NSApplication.shared
    let suite = "limitaur-synthetic-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let clock = PresentationClock(), probe = NudgeOrderProbe()
    defaults.set(try JSONEncoder().encode(["claude-default": Date.distantFuture]), forKey: "nudge.lastAttempts")
    let monitor = Monitor(clock: clock, reactiveRecheck: true, nudger: probe)
    let controller = AppController(monitor: monitor, presentationClock: clock, countStore: CountStoreProbe(3), defaults: defaults, nudger: probe)
    var toggles: [Bool] = []
    controller.nudgeToggled = { toggles.append($0) }
    var item = controller.settingsMenu().item(at: 4)!
    #expect(item.title == "Run claude when the Claude session has expired" && item.state == .on && item.isEnabled)   // r15: an absent key means on
    #expect(NSApp.sendAction(item.action!, to: item.target, from: item))
    #expect(toggles == [false] && defaults.object(forKey: "claudeNudgeEnabled") as? Bool == false)
    item = controller.settingsMenu().item(at: 4)!
    #expect(item.state == .off)
    #expect(NSApp.sendAction(item.action!, to: item.target, from: item))
    #expect(toggles == [false, true] && defaults.bool(forKey: "claudeNudgeEnabled"))
    await controller.restoreNudge()   // a stored future attempt is clamped to the clock's now
    #expect(await monitor.display().nudgeAttempts == ["claude-default": clock.wallNow()])
    let before = defaults.data(forKey: "nudge.lastAttempts")   // only the monitor's attemptStore writes this key
    let stamp = clock.wallNow().addingTimeInterval(-60)
    controller.receiveDisplay(MonitorDisplay(profiles: [], candidates: [], revision: 5, nextDisplayDeadline: nil, nudgeAttempts: ["claude-default": stamp]))
    #expect(defaults.data(forKey: "nudge.lastAttempts") == before)
    var order: [String] = []
    controller.terminateProcesses = { order = probe.log.withLock { $0 } + ["terminate"] }
    controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    #expect(order == ["wait 5", "terminate"])
    let demo = AppController(demo: true, countStore: CountStoreProbe(3), defaults: defaults, nudger: probe)
    #expect(demo.settingsMenu().item(at: 4)?.isEnabled == false)
    demo.terminateProcesses = {}
    demo.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    #expect(probe.log.withLock { $0 } == ["wait 5"])
    await monitor.stop()
}

@MainActor @Test func displaysNeverWriteAttemptsAndDemoToggleIsInert() async throws {
    _ = NSApplication.shared
    let suite = "limitaur-synthetic-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let clock = PresentationClock(), stamp = clock.wallNow().addingTimeInterval(-60)
    let stored = try JSONEncoder().encode(["claude-default": stamp])
    defaults.set(stored, forKey: "nudge.lastAttempts")
    let monitor = Monitor(clock: clock, reactiveRecheck: true)
    let controller = AppController(monitor: monitor, presentationClock: clock, countStore: CountStoreProbe(3), defaults: defaults, nudger: nil)
    controller.receiveDisplay(MonitorDisplay(profiles: [], candidates: [], revision: 1, nextDisplayDeadline: nil))   // a display delivered before the restore
    #expect(defaults.data(forKey: "nudge.lastAttempts") == stored)
    await controller.restoreNudge()
    controller.receiveDisplay(MonitorDisplay(profiles: [], candidates: [], revision: 2, nextDisplayDeadline: nil, nudgeAttempts: ["claude-default": stamp.addingTimeInterval(30)]))
    controller.receiveDisplay(MonitorDisplay(profiles: [], candidates: [], revision: 3, nextDisplayDeadline: nil))   // a stale, empty display after it
    #expect(defaults.data(forKey: "nudge.lastAttempts") == stored)   // a display, early, late or stale, never writes
    await monitor.stop()

    let demo = AppController(demo: true, countStore: CountStoreProbe(3), defaults: defaults, nudger: nil)
    var toggles: [Bool] = []
    demo.nudgeToggled = { toggles.append($0) }
    let menu = demo.settingsMenu()
    menu.update()   // automatic enabling must not re-enable the item
    let item = menu.item(at: 4)!
    #expect(!menu.autoenablesItems && !item.isEnabled)
    #expect(NSApp.sendAction(item.action!, to: item.target, from: item))
    #expect(toggles.isEmpty && defaults.object(forKey: "claudeNudgeEnabled") == nil && item.state == .on)
}

private final class CountingNudger: SessionNudging, @unchecked Sendable {
    let calls = Mutex(0)
    func nudge() async -> NudgeOutcome { calls.withLock { $0 += 1 }; return .ran(exitCode: 0) }
    func waitForCompletion(upTo: TimeInterval) {}
}

/// r15: with no stored key the item is checked and `setNudgeEnabled(true)` is called; a stored false unchecks it and calls false.
/// The call is observed through an expired re-check, which runs the nudger only when the monitor was told true.
@MainActor @Test(arguments: [nil, false, true] as [Bool?])
func nudgeDefaultsToOnAndAStoredValueWins(_ stored: Bool?) async throws {
    _ = NSApplication.shared
    let suite = "limitaur-synthetic-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    if let stored { defaults.set(stored, forKey: "claudeNudgeEnabled") }
    let expected = stored ?? true
    let clock = PresentationClock()
    let nudger = CountingNudger()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: CountingFiles(), keychain: UnexpiredKeychain(expiry: clock.wallNow().addingTimeInterval(-10))),
                          transport: CountingTransport(.healthy), reactiveRecheck: true, nudger: nudger)
    let controller = AppController(monitor: monitor, presentationClock: clock, countStore: CountStoreProbe(3), defaults: defaults, nudger: nil)
    #expect(controller.settingsMenu().item(at: 4)?.state == (expected ? .on : .off))
    await controller.restoreNudge()
    await monitor.setProfiles([AccountProfile(id: "a", providerID: "claude", label: "Synthetic", source: .claudeDefaultDiscovery)])
    #expect(await monitor.settle())
    clock.move(wall: 301, mono: 301)
    await monitor.refresh(driver: .cycle)
    #expect(await monitor.settle())
    for _ in 0..<(expected ? 500 : 40) where nudger.calls.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(nudger.calls.withLock { $0 } == (expected ? 1 : 0))
    await monitor.stop()
}

private struct UnexpiredKeychain: KeychainReading {
    let expiry: Date
    func claudeCredential() -> KeychainResult {
        .found(try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": "synthetic-token-1", "expiresAt": Int64(expiry.timeIntervalSince1970 * 1000)]]))
    }
}

/// The wiring: the app's `attemptWriter` is the monitor's `attemptStore`, so a launch bind of an unexpired token writes nothing
/// when no attempt exists and replaces a restored attempt with the cleared map when one does.
@MainActor @Test func unexpiredLaunchBindClearsStoredAttemptsThroughTheAppWiring() async throws {
    _ = NSApplication.shared
    for restored in [false, true] {
        let suite = "limitaur-synthetic-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = PresentationClock()
        if restored { defaults.set(try JSONEncoder().encode(["claude:default": clock.wallNow().addingTimeInterval(-60)]), forKey: "nudge.lastAttempts") }
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: CountingFiles(), keychain: UnexpiredKeychain(expiry: clock.wallNow().addingTimeInterval(400))),
                              transport: CountingTransport(.healthy), reactiveRecheck: true, nudger: NudgeOrderProbe(),
                              attemptStore: AppController.attemptWriter(defaults))
        let controller = AppController(monitor: monitor, presentationClock: clock, countStore: CountStoreProbe(3), defaults: defaults, nudger: nil)
        await controller.restoreNudge()
        await monitor.setProfiles([AccountProfile(id: "a", providerID: "claude", label: "Synthetic", source: .claudeDefaultDiscovery)])
        #expect(await monitor.settle())
        let stored = defaults.data(forKey: "nudge.lastAttempts")
        if restored { #expect(try JSONDecoder().decode([String: Date].self, from: stored!).isEmpty) } else { #expect(stored == nil) }
        await monitor.stop()
    }
}
