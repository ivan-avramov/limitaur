import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Criterion C7 (controller persistence and wiring, I8). The controller gets an injected UserDefaults suite for the two new
// keys (`claudeSpendResetDay`, `sharedBudget`), as it does for the nudge setting; `profiles` stays in UserDefaults.standard
// and is restored after each test that seeds it.

private let sbuWall = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
private func sbuUTC(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day))!
}
private final class SBUClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock(); private var wall: Date, mono: TimeInterval = 100
    init(wall: Date = sbuWall) { self.wall = wall }
    func wallNow() -> Date { lock.withLock { wall } }
    func monotonicNow() -> TimeInterval { lock.withLock { mono } }
    func move(mono elapsed: TimeInterval) { lock.withLock { mono += elapsed } }
}
private struct SBUNoFiles: CredentialFileReading {
    func read(path: String) throws -> Data { throw CredentialFailure.missing }
}
private struct SBUKeychain: KeychainReading {
    let result: KeychainResult
    func claudeCredential() -> KeychainResult { result }
}
private struct SBUTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = #"{"limits":[{"kind":"session","percent":25}],"spend":{"enabled":true,"percent":15,"used":{"amount_minor":41000,"currency":"USD","exponent":2},"limit":{"amount_minor":500000,"currency":"USD","exponent":2}},"extra_usage":{"is_enabled":true,"monthly_limit":500000,"used_credits":41000.0,"utilization":8.2,"currency":"USD","decimal_places":2}}"#
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
    }
}
private struct SBUOfflineTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw TransportFailure.network }
}
private func sbuMonitor(_ clock: SBUClock) -> Monitor {
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented-claude-token"}}"#.utf8)
    return Monitor(clock: clock, credentials: CredentialStore(files: SBUNoFiles(), keychain: SBUKeychain(result: .found(claude)),
                                                              cursorKeychain: SBUKeychain(result: .notFound)),
                   transport: SBUTransport())
}
private func sbuSuite() -> (UserDefaults, () -> Void) {
    let name = "limitaur-synthetic-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}
private let sbuProfiles = [rdClaudeDefault, rdProfile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)]
private let sbuStoredBudget = SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["claude", "cursor"], resetDay: .day(1))

/// Seeds `profiles`, launches the controller and returns a teardown that restores `profiles`.
@MainActor private func sbuLaunch(defaults: UserDefaults, monitor: Monitor, clock: SBUClock) throws -> (AppController, () async -> Void) {
    _ = NSApplication.shared
    let previous = UserDefaults.standard.data(forKey: "profiles")
    UserDefaults.standard.set(try JSONEncoder().encode(sbuProfiles), forKey: "profiles")
    let controller = AppController(monitor: monitor, presentationClock: clock, countStore: RDCountStore(), defaults: defaults, nudger: nil)
    controller.settingsPresenter = { _ in }
    controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    return (controller, {
        controller.terminateProcesses = {}
        controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        await monitor.stop()
        if let previous { UserDefaults.standard.set(previous, forKey: "profiles") } else { UserDefaults.standard.removeObject(forKey: "profiles") }
    })
}
private func sbuPeriodEnd(_ monitor: Monitor) async -> Date? {
    await monitor.display().profiles.first { $0.profile.id == "claude-default" }?.snapshot?.spend?.periodEnd
}

// Serialized: launching seeds and restores the profile list in UserDefaults.standard.
@Suite(.serialized) @MainActor struct SBControllerTests {
    // N, I8: each change is stored under its key in the specified form: the day as storage text, the budget as JSON.
    @Test func changesArePersisted() throws {
        _ = NSApplication.shared
        let (defaults, cleanup) = sbuSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(defaults.object(forKey: "claudeSpendResetDay") == nil && defaults.object(forKey: "sharedBudget") == nil)
        controller.settings.setClaudeResetDay(.day(15))
        #expect(defaults.string(forKey: "claudeSpendResetDay") == "15")
        controller.settings.setClaudeResetDay(.lastDay)
        #expect(defaults.string(forKey: "claudeSpendResetDay") == "last")
        controller.settings.setBudgetEnabled(true)
        #expect(controller.settings.setBudgetAmount("5000"))
        controller.settings.setBudgetMember("cursor", false)
        controller.settings.setBudgetResetDay(.day(20))
        let stored = try JSONDecoder().decode(SharedBudgetConfig.self, from: try #require(defaults.data(forKey: "sharedBudget")))
        #expect(stored == SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["claude"], resetDay: .day(20)))
        #expect(stored == controller.settings.budget)
    }
    // N, I8: stored values are in force after launch; absent or invalid values mean the defaults.
    @Test func storedValuesLoadAndInvalidOnesDefault() async throws {
        let (defaults, cleanup) = sbuSuite(); defer { cleanup() }
        let clock = SBUClock(), monitor = sbuMonitor(clock)
        defaults.set("20", forKey: "claudeSpendResetDay")
        defaults.set(try JSONEncoder().encode(sbuStoredBudget), forKey: "sharedBudget")
        let (controller, teardown) = try sbuLaunch(defaults: defaults, monitor: monitor, clock: clock)
        #expect(controller.settings.claudeResetDay == .day(20) && controller.settings.budget == sbuStoredBudget)
        await teardown()
        for (day, budget) in [("0", Data("{}".utf8)), ("32", Data("not json".utf8)), ("", Data())] as [(String, Data)] {
            let (bad, badCleanup) = sbuSuite(); defer { badCleanup() }
            bad.set(day, forKey: "claudeSpendResetDay"); bad.set(budget, forKey: "sharedBudget")
            let (second, secondTeardown) = try sbuLaunch(defaults: bad, monitor: sbuMonitor(clock), clock: clock)
            #expect(second.settings.claudeResetDay == .default && second.settings.budget == SBSettingsProbe().model().budget, "\(day)")
            await secondTeardown()
        }
        let (empty, emptyCleanup) = sbuSuite(); defer { emptyCleanup() }
        let (third, thirdTeardown) = try sbuLaunch(defaults: empty, monitor: sbuMonitor(clock), clock: clock)
        #expect(third.settings.claudeResetDay == .default && !third.settings.budget.enabled && third.settings.budget.amount == nil)
        await thirdTeardown()
    }
    // I, I8: the demo controller applies the change to its model but stores neither key, in the injected suite or in standard.
    @Test func demoStoresNothing() {
        _ = NSApplication.shared
        let (defaults, cleanup) = sbuSuite(); defer { cleanup() }
        let keys = ["claudeSpendResetDay", "sharedBudget"]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
        defer { for (key, value) in zip(keys, before) { if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } } }
        let demo = AppController(demo: true, countStore: RDCountStore(), defaults: defaults)
        demo.settings.setClaudeResetDay(.day(9)); demo.settings.setBudgetEnabled(true)
        _ = demo.settings.setBudgetAmount("100"); demo.settings.setBudgetMember("claude", false); demo.settings.setBudgetResetDay(.lastDay)
        #expect(demo.settings.claudeResetDay == .day(9) && demo.settings.budget.amount == 100 && !demo.settings.editable)
        #expect(keys.allSatisfy { defaults.object(forKey: $0) == nil })
        #expect(zip(keys, before).allSatisfy { UserDefaults.standard.object(forKey: $0) as? NSObject == $1 })
    }
    // N, I4/I8: the stored day reaches the monitor at launch and a change reaches it for the next fetch.
    @Test func resetDayReachesTheMonitor() async throws {
        let (defaults, cleanup) = sbuSuite(); defer { cleanup() }
        defaults.set("20", forKey: "claudeSpendResetDay")
        let clock = SBUClock(), monitor = sbuMonitor(clock)
        let (controller, teardown) = try sbuLaunch(defaults: defaults, monitor: monitor, clock: clock)
        #expect(await sbuWait { await sbuPeriodEnd(monitor) == sbuUTC(2027, 1, 20) })
        controller.settings.setClaudeResetDay(.lastDay)
        var reached = false
        for _ in 0..<400 where !reached {
            clock.move(mono: 60); await monitor.refresh()
            reached = await sbuPeriodEnd(monitor) == sbuUTC(2027, 1, 31)
            if !reached { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(reached)
        await teardown()
    }
    // N, I8: refreshProjection computes the budget from the projected rows and the Settings main accounts, ranks it, shows it
    // in the dropdown model, and feeds the reported limits back to Settings (pre-fill).
    @Test func projectionWiresTheBudget() async throws {
        let (defaults, cleanup) = sbuSuite(); defer { cleanup() }
        let clock = SBUClock(wall: sbuUTC(2027, 1, 15))
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: SBUNoFiles(), keychain: SBUKeychain(result: .notFound),
                                                                         cursorKeychain: SBUKeychain(result: .notFound)),
                              transport: SBUOfflineTransport())
        let (controller, teardown) = try sbuLaunch(defaults: defaults, monitor: monitor, clock: clock)
        let end = sbuUTC(2027, 2, 1)
        func row(_ provider: ProviderID, _ spent: Decimal, percent: Double) -> (ProfileDisplay, PresentationCandidate) {
            var source = sbuRow(provider, limit: 5000)
            let metric = UsageMetric(id: "spend", label: "Monthly spend", usedPercent: percent, resetsAt: end)
            let snapshot = UsageSnapshot(providerID: provider, accountID: AccountID(source.profile.id), accountLabel: "Default",
                                         fetchedAt: clock.wallNow(), metrics: [metric],
                                         spend: SpendSummary(spent: spent, limit: 5000, currency: "USD", periodEnd: end))
            source = ProfileDisplay(profile: source.profile, snapshot: snapshot, health: .healthy, message: nil, fetchedAge: 0,
                                    freshnessDeadline: 190, snapshotGeneration: provider == "claude" ? 1 : 2)
            return (source, PresentationCandidate(metric: RankedMetric(snapshot: snapshot, metric: metric), freshnessDeadline: 190,
                                                  snapshotGeneration: source.snapshotGeneration))
        }
        let claude = row("claude", 410, percent: 15), cursor = row("cursor", 41, percent: 0.82)
        func display(_ revision: UInt64) -> MonitorDisplay {
            MonitorDisplay(profiles: [claude.0, cursor.0], candidates: [claude.1, cursor.1], revision: revision, nextDisplayDeadline: nil)
        }
        controller.receiveDisplay(display(1001))   // revisions above anything the offline monitor publishes
        #expect(controller.dropdownModel.budget == nil && controller.currentPresentation?.selected.map(\.providerID.rawValue) == ["claude", "cursor"])
        controller.settings.setBudgetEnabled(true)   // pre-filled from the limits the projection reported to Settings
        #expect(controller.settings.budget.amount == 5000)
        controller.receiveDisplay(display(1002))
        let budget = try #require(controller.dropdownModel.budget)
        #expect(budget.total == 451 && budget.resetsAt == end && budget.warning == nil)
        #expect(abs(try #require(budget.usedPercent) - 9.02) < 1e-9)
        #expect(controller.currentPresentation?.selected.map(\.providerID.rawValue) == ["claude", "budget", "cursor"])
        #expect(controller.currentPresentation?.accessibilitySummary.contains("Shared budget") == true)
        controller.updateDropdown([claude.0, cursor.0])
        #expect(controller.dropdownModel.actionTitles() == ["Refresh", "Settings", "Quit"], "the action titles are unchanged")
        controller.settings.setBudgetEnabled(false)
        controller.receiveDisplay(display(1003))
        #expect(controller.dropdownModel.budget == nil && controller.currentPresentation?.selected.map(\.providerID.rawValue) == ["claude", "cursor"])
        await teardown()
    }
}

/// A clock that advances with real time from a chosen wall instant.
private final class SBUTickClock: MonitorClock, @unchecked Sendable {
    private let base: Date, start = ContinuousClock.now
    init(base: Date) { self.base = base }
    private var elapsed: TimeInterval {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
    func wallNow() -> Date { base.addingTimeInterval(elapsed) }
    func monotonicNow() -> TimeInterval { 100 + elapsed }
}

// Revision 2 (H3, H4). Classes: R = reproduces a failure the revision fixes, I = invariant.
extension SBControllerTests {
    // R, H3: a persisted budget loads validated: known members once each in first-seen order, a positive amount or nil; a
    // non-USD currency makes the whole configuration default. A valid configuration loads unchanged.
    @Test func persistedBudgetLoadsValidated() async throws {
        let defaultBudget = SBSettingsProbe().model().budget
        let cases: [(SharedBudgetConfig, SharedBudgetConfig)] = [
            (SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["claude", "claude", "cursor", "claude"], resetDay: .day(15)),
             SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["claude", "cursor"], resetDay: .day(15))),
            (SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["cursor", "codex", "budget", "claude"], resetDay: .lastDay),
             SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["cursor", "claude"], resetDay: .lastDay)),
            (SharedBudgetConfig(enabled: true, amount: -5, currency: "USD", members: ["claude", "cursor"], resetDay: .default),
             SharedBudgetConfig(enabled: true, amount: nil, currency: "USD", members: ["claude", "cursor"], resetDay: .default)),
            (SharedBudgetConfig(enabled: true, amount: 0, currency: "USD", members: ["claude"], resetDay: .default),
             SharedBudgetConfig(enabled: true, amount: nil, currency: "USD", members: ["claude"], resetDay: .default)),
            (SharedBudgetConfig(enabled: true, amount: 5000, currency: "EUR", members: ["claude", "cursor"], resetDay: .day(9)), defaultBudget),
            (sbuStoredBudget, sbuStoredBudget)]
        for (stored, expected) in cases {
            let (defaults, cleanup) = sbuSuite(); defer { cleanup() }
            defaults.set(try JSONEncoder().encode(stored), forKey: "sharedBudget")
            let clock = SBUClock(), monitor = sbuMonitor(clock)
            let (controller, teardown) = try sbuLaunch(defaults: defaults, monitor: monitor, clock: clock)
            #expect(controller.settings.budget == expected, "\(stored)")
            await teardown()
        }
    }

    // R, H4: with no further display event, the budget is recomputed at its reset: after `resetsAt` the old period no longer
    // matches, so the stale total is not shown as current. Unlaunched controller, so only the armed one-shot can refresh.
    @Test func budgetRefreshesAtItsReset() async throws {
        _ = NSApplication.shared
        let previous = UserDefaults.standard.data(forKey: "profiles")
        defer { if let previous { UserDefaults.standard.set(previous, forKey: "profiles") } else { UserDefaults.standard.removeObject(forKey: "profiles") } }
        let (defaults, cleanup) = sbuSuite(); defer { cleanup() }
        defaults.set(try JSONEncoder().encode(sbuStoredBudget), forKey: "sharedBudget")
        let end = sbuUTC(2027, 2, 1)
        let clock = SBUTickClock(base: end.addingTimeInterval(-1.5))
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: SBUNoFiles(), keychain: SBUKeychain(result: .notFound),
                                                                         cursorKeychain: SBUKeychain(result: .notFound)),
                              transport: SBUOfflineTransport())
        let controller = AppController(monitor: monitor, presentationClock: clock, countStore: RDCountStore(), defaults: defaults, nudger: nil)
        controller.settings.setProviderEnabled("claude", true); controller.settings.setProviderEnabled("cursor", true)
        func row(_ provider: ProviderID, _ spent: Decimal, generation: Int) -> ProfileDisplay {
            let base = sbuRow(provider, limit: 5000)
            let snapshot = UsageSnapshot(providerID: provider, accountID: AccountID(base.profile.id), accountLabel: "Default",
                                         fetchedAt: clock.wallNow(), metrics: [],
                                         spend: SpendSummary(spent: spent, limit: 5000, currency: "USD", periodEnd: end))
            return ProfileDisplay(profile: base.profile, snapshot: snapshot, health: .healthy, message: nil, fetchedAge: 0,
                                  freshnessDeadline: clock.monotonicNow() + 1000, snapshotGeneration: generation)
        }
        controller.receiveDisplay(MonitorDisplay(profiles: [row("claude", 410, generation: 1), row("cursor", 41, generation: 2)],
                                                 candidates: [], revision: 1001, nextDisplayDeadline: nil))
        #expect(controller.dropdownModel.budget?.total == 451 && controller.dropdownModel.budget?.resetsAt == end)
        var refreshed = false
        for _ in 0..<400 where !refreshed {
            try await Task.sleep(for: .milliseconds(10))
            refreshed = controller.dropdownModel.budget?.total == nil
        }
        #expect(refreshed, "no refresh happened at the reset")
        #expect(controller.dropdownModel.budget?.resetsAt == sbuUTC(2027, 3, 1))
        controller.terminateProcesses = {}
        controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        await monitor.stop()
    }
}

/// Polls until `predicate` holds, for at most three seconds.
private func sbuWait(_ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    let end = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < end { if await predicate() { return true }; try? await Task.sleep(for: .milliseconds(5)) }
    return await predicate()
}
