import AppKit
import Foundation
import Testing
@testable import LimitaurCore
@testable import Limitaur

// MARK: - Fixtures

@MainActor private final class SettingsProbe {
    var profiles: [[AccountProfile]] = []
    var counts: [Int] = []
    var nudges: [Bool] = []
    var connects: [String] = []
    var abouts = 0
    var callbacks: Int { profiles.count + counts.count + nudges.count + connects.count + abouts }
    func model(_ list: [AccountProfile], count: Int = 3, nudge: Bool = true, editable: Bool = true) -> SettingsModel {
        SettingsModel(profiles: list, indicatorCount: count, nudgeEnabled: nudge, editable: editable,
                      onProfiles: { self.profiles.append($0) }, onIndicatorCount: { self.counts.append($0) },
                      onNudge: { self.nudges.append($0) }, onConnect: { self.connects.append($0) },
                      onAbout: { self.abouts += 1 })
    }
}

private func profile(_ id: String, _ provider: ProviderID, _ label: String = "Default",
                     _ source: CredentialSource = .claudeDefaultDiscovery, enabled: Bool = true) -> AccountProfile {
    AccountProfile(id: id, providerID: provider, label: label, source: source, enabled: enabled)
}

private func row(_ id: String, _ provider: ProviderID, _ label: String, _ health: Health, message: String? = nil) -> ProfileDisplay {
    ProfileDisplay(profile: profile(id, provider, label, .claudeFile("/synthetic")), snapshot: nil,
                   health: health, message: message, fetchedAge: nil)
}

@MainActor private func section(_ model: SettingsModel, _ provider: ProviderID) -> SettingsSection {
    model.sections.first { $0.provider == provider }!
}

// MARK: - C4 formatting

@Test func percentTextRoundsToWholeNumbers() {
    #expect(percentText(nil) == "—")
    #expect(percentText(-1) == "—")
    #expect(percentText(.nan) == "—")
    #expect(percentText(0) == "0%")
    #expect(percentText(0.2) == "<1%")
    #expect(percentText(0.49) == "<1%")
    #expect(percentText(98.4) == "98%")
    #expect(percentText(99.5) == "99%")
    #expect(percentText(99.99) == "99%")
    #expect(percentText(100) == "100%")
    #expect(percentText(120) == "120%")
    #expect(percentText(1e30) == String(format: "%.0f%%", 1e30))       // F1: no Int conversion trap
    #expect(percentText(.greatestFiniteMagnitude).hasSuffix("%"))
}

@Test func exactPercentAndProviderNames() {
    #expect(exactPercentText(12.345) == "12.35%")
    #expect(exactPercentText(nil) == "unknown")
    #expect(providerName("claude") == "Claude")
    #expect(providerName("codex") == "Codex")
    #expect(providerName("cursor") == "Cursor")
    #expect(providerName("gemini") == "Gemini")
}

@Test func amountTextFormatsCurrencyCodes() {
    let us = Locale(identifier: "en_US")
    #expect(amountText(Decimal(string: "86.14")!, currency: "USD", locale: us) == "$86.14")
    #expect(amountText(Decimal(5000), currency: "USD", locale: us) == "$5,000.00")
    #expect(amountText(Decimal(4), currency: "credits", locale: us) == "4 credits")
    #expect(amountText(Decimal(4), currency: "usd", locale: us) == "4 usd")
    #expect(amountText(Decimal(4), currency: "US", locale: us) == "4 US")
}

@Test func resetLabelCases() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let known = UsageMetric(id: "a", label: "A", usedPercent: 1, resetsAt: now.addingTimeInterval(7200))
    #expect(resetLabel(known, expired: false, now: now) == "resets in 2h")
    #expect(resetLabel(known, expired: true, now: now) == "reset due")
    let past = UsageMetric(id: "a", label: "A", usedPercent: 1, resetsAt: now.addingTimeInterval(-5))
    #expect(resetLabel(past, expired: false, now: now) == "reset due")
    let absurd = UsageMetric(id: "a", label: "A", usedPercent: 1, resetsAt: Date(timeIntervalSince1970: 1e15))
    #expect(resetLabel(absurd, expired: false, now: now) == "reset time unavailable")
    let unknown = UsageMetric(id: "a", label: "A", usedPercent: 1)
    #expect(resetLabel(unknown, expired: false, now: now) == "reset unknown")
}

@Test func accountStatusMapsEveryHealth() {
    let expected: [(Health, AccountStatus, String)] = [
        (.healthy, .healthy, "Healthy"), (.partial, .partial, "Partial data"), (.throttled, .throttled, "Rate limited"),
        (.stale, .stale, "Stale"), (.unavailable, .unavailable, "Unavailable"), (.failed, .failed, "Connection failed"),
        (.unauthenticated, .signIn, "Needs sign-in")
    ]
    for (health, status, label) in expected {
        #expect(AccountStatus(health) == status)
        #expect(status.label == label)
    }
    #expect(AccountStatus.off.label == "Off")
    #expect(AccountStatus.connecting.label == "Connecting…")
}

// MARK: - C2 SettingsModel

@MainActor @Test func mainAccountPrefersDefaultIDThenSavedOrder() {
    let probe = SettingsProbe()
    let model = probe.model([
        profile("x1", "codex", "First", .codexFile("/a")),
        profile("codex-default", "codex", "Default", .codexFile("/b")),
        profile("c1", "claude", "Only", .claudeFile("/c"))
    ])
    #expect(model.sections.map(\.provider) == ["claude", "codex", "cursor"])
    #expect(section(model, "codex").main?.id == "codex-default")
    #expect(section(model, "codex").others.map(\.id) == ["x1"])
    #expect(section(model, "claude").main?.id == "c1")
    #expect(section(model, "cursor").main == nil)
    #expect(section(model, "cursor").others.isEmpty)
}

@MainActor @Test func switchingOnCreatesMainAccountAtTheEnd() {
    let probe = SettingsProbe()
    let model = probe.model([])
    model.setProviderEnabled("cursor", true)
    model.setProviderEnabled("claude", true)
    model.setProviderEnabled("codex", true)
    #expect(model.profiles == [
        AccountProfile(id: "cursor-default", providerID: "cursor", label: "Default", source: .cursorDefaultDiscovery, enabled: true),
        AccountProfile(id: "claude-default", providerID: "claude", label: "Default", source: .claudeDefaultDiscovery, enabled: true),
        AccountProfile(id: "codex-default", providerID: "codex", label: "Default",
                       source: .codexFile(CredentialStore.defaultCodexPath), enabled: true)
    ])
    #expect(probe.profiles.count == 3)
    #expect(probe.profiles.last == model.profiles)
    #expect(section(model, "cursor").main?.enabled == true)
}

@MainActor @Test func switchingOffKeepsTheProfileAndOthers() {
    let probe = SettingsProbe()
    let list = [profile("codex-default", "codex", "Default", .codexFile("/a")),
                profile("extra", "codex", "Account 2", .codexFile("/b"))]
    let model = probe.model(list)
    model.setProviderEnabled("codex", false)
    #expect(model.profiles.count == 2)
    #expect(model.profiles[0].enabled == false)
    #expect(model.profiles[1].enabled == true)
    #expect(section(model, "codex").main?.status == .off)
    #expect(probe.profiles.count == 1)
    model.setProviderEnabled("codex", false)       // unchanged: no callback
    model.setProviderEnabled("cursor", false)      // no main account: nothing to create
    model.setProviderEnabled("gemini", true)       // unsupported provider
    #expect(probe.profiles.count == 1)
    #expect(model.profiles.count == 2)
}

@MainActor @Test func addRemoveAndAccountNumbering() throws {
    let probe = SettingsProbe()
    let model = probe.model([profile("codex-default", "codex", "Default", .codexFile("/a")),
                             profile("claude-default", "claude")])
    let first = try #require(model.addAccount("codex"))
    let second = try #require(model.addAccount("codex"))
    let claude = try #require(model.addAccount("claude"))
    #expect(model.profiles.first { $0.id == first } ==
            AccountProfile(id: first, providerID: "codex", label: "Account 2",
                           source: .codexFile(CredentialStore.defaultCodexPath), enabled: false))
    #expect(model.profiles.first { $0.id == second }?.label == "Account 3")
    #expect(model.profiles.first { $0.id == claude } ==
            AccountProfile(id: claude, providerID: "claude", label: "Account 2",
                           source: .claudeFile(CredentialStore.defaultClaudePath), enabled: false))
    #expect(model.addAccount("cursor") == nil)
    #expect(model.addAccount("gemini") == nil)
    #expect(probe.profiles.count == 3)
    model.removeAccount(first)
    #expect(model.profiles.first { $0.id == first } == nil)
    let refill = try #require(model.addAccount("codex"))
    #expect(model.profiles.first { $0.id == refill }?.label == "Account 2")
    model.removeAccount("codex-default")
    #expect(model.profiles.contains { $0.id == "codex-default" })
    #expect(section(model, "codex").others.map(\.id) == [second, refill])
    #expect(probe.profiles.count == 5)
}

@MainActor @Test func labelsPathsAndSourcesFollowTheRules() {
    let probe = SettingsProbe()
    let model = probe.model([profile("claude-default", "claude"),
                             profile("x", "codex", "Work", .codexFile("/a")),
                             profile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)])
    model.setLabel("x", "  Personal  ")
    #expect(model.profiles[1].label == "Personal")
    model.setLabel("x", "   ")
    #expect(model.profiles[1].label == "Personal")
    #expect(model.setSourcePath("x", "relative/auth.json") == false)
    #expect(model.setSourcePath("x", "~/auth.json") == false)
    #expect(model.profiles[1].source == .codexFile("/a"))
    #expect(model.setSourcePath("x", " /tmp/codex.json\n"))
    #expect(model.profiles[1].source == .codexFile("/tmp/codex.json"))
    #expect(model.setSourcePath("cursor-default", "/tmp/cursor") == false)
    #expect(model.profiles[2].source == .cursorDefaultDiscovery)
    model.setClaudeUsesKeychain(false)
    #expect(model.profiles[0].source == .claudeFile(CredentialStore.defaultClaudePath))
    #expect(model.setSourcePath("claude-default", "/tmp/claude.json"))
    model.setClaudeUsesKeychain(false)              // keeps the chosen file
    #expect(model.profiles[0].source == .claudeFile("/tmp/claude.json"))
    model.setClaudeUsesKeychain(true)
    #expect(model.profiles[0].source == .claudeDefaultDiscovery)
    model.setAccountEnabled("x", false)
    #expect(model.profiles[1].enabled == false)
    #expect(probe.profiles.count == 6)   // label, two paths, file source, keychain, enable
}

@MainActor @Test func readOnlyModelChangesNothingAndCallsNothing() {
    let probe = SettingsProbe()
    let list = [profile("claude-default", "claude"), profile("x", "codex", "Work", .codexFile("/a"))]
    let model = probe.model(list, count: 3, nudge: true, editable: false)
    model.setProviderEnabled("claude", false)
    model.setProviderEnabled("cursor", true)
    model.setClaudeUsesKeychain(false)
    #expect(model.setSourcePath("x", "/b") == false)
    model.setLabel("x", "Other")
    model.setAccountEnabled("x", false)
    #expect(model.addAccount("codex") == nil)
    model.removeAccount("x")
    model.setNudge(false)
    model.connect("x")
    #expect(model.profiles == list)
    #expect(model.nudgeEnabled == true)
    #expect(probe.callbacks == 0)
    // F5: the indicator count and About work whatever `editable` says.
    model.setIndicatorCount(5)
    model.showAbout()
    #expect(model.indicatorCount == 5 && probe.counts == [5] && probe.abouts == 1)
}

@MainActor @Test func indicatorNudgeConnectAndAboutCallbacks() {
    let probe = SettingsProbe()
    let model = probe.model([], count: 3, nudge: true)
    model.setIndicatorCount(3)
    model.setIndicatorCount(0)
    model.setIndicatorCount(9)
    model.setIndicatorCount(8)
    model.setIndicatorCount(1)
    #expect(probe.counts == [8, 1])
    #expect(model.indicatorCount == 1)
    model.setNudge(true)
    model.setNudge(false)
    model.setNudge(false)
    #expect(probe.nudges == [false])
    #expect(model.nudgeEnabled == false)
    model.connect("claude-default")
    model.showAbout()
    #expect(probe.connects == ["claude-default"])
    #expect(probe.abouts == 1)
    #expect(probe.profiles.isEmpty)
}

@MainActor @Test func updateStatusesMapsRowsOffAndConnecting() {
    let probe = SettingsProbe()
    let model = probe.model([profile("claude-default", "claude"),
                             profile("codex-default", "codex", "Default", .codexFile("/a")),
                             profile("x", "codex", "Off one", .codexFile("/b"), enabled: false),
                             profile("y", "codex", "New one", .codexFile("/c"))])
    model.updateStatuses([row("claude-default", "claude", "Default", .throttled, message: "Retry later"),
                          row("codex-default", "codex", "Default", .unauthenticated),
                          row("x", "codex", "Off one", .healthy)])
    let claude = section(model, "claude").main
    #expect(claude?.status == .throttled && claude?.message == "Retry later")
    #expect(section(model, "codex").main?.status == .signIn)
    let others = section(model, "codex").others
    #expect(others.first { $0.id == "x" }?.status == .off)
    #expect(others.first { $0.id == "x" }?.message == nil)
    #expect(others.first { $0.id == "y" }?.status == .connecting)
    model.setAccountEnabled("y", false)
    #expect(section(model, "codex").others.first { $0.id == "y" }?.status == .off)
    #expect(probe.profiles.count == 1)
    // F7: the monitor's not-yet-fetched row reads Connecting…, with no message; other unavailable rows keep theirs.
    model.updateStatuses([row("claude-default", "claude", "Default", .unavailable, message: "Connecting account"),
                          row("codex-default", "codex", "Default", .unavailable, message: "Provider unavailable")])
    #expect(section(model, "claude").main?.status == .connecting && section(model, "claude").main?.message == nil)
    #expect(section(model, "codex").main?.status == .unavailable && section(model, "codex").main?.message == "Provider unavailable")
}

// MARK: - C3 DropdownModel

@MainActor private final class DropdownProbe {
    var log: [String] = []
    func model(_ rows: [ProfileDisplay], demo: Bool = false) -> DropdownModel {
        let model = DropdownModel()
        model.rows = rows; model.demo = demo
        model.refresh = { self.log.append("refresh") }
        model.settings = { self.log.append("settings") }
        model.quit = { self.log.append("quit") }
        model.connect = { self.log.append("connect:" + $0) }
        return model
    }
}

@MainActor @Test func dropdownActionTitlesInVisualOrder() {
    let probe = DropdownProbe()
    let healthy = row("a", "codex", "Work", .healthy)
    let signIn = row("b", "claude", "Home", .unauthenticated)
    let signIn2 = row("c", "claude", "Lab", .unauthenticated)
    #expect(probe.model([healthy]).actionTitles() == ["Refresh", "Settings", "Quit"])
    #expect(probe.model([signIn, healthy, signIn2]).actionTitles() ==
            ["Refresh", "Settings", "Connect / Authorize Home", "Connect / Authorize Lab", "Quit"])
    #expect(probe.model([signIn], demo: true).actionTitles() == ["Refresh", "Settings", "Quit"])
    #expect(probe.model([]).actionTitles() == ["Refresh", "Settings", "Open Settings", "Quit"])
    #expect(probe.model([], demo: true).actionTitles() == ["Refresh", "Settings", "Quit"])
}

@MainActor @Test func dropdownPerformRoutesToTheRightClosure() {
    let probe = DropdownProbe()
    let model = probe.model([row("b", "claude", "Home", .unauthenticated)])
    for title in ["Refresh", "Settings", "Connect / Authorize Home", "Quit", "Open Settings", "Nonsense", "Connect / Authorize Nobody"] {
        model.perform(title)
    }
    #expect(probe.log == ["refresh", "settings", "connect:b", "quit"])
    probe.log = []
    probe.model([]).perform("Open Settings")
    #expect(probe.log == ["settings"])
    probe.log = []
    probe.model([row("b", "claude", "Home", .unauthenticated)], demo: true).perform("Connect / Authorize Home")
    #expect(probe.log.isEmpty)
}

// MARK: - Controller seams

@MainActor @Test func dropdownSettingsOpensTheSettingsWindowInDemoToo() {
    _ = NSApplication.shared
    let live = AppController(countStore: MemoryIndicatorStore())
    var presented: [ObjectIdentifier] = []
    live.settingsPresenter = { presented.append(ObjectIdentifier($0)) }
    live.configureDropdownActions()
    live.pressDropdownButton("Settings")
    #expect(presented == [ObjectIdentifier(live.settings)])
    live.updateDropdown([])
    #expect(live.hasDropdownButton("Open Settings"))
    live.pressDropdownButton("Open Settings")
    #expect(presented.count == 2)

    // F5: demo presents its read-only model without the router, whose accounts guard is unchanged.
    var accounts = 0
    let router = AppActionRouter(demo: true, refresh: {}, connect: { _ in }, accounts: { accounts += 1 }, quit: {})
    let demo = AppController(demo: true, actionRouter: router)
    demo.settingsPresenter = { presented.append(ObjectIdentifier($0)) }
    demo.prepareDemo()
    demo.pressDropdownButton("Settings")
    #expect(presented.count == 3 && presented.last == ObjectIdentifier(demo.settings))
    #expect(accounts == 0)
    #expect(demo.settings.editable == false)
    #expect(!demo.hasDropdownButton("Open Settings"))
    demo.settings.setIndicatorCount(6)          // in-memory store through selectCount
    #expect(demo.presentedCount == 6)
}

// G2: the demo Settings model holds the demo rows' profiles and their statuses.
@MainActor @Test func demoSettingsMatchTheDemoRows() {
    _ = NSApplication.shared
    let demo = AppController(demo: true)
    demo.prepareDemo()
    let accounts = demo.settings.sections.flatMap { [$0.main].compactMap { $0 } + $0.others }
    #expect(accounts.count == 10 && accounts.allSatisfy { $0.status == .healthy })
    #expect(Set(demo.settings.profiles.map(\.providerID)) == ["claude", "codex"])
    #expect(demo.settings.sections.first { $0.provider == "cursor" }?.main == nil)
    #expect(demo.settings.editable == false)
}

// G3: one mapping; only the exact unavailable placeholder reads Connecting….
@Test func accountStatusFromRow() {
    #expect(AccountStatus(row: row("a", "codex", "A", .unavailable, message: "Connecting account")) == .connecting)
    #expect(AccountStatus(row: row("a", "codex", "A", .failed, message: "Connecting account")) == .failed)
    #expect(AccountStatus(row: row("a", "codex", "A", .unavailable, message: "Provider unavailable")) == .unavailable)
    #expect(AccountStatus(row: row("a", "codex", "A", .unauthenticated)) == .signIn)
}

@MainActor @Test func settingsIndicatorCountDrivesThePresentedCount() {
    _ = NSApplication.shared
    let store = MemoryIndicatorStore(3)
    let controller = AppController(countStore: store)
    controller.settings.setIndicatorCount(6)
    #expect(controller.presentedCount == 6)
    #expect(store.loadCount() == 6)
}

@MainActor @Test func settingsNudgePersistsThroughTheController() {
    _ = NSApplication.shared
    let suite = "limitaur-redesign-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = AppController(countStore: MemoryIndicatorStore(), defaults: defaults, nudger: nil)
    var toggles: [Bool] = []
    controller.nudgeToggled = { toggles.append($0) }
    #expect(controller.settings.nudgeEnabled == true)
    controller.settings.setNudge(false)
    #expect(defaults.object(forKey: "claudeNudgeEnabled") as? Bool == false)
    #expect(toggles == [false])
}

@MainActor @Test func dropdownRowsFeedSettingsStatuses() {
    _ = NSApplication.shared
    let controller = AppController(countStore: MemoryIndicatorStore())
    controller.updateDropdown([row("claude-default", "claude", "Default", .unauthenticated)])
    #expect(controller.dropdownModel.rows.count == 1)
    #expect(controller.hasDropdownButton("Connect / Authorize Default"))
}

// MARK: - C5 P25 eligibility

private struct RedesignFiles: CredentialFileReading {
    let sources: [String: Data]
    func read(path: String) throws -> Data {
        guard let data = sources[path] else { throw CredentialFailure.missing }
        return data
    }
}
private struct RedesignKeychain: KeychainReading {
    let result: KeychainResult
    func claudeCredential() -> KeychainResult { result }
}
private final class RedesignClock: MonitorClock, @unchecked Sendable {
    func wallNow() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
    func monotonicNow() -> TimeInterval { 100 }
}
private actor RedesignTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = request.providerID == "codex" ? #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#
            : #"{"limits":[{"kind":"session","percent":25}]}"#
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
    }
}

@Test func eligibilityCountsOnlyEnabledProfiles() async {
    let codex = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented"}}"#.utf8)
    let files = RedesignFiles(sources: [CredentialStore.defaultCodexPath: codex, "/synthetic-other": codex])
    let monitor = Monitor(clock: RedesignClock(),
                          credentials: CredentialStore(files: files, keychain: RedesignKeychain(result: .found(claude)),
                                                       cursorKeychain: RedesignKeychain(result: .notFound)),
                          transport: RedesignTransport())
    let defaults = [AccountProfile(id: "codex-default", providerID: "codex", label: "Default",
                                   source: .codexFile(CredentialStore.defaultCodexPath)),
                    AccountProfile(id: "claude-default", providerID: "claude", label: "Default", source: .claudeDefaultDiscovery)]
    var third = AccountProfile(id: "third", providerID: "codex", label: "Account 2",
                               source: .codexFile("/synthetic-other"), enabled: false)
    await monitor.setProfiles(defaults + [third]); #expect(await monitor.settle())
    #expect((await monitor.statistics())["__eligibility"]?["eligible"] == 1)
    third.enabled = true
    await monitor.setProfiles(defaults + [third]); #expect(await monitor.settle())
    #expect((await monitor.statistics())["__eligibility"]?["eligible"] == 0)
    await monitor.stop()
}
