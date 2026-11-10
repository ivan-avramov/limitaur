import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: N = exercises new behaviour, I = preserves an invariant. Criteria C2 (wiring of I2 callbacks) and C3 (router seams).

private struct RDNoFiles: CredentialFileReading {
    func read(path: String) throws -> Data { throw CredentialFailure.missing }
}
private struct RDNoKeychain: KeychainReading {
    func claudeCredential() -> KeychainResult { .notFound }
}
private struct RDOfflineTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw TransportFailure.network }
}
private func rdOfflineMonitor() -> Monitor {
    Monitor(credentials: CredentialStore(files: RDNoFiles(), keychain: RDNoKeychain(), cursorKeychain: RDNoKeychain()),
            transport: RDOfflineTransport())
}
@MainActor private func rdIsolatedDefaults() -> (UserDefaults, String) {
    let suite = "limitaur-synthetic-" + UUID().uuidString
    return (UserDefaults(suiteName: suite)!, suite)
}

// Serialized: the profile list is persisted in UserDefaults.standard, as `saveProfiles()` does today.
@Suite(.serialized) @MainActor struct RDControllerTests {
    // N, I1: the model starts from the persisted indicator count and the nudge default (absent key means on).
    @Test func settingsStartFromStoredPreferences() {
        _ = NSApplication.shared
        let (defaults, suite) = rdIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = AppController(countStore: RDCountStore(6), defaults: defaults, nudger: nil)
        #expect(controller.settings.indicatorCount == 6 && controller.presentedCount == 6)
        #expect(controller.settings.nudgeEnabled && controller.settings.editable)
        defaults.set(false, forKey: "claudeNudgeEnabled")
        #expect(AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil).settings.nudgeEnabled == false)
    }
    // N: the demo controller's model is read-only.
    @Test func demoSettingsAreNotEditable() {
        _ = NSApplication.shared
        let demo = AppController(demo: true, countStore: RDCountStore())
        #expect(!demo.settings.editable)
        #expect(AppController(countStore: RDCountStore()).settings.editable)
    }
    // N, I3: the Settings action and "Open Settings" hand the controller's model to settingsPresenter, once each.
    @Test func settingsActionPresentsTheModel() {
        _ = NSApplication.shared
        let controller = AppController(countStore: RDCountStore())
        controller.configureDropdownActions()
        var presented: [SettingsModel] = []
        controller.settingsPresenter = { presented.append($0) }
        controller.pressDropdownButton("Settings")
        #expect(presented.count == 1 && presented.first === controller.settings)
        controller.updateDropdown([])
        controller.pressDropdownButton("Open Settings")
        #expect(presented.count == 2 && presented.last === controller.settings)
    }
    // N, F5 (Revision 2; replaces demoSettingsActionDoesNotPresent): demo "Settings" and "Open Settings" present the
    // read-only model through settingsPresenter and never reach the router, whose demo guard is unchanged.
    @Test func demoSettingsActionPresentsWithoutTheRouter() {
        _ = NSApplication.shared
        let probe = RDRouterProbe()
        let controller = AppController(demo: true, countStore: RDCountStore(), actionRouter: probe.router(demo: true))
        controller.configureDropdownActions()
        var presented: [SettingsModel] = []
        controller.settingsPresenter = { presented.append($0) }
        controller.pressDropdownButton("Settings")
        #expect(presented.count == 1 && presented.first === controller.settings && !controller.settings.editable)
        controller.routeConnect("x"); controller.pressDropdownButton("Refresh")
        #expect(presented.count == 1 && probe.accounts == 0 && probe.refreshes == 0 && probe.connected.isEmpty)
    }
    // N, I2: onAbout calls aboutPresenter with the About options; nothing else is touched.
    @Test func aboutReachesThePresenterWithOptions() {
        _ = NSApplication.shared
        let probe = RDRouterProbe(), store = RDCountStore()
        let controller = AppController(countStore: store, actionRouter: probe.router(demo: false))
        var presented: [[NSApplication.AboutPanelOptionKey: Any]] = []
        controller.aboutPresenter = { presented.append($0) }
        controller.settings.showAbout()
        #expect(presented.count == 1 && presented.first?[.applicationVersion] as? String == AppVersion.string)
        #expect(probe.refreshes == 0 && probe.connected.isEmpty && probe.accounts == 0 && probe.quits == 0 && store.writes.isEmpty)
    }
    // N, I2: connect from the model goes through the router with the account id; in demo it never does.
    @Test func settingsConnectGoesThroughTheRouter() {
        _ = NSApplication.shared
        let probe = RDRouterProbe()
        let controller = AppController(countStore: RDCountStore(), actionRouter: probe.router(demo: false))
        controller.settings.connect("codex-default")
        #expect(probe.connected == ["codex-default"] && probe.refreshes == 0 && probe.accounts == 0)
        let demoProbe = RDRouterProbe()
        let demo = AppController(demo: true, countStore: RDCountStore(), actionRouter: demoProbe.router(demo: true))
        demo.settings.connect("codex-default")
        #expect(demoProbe.connected.isEmpty)
    }
    // N, I1: a profile change saves normalised profiles under the `profiles` key and reaches the monitor; a section turned off
    // keeps its profile. Demo never saves.
    @Test func profileChangesAreSavedAndReachTheMonitor() async throws {
        _ = NSApplication.shared
        let previous = UserDefaults.standard.data(forKey: "profiles")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "profiles") }
            else { UserDefaults.standard.removeObject(forKey: "profiles") }
        }
        UserDefaults.standard.removeObject(forKey: "profiles")
        let demo = AppController(demo: true, countStore: RDCountStore())
        demo.settings.setProviderEnabled("cursor", true)
        #expect(UserDefaults.standard.data(forKey: "profiles") == nil)

        let monitor = rdOfflineMonitor()
        let controller = AppController(monitor: monitor, countStore: RDCountStore(), nudger: nil)
        controller.settings.setProviderEnabled("cursor", true)
        func saved() throws -> [AccountProfile] {
            try JSONDecoder().decode([AccountProfile].self, from: try #require(UserDefaults.standard.data(forKey: "profiles")))
        }
        let created = try #require(try saved().first { $0.id == "cursor-default" })
        #expect(created == AccountProfile(id: "cursor-default", providerID: "cursor", label: "Default",
                                          source: .cursorDefaultDiscovery, enabled: true))
        #expect(try saved() == controller.settings.profiles)
        controller.settings.setProviderEnabled("cursor", false)
        #expect(try saved().first { $0.id == "cursor-default" }?.enabled == false)
        controller.settings.setProviderEnabled("cursor", true)   // the final state: enabled
        #expect(try saved().first { $0.id == "cursor-default" }?.enabled == true)
        #expect(try saved() == controller.settings.profiles)
        // The save path's Task reads the profile list when it runs, so earlier changes may be coalesced into the last one;
        // assert the final monitored state after at least one configuration change.
        var seen = false
        for _ in 0..<400 where !seen {
            let changes = (await monitor.statistics())["__eligibility"]?["configurationChanges"] ?? 0
            let monitored = (await monitor.display()).profiles.contains { $0.profile.id == "cursor-default" && $0.profile.enabled }
            seen = changes >= 1 && monitored
            if !seen { try await Task.sleep(for: .milliseconds(5)) }
        }
        #expect(seen)
        await monitor.stop()
    }

    // R, F5: in demo the indicator count changes through the model and reaches presentedCount; the injected store is untouched
    // because demo uses the in-memory store; provider data stays untouched.
    @Test func demoIndicatorCountChangesPresentedCount() {
        _ = NSApplication.shared
        let store = RDCountStore()
        let demo = AppController(demo: true, countStore: store)
        #expect(demo.presentedCount == 3)
        demo.settings.setIndicatorCount(6)
        #expect(demo.presentedCount == 6 && demo.settings.indicatorCount == 6 && !demo.settings.editable)
        demo.settings.setIndicatorCount(9)
        #expect(demo.presentedCount == 6)
        #expect(store.reads == 0 && store.writes.isEmpty)
        #expect(demo.statusWidth == RingView.statusWidth(for: 6))
    }

    // R, G3: through the controller, a "Connecting account" row reaches Settings as Connecting… without its message, and the
    // dropdown model's own rows keep the message and map to the same status.
    @Test func controllerConnectingRowAgreesAcrossDropdownAndSettings() async throws {
        let (controller, _, teardown) = try launched(seed: Self.seeded)
        let connecting = ProfileDisplay(profile: Self.seeded[1], snapshot: nil, health: .unavailable,
                                        message: "Connecting account", fetchedAge: nil)
        controller.updateDropdown([connecting])
        let main = controller.settings.sections.first { $0.provider == "claude" }?.main
        #expect(main?.status == .connecting && main?.message == nil)
        #expect(controller.dropdownModel.rows.first.map { AccountStatus(row: $0) } == .connecting)
        #expect(controller.dropdownModel.rows.first?.message == "Connecting account")
        #expect(controller.dropdownModel.actionTitles() == ["Refresh", "Settings", "Quit"])
        await teardown()
    }

    // MARK: demo content (G2)

    // R, G2: after prepareDemo the read-only Settings model is built from the demo's own profiles: it matches the demo rows'
    // accounts and providers, with statuses mapped, Claude and Codex on, Cursor off, and it is not editable.
    @Test func demoSettingsMatchTheDemoRows() throws {
        _ = NSApplication.shared
        let demo = AppController(demo: true, countStore: RDCountStore())
        demo.prepareDemo()
        let rows = try #require(demo.currentPresentation?.profiles)
        #expect(!rows.isEmpty && !demo.settings.editable)
        #expect(Set(demo.settings.profiles.map(\.id)) == Set(rows.map(\.profile.id)))
        let accounts = demo.settings.sections.flatMap { section in ([section.main].compactMap { $0 } + section.others).map { (section.provider, $0) } }
        #expect(Set(accounts.map(\.1.id)) == Set(rows.map(\.profile.id)))
        #expect(accounts.count == rows.count)
        for (provider, account) in accounts {
            let row = try #require(rows.first { $0.profile.id == account.id })
            #expect(row.profile.providerID == provider && account.label == row.profile.label)
            #expect(account.status == AccountStatus(row: row) && account.status == .healthy && account.enabled)
        }
        for provider in Set(rows.map(\.profile.providerID)) {
            #expect(demo.settings.sections.first { $0.provider == provider }?.main?.enabled == true)
        }
        let shown = Set(rows.map(\.profile.providerID.rawValue))
        for section in demo.settings.sections where !shown.contains(section.provider.rawValue) {
            #expect(section.main == nil && section.others.isEmpty)
        }
        #expect(demo.settings.sections.map(\.provider.rawValue) == ["claude", "codex", "cursor"])
    }
    // I, G2: the demo model stays read-only and never saves, whatever is changed.
    @Test func demoSettingsNeverSave() {
        _ = NSApplication.shared
        let previous = UserDefaults.standard.data(forKey: "profiles")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "profiles") }
            else { UserDefaults.standard.removeObject(forKey: "profiles") }
        }
        UserDefaults.standard.removeObject(forKey: "profiles")
        let demo = AppController(demo: true, countStore: RDCountStore())
        demo.prepareDemo()
        let before = demo.settings.profiles
        let first = before[0].id
        demo.settings.setProviderEnabled("claude", false); demo.settings.setProviderEnabled("cursor", true)
        demo.settings.setAccountEnabled(first, false); demo.settings.setLabel(first, "X")
        demo.settings.removeAccount(before.last!.id)
        _ = demo.settings.addAccount("codex")
        #expect(demo.settings.profiles == before && !demo.settings.editable)
        #expect(UserDefaults.standard.data(forKey: "profiles") == nil)
    }

    // MARK: launch path

    private static let seeded: [AccountProfile] = [
        AccountProfile(id: "codex-default", providerID: "codex", label: "Default", source: .codexFile("/rd/seed/codex.json"), enabled: false),
        AccountProfile(id: "claude-default", providerID: "claude", label: "Default", source: .claudeFile("/rd/seed/claude.json")),
        AccountProfile(id: "codex-work", providerID: "codex", label: "Work", source: .codexFile("/rd/seed/work.json")),
        AccountProfile(id: "claude-b", providerID: "claude", label: "Account 2", source: .claudeDefaultDiscovery, enabled: false),
        AccountProfile(id: "cursor-default", providerID: "cursor", label: "Default", source: .cursorDefaultDiscovery, enabled: false)
    ]

    /// Seeds the `profiles` key, launches the controller as production does (offline monitor) and returns a teardown.
    private func launched(seed: [AccountProfile]) throws -> (AppController, Monitor, () async -> Void) {
        _ = NSApplication.shared
        let previous = UserDefaults.standard.data(forKey: "profiles")
        UserDefaults.standard.set(try JSONEncoder().encode(seed), forKey: "profiles")
        let monitor = rdOfflineMonitor()
        let controller = AppController(monitor: monitor, countStore: RDCountStore(), nudger: nil)
        controller.settingsPresenter = { _ in }
        controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return (controller, monitor, {
            controller.terminateProcesses = {}
            controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            await monitor.stop()
            if let previous { UserDefaults.standard.set(previous, forKey: "profiles") }
            else { UserDefaults.standard.removeObject(forKey: "profiles") }
        })
    }

    // N, I1: after launch the Settings model holds the persisted profiles in saved order; one Settings change saves every seeded
    // profile, changing only that change, and nothing is lost to the model having been built before the profiles were loaded.
    @Test func launchLoadsPersistedProfilesAndASettingsChangeKeepsThemAll() async throws {
        let (controller, monitor, teardown) = try launched(seed: Self.seeded)
        let settings = controller.settings!
        #expect(settings.profiles == Self.seeded)
        controller.settings.setLabel("codex-work", "Laptop")
        let data = try #require(UserDefaults.standard.data(forKey: "profiles"))
        let saved = try JSONDecoder().decode([AccountProfile].self, from: data)
        var expected = Self.seeded
        expected[2].label = "Laptop"
        #expect(saved == expected)
        controller.settings.setProviderEnabled("cursor", true)
        let saved2 = try JSONDecoder().decode([AccountProfile].self, from: try #require(UserDefaults.standard.data(forKey: "profiles")))
        expected[4].enabled = true
        #expect(saved2 == expected && saved2.count == Self.seeded.count)
        await teardown()
        _ = monitor
    }

    // N, C2: statuses reach Settings while the popover is closed: after receiveDisplay with rows the sections show the mapped
    // statuses, disabled accounts show Off, and enabled accounts without a row show Connecting….
    @Test func statusesReachSettingsWithThePopoverClosed() async throws {
        let (controller, _, teardown) = try launched(seed: Self.seeded)
        func row(_ id: String, _ health: Health, _ message: String?) -> ProfileDisplay {
            ProfileDisplay(profile: Self.seeded.first { $0.id == id }!, snapshot: nil, health: health, message: message, fetchedAge: nil)
        }
        controller.receiveDisplay(MonitorDisplay(profiles: [row("claude-default", .throttled, "Slow down"),
                                                            row("codex-default", .unauthenticated, "Sign in")],
                                                 candidates: [], revision: 1, nextDisplayDeadline: nil))
        func account(_ provider: ProviderID, _ id: String) -> SettingsAccount? {
            controller.settings.sections.first { $0.provider == provider }.flatMap { section in
                ([section.main].compactMap { $0 } + section.others).first { $0.id == id }
            }
        }
        #expect(account("claude", "claude-default")?.status == .throttled && account("claude", "claude-default")?.message == "Slow down")
        #expect(account("codex", "codex-default")?.status == .off)   // disabled: Off wins over the row
        #expect(account("codex", "codex-work")?.status == .connecting)
        #expect(account("claude", "claude-b")?.status == .off)
        controller.receiveDisplay(MonitorDisplay(profiles: [row("claude-default", .healthy, nil), row("codex-work", .unauthenticated, nil)],
                                                 candidates: [], revision: 2, nextDisplayDeadline: nil))
        #expect(account("claude", "claude-default")?.status == .healthy && account("codex", "codex-work")?.status == .signIn)
        await teardown()
    }
}
