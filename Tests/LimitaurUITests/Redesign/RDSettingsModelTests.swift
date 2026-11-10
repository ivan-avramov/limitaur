import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Criterion C2 unless stated.

@Suite @MainActor struct RDSettingsModelTests {
    // MARK: sections and the main account (I1)

    // N: three sections, always Claude, Codex, Cursor, whatever the saved order or content.
    @Test(arguments: [[], rdFreshInstall, rdFreshInstall.reversed(),
                      [rdProfile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)]] as [[AccountProfile]])
    func sectionsAreAlwaysClaudeCodexCursor(_ profiles: [AccountProfile]) {
        let model = RDSettingsProbe().model(profiles)
        #expect(model.sections.map(\.provider.rawValue) == ["claude", "codex", "cursor"])
        #expect(model.sections.map(\.id) == ["claude", "codex", "cursor"])
    }
    // N: fresh install defaults: Codex and Claude on, Cursor has no main account.
    @Test func freshInstallShowsCodexAndClaudeOnAndCursorOff() {
        let model = RDSettingsProbe().model()
        #expect(rdSection(model, "claude")?.main?.id == "claude-default" && rdSection(model, "claude")?.main?.enabled == true)
        #expect(rdSection(model, "codex")?.main?.id == "codex-default" && rdSection(model, "codex")?.main?.enabled == true)
        #expect(rdSection(model, "cursor")?.main == nil && rdSection(model, "cursor")?.others.isEmpty == true)
    }
    // N: the profile with id "<provider>-default" is the main account even when it is not first.
    @Test func mainAccountPrefersTheDefaultID() {
        let other = rdProfile("claude-x", "claude", "Work", .claudeFile("/x"))
        let model = RDSettingsProbe().model([other, rdClaudeDefault])
        let section = rdSection(model, "claude")
        #expect(section?.main?.id == "claude-default")
        #expect(section?.others.map(\.id) == ["claude-x"])
    }
    // N: without a default id, the first profile of the provider in saved order is the main account.
    @Test func mainAccountFallsBackToTheFirstOfTheProvider() {
        let first = rdProfile("codex-a", "codex", "A", .codexFile("/a")), second = rdProfile("codex-b", "codex", "B", .codexFile("/b"))
        let model = RDSettingsProbe().model([rdClaudeDefault, first, second])
        let section = rdSection(model, "codex")
        #expect(section?.main?.id == "codex-a" && section?.main?.label == "A")
        #expect(section?.others.map(\.id) == ["codex-b"])
    }
    // N: a SettingsAccount carries the profile's label, switch and source; others keep saved order.
    @Test func accountsCarryProfileFieldsAndSavedOrder() {
        let a = rdProfile("a", "codex", "Alpha", .codexFile("/a"), enabled: false)
        let b = rdProfile("b", "codex", "Beta", .codexFile("/b"))
        let model = RDSettingsProbe().model([rdCodexDefault, b, a])
        let section = rdSection(model, "codex")
        #expect(section?.others.map(\.id) == ["b", "a"])
        #expect(section?.others.map(\.label) == ["Beta", "Alpha"])
        #expect(section?.others.map(\.enabled) == [true, false])
        #expect(section?.others.map(\.source) == [.codexFile("/b"), .codexFile("/a")])
        #expect(model.profiles == [rdCodexDefault, b, a])
    }

    // MARK: provider switch

    // N: turning a missing section on appends the specified main account and calls onProfiles once with the full list.
    @Test(arguments: [("claude", CredentialSource.claudeDefaultDiscovery), ("codex", .codexFile(CredentialStore.defaultCodexPath)),
                      ("cursor", .cursorDefaultDiscovery)] as [(ProviderID, CredentialSource)])
    func switchingOnCreatesTheMainAccount(_ provider: ProviderID, _ source: CredentialSource) {
        let probe = RDSettingsProbe()
        let existing = rdProfile("zzz", provider == "codex" ? "claude" : "codex", "Z", .claudeFile("/z"))
        let model = probe.model([existing])
        model.setProviderEnabled(provider, true)
        let created = AccountProfile(id: provider.rawValue + "-default", providerID: provider, label: "Default",
                                     source: source, enabled: true)
        #expect(model.profiles == [existing, created])
        #expect(probe.lists == [[existing, created]])
        #expect(rdSection(model, provider)?.main?.id == created.id)
        #expect(rdSection(model, provider)?.main?.enabled == true)
    }
    // N: turning a section on enables an existing main account in place and creates nothing, keeping its source.
    @Test func switchingOnEnablesTheExistingMainInPlace() {
        let probe = RDSettingsProbe()
        let main = rdProfile("claude-default", "claude", "Default", .claudeFile("/kept"), enabled: false)
        let model = probe.model([main, rdCodexDefault])
        model.setProviderEnabled("claude", true)
        var expected = main
        expected.enabled = true
        #expect(model.profiles == [expected, rdCodexDefault])
        #expect(probe.lists.count == 1)
    }
    // N: with no default id, the first profile of the provider is enabled instead of creating "<provider>-default".
    @Test func switchingOnUsesTheFallbackMainAccount() {
        let probe = RDSettingsProbe()
        let first = rdProfile("cursor-a", "cursor", "A", .cursorDefaultDiscovery, enabled: false)
        let model = probe.model([first])
        model.setProviderEnabled("cursor", true)
        #expect(model.profiles.map(\.id) == ["cursor-a"] && model.profiles.first?.enabled == true)
        #expect(probe.lists.count == 1)
    }
    // N: turning a section off disables only the main account and keeps every profile; other accounts keep their switches.
    @Test func switchingOffKeepsTheProfileAndOtherAccounts() {
        let probe = RDSettingsProbe()
        let other = rdProfile("codex-2", "codex", "Account 2", .codexFile("/two"))
        let model = probe.model([rdCodexDefault, rdClaudeDefault, other])
        model.setProviderEnabled("codex", false)
        var off = rdCodexDefault
        off.enabled = false
        #expect(model.profiles == [off, rdClaudeDefault, other])
        #expect(rdSection(model, "codex")?.main?.enabled == false)
        #expect(rdSection(model, "codex")?.others.first?.enabled == true)
        #expect(probe.lists.count == 1)
    }
    // N: off then on again reuses the kept profile instead of adding a second one.
    @Test func offThenOnDoesNotDuplicateTheMainAccount() {
        let probe = RDSettingsProbe()
        let model = probe.model()
        model.setProviderEnabled("claude", false)
        model.setProviderEnabled("claude", true)
        #expect(model.profiles == rdFreshInstall)
        #expect(probe.lists.count == 2)
    }

    // MARK: other accounts

    // N: adding appends a disabled "Account 2" with the provider's file source and a fresh UUID id, one onProfiles call.
    @Test(arguments: [("codex", CredentialSource.codexFile(CredentialStore.defaultCodexPath)),
                      ("claude", .claudeFile(CredentialStore.defaultClaudePath))] as [(ProviderID, CredentialSource)])
    func addAccountAppendsADisabledProfile(_ provider: ProviderID, _ source: CredentialSource) throws {
        let probe = RDSettingsProbe()
        let model = probe.model()
        let id = try #require(model.addAccount(provider))
        #expect(UUID(uuidString: id) != nil)
        let added = AccountProfile(id: id, providerID: provider, label: "Account 2", source: source, expectedAccountID: nil, enabled: false)
        #expect(model.profiles == rdFreshInstall + [added])
        #expect(probe.lists == [rdFreshInstall + [added]])
        #expect(rdSection(model, provider)?.others.map(\.id) == [id])
    }
    // N: numbering takes the smallest integer >= 2 not already used as an "Account <n>" label of that provider.
    @Test func accountNumbersFillTheSmallestFreeSlot() throws {
        let model = RDSettingsProbe().model()
        let ids = try (0..<3).map { _ in try #require(model.addAccount("codex")) }
        #expect(rdSection(model, "codex")?.others.map(\.label) == ["Account 2", "Account 3", "Account 4"])
        #expect(Set(ids).count == 3)
        model.removeAccount(ids[0])   // frees "Account 2"
        _ = model.addAccount("codex")
        #expect(rdSection(model, "codex")?.others.map(\.label) == ["Account 3", "Account 4", "Account 2"])
        model.setLabel(ids[1], "Work")   // frees "Account 3"
        _ = model.addAccount("codex")
        #expect(rdSection(model, "codex")?.others.last?.label == "Account 3")
    }
    // N: numbering is per provider.
    @Test func accountNumbersAreCountedPerProvider() throws {
        let model = RDSettingsProbe().model()
        _ = model.addAccount("codex"); _ = model.addAccount("codex")
        _ = model.addAccount("claude")
        #expect(rdSection(model, "claude")?.others.map(\.label) == ["Account 2"])
        #expect(rdSection(model, "codex")?.others.map(\.label) == ["Account 2", "Account 3"])
    }
    // N: a label typed as "Account 2" on a differently-labelled profile of the same provider is counted as used.
    @Test func typedAccountLabelsAreCountedAsUsed() throws {
        let model = RDSettingsProbe().model([rdCodexDefault, rdProfile("x", "codex", "Account 2", .codexFile("/x")),
                                             rdProfile("y", "codex", "Account 4", .codexFile("/y"))])
        _ = model.addAccount("codex")
        #expect(rdSection(model, "codex")?.others.last?.label == "Account 3")
    }
    // N: Cursor cannot be added; unknown providers cannot either; nothing changes and nothing is called.
    @Test(arguments: ["cursor", "other", ""] as [ProviderID])
    func addAccountIsRefusedForCursorAndUnknownProviders(_ provider: ProviderID) {
        let probe = RDSettingsProbe()
        let model = probe.model()
        #expect(model.addAccount(provider) == nil)
        #expect(model.profiles == rdFreshInstall && probe.callbacks == 0)
    }
    // N: removing deletes only that other account, with one onProfiles call.
    @Test func removeAccountDeletesTheOtherAccount() throws {
        let probe = RDSettingsProbe()
        let model = probe.model()
        let id = try #require(model.addAccount("claude"))
        probe.lists.removeAll()
        model.removeAccount(id)
        #expect(model.profiles == rdFreshInstall && probe.lists == [rdFreshInstall])
        #expect(rdSection(model, "claude")?.others.isEmpty == true)
    }
    // N: a main account cannot be removed, and an unknown id is ignored; nothing changes and nothing is called.
    @Test func mainAccountCannotBeRemoved() {
        let probe = RDSettingsProbe()
        let model = probe.model()
        model.removeAccount("claude-default"); model.removeAccount("codex-default"); model.removeAccount("missing")
        #expect(model.profiles == rdFreshInstall && probe.callbacks == 0)
    }
    // I: a fallback main account (no default id) is also protected from removal.
    @Test func fallbackMainAccountCannotBeRemoved() {
        let probe = RDSettingsProbe()
        let first = rdProfile("codex-a", "codex", "A", .codexFile("/a"))
        let model = probe.model([first, rdProfile("codex-b", "codex", "B", .codexFile("/b"))])
        model.removeAccount("codex-a")
        #expect(model.profiles.map(\.id) == ["codex-a", "codex-b"] && probe.callbacks == 0)
    }
    // N: existing extra Cursor profiles are listed as others and can be removed.
    @Test func extraCursorProfilesAreListedAndRemovable() {
        let probe = RDSettingsProbe()
        let main = rdProfile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)
        let extra = rdProfile("cursor-old", "cursor", "Old", .cursorDefaultDiscovery, enabled: false)
        let model = probe.model(rdFreshInstall + [main, extra])
        #expect(rdSection(model, "cursor")?.others.map(\.id) == ["cursor-old"])
        model.removeAccount("cursor-old")
        #expect(model.profiles == rdFreshInstall + [main] && probe.lists.count == 1)
    }
    // N: an other account's switch changes only that profile; a main account's switch is also settable by id.
    @Test func setAccountEnabledChangesOnlyThatProfile() throws {
        let probe = RDSettingsProbe()
        let model = probe.model()
        let id = try #require(model.addAccount("codex"))
        probe.lists.removeAll()
        model.setAccountEnabled(id, true)
        #expect(rdSection(model, "codex")?.others.first?.enabled == true && probe.lists.count == 1)
        #expect(rdSection(model, "codex")?.main?.enabled == true && rdSection(model, "claude")?.main?.enabled == true)
        model.setAccountEnabled(id, false)
        #expect(rdSection(model, "codex")?.others.first?.enabled == false && probe.lists.count == 2)
    }

    // MARK: labels and paths

    // N: setLabel trims whitespace; an empty or blank result keeps the old label.
    @Test func setLabelTrimsAndKeepsTheOldLabelWhenEmpty() throws {
        let probe = RDSettingsProbe()
        let model = probe.model()
        let id = try #require(model.addAccount("codex"))
        probe.lists.removeAll()
        model.setLabel(id, "  Work laptop \n")
        #expect(rdSection(model, "codex")?.others.first?.label == "Work laptop" && probe.lists.count == 1)
        model.setLabel(id, "")
        model.setLabel(id, " \t\n ")
        #expect(rdSection(model, "codex")?.others.first?.label == "Work laptop")
        #expect(model.profiles.last?.label == "Work laptop")
    }
    // N: an absolute path is trimmed and stored in the provider's file source; the call reports success.
    @Test func setSourcePathStoresTrimmedAbsolutePaths() throws {
        let probe = RDSettingsProbe()
        let model = probe.model()
        let codexID = try #require(model.addAccount("codex")), claudeID = try #require(model.addAccount("claude"))
        probe.lists.removeAll()
        #expect(model.setSourcePath(codexID, "  /tmp/codex auth.json\n"))
        #expect(model.setSourcePath(claudeID, "/tmp/claude.json"))
        #expect(model.setSourcePath("claude-default", "/tmp/main.json"))
        #expect(model.profiles.first { $0.id == codexID }?.source == .codexFile("/tmp/codex auth.json"))
        #expect(model.profiles.first { $0.id == claudeID }?.source == .claudeFile("/tmp/claude.json"))
        #expect(model.profiles.first { $0.id == "claude-default" }?.source == .claudeFile("/tmp/main.json"))
        #expect(probe.lists.count == 3)
    }
    // R: the baseline dialog beeped and refused relative paths on Save; now each is refused without any change or callback.
    @Test(arguments: ["relative/path.json", "~/auth.json", "", "   ", "./x", " x/ /y"])
    func setSourcePathRejectsNonAbsolutePaths(_ path: String) throws {
        let probe = RDSettingsProbe()
        let model = probe.model()
        let id = try #require(model.addAccount("codex"))
        probe.lists.removeAll()
        let before = model.profiles
        #expect(model.setSourcePath(id, path) == false)
        #expect(model.profiles == before && probe.lists.isEmpty)
    }
    // N: a Cursor account never takes a path; neither does an unknown account.
    @Test func setSourcePathIsRefusedForCursor() {
        let probe = RDSettingsProbe()
        let main = rdProfile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)
        let model = probe.model(rdFreshInstall + [main])
        #expect(model.setSourcePath("cursor-default", "/tmp/x") == false)
        #expect(model.setSourcePath("missing", "/tmp/x") == false)
        #expect(model.profiles == rdFreshInstall + [main] && probe.callbacks == 0)
    }
    // N: the Claude source switch maps to Keychain discovery or a credential file, keeping the file path while it is a file.
    @Test func claudeKeychainSwitchMapsSources() {
        let probe = RDSettingsProbe()
        let model = probe.model()
        func source() -> CredentialSource? { model.profiles.first { $0.id == "claude-default" }?.source }
        model.setClaudeUsesKeychain(false)
        #expect(source() == .claudeFile(CredentialStore.defaultClaudePath))
        #expect(model.setSourcePath("claude-default", "/tmp/c.json"))
        model.setClaudeUsesKeychain(false)
        #expect(source() == .claudeFile("/tmp/c.json"))
        model.setClaudeUsesKeychain(true)
        #expect(source() == .claudeDefaultDiscovery)
        #expect(rdSection(model, "claude")?.main?.source == .claudeDefaultDiscovery)
        #expect(model.profiles.filter { $0.providerID == "codex" } == [rdCodexDefault])
    }
    // N: the Claude source switch does nothing without a Claude main account.
    @Test func claudeKeychainSwitchNeedsAMainAccount() {
        let probe = RDSettingsProbe()
        let model = probe.model([rdCodexDefault])
        model.setClaudeUsesKeychain(false); model.setClaudeUsesKeychain(true)
        #expect(model.profiles == [rdCodexDefault] && probe.lists.isEmpty)
    }

    // MARK: indicators and nudge

    // I: the indicator count accepts 1...8 and calls onIndicatorCount only when the value changes.
    @Test func indicatorCountAcceptsOneToEightAndCallsOnChange() {
        let probe = RDSettingsProbe()
        let model = probe.model(count: 3)
        #expect(model.indicatorCount == 3)
        model.setIndicatorCount(3)
        #expect(probe.counts.isEmpty)
        for value in 1...8 where value != 3 { model.setIndicatorCount(value) }
        #expect(probe.counts == [1, 2, 4, 5, 6, 7, 8] && model.indicatorCount == 8)
        model.setIndicatorCount(8)
        #expect(probe.counts.count == 7)
    }
    // I: values outside 1...8 are ignored.
    @Test(arguments: [0, 9, -1, 100, Int.max, Int.min])
    func indicatorCountIgnoresOutOfRangeValues(_ value: Int) {
        let probe = RDSettingsProbe()
        let model = probe.model(count: 4)
        model.setIndicatorCount(value)
        #expect(model.indicatorCount == 4 && probe.counts.isEmpty && probe.callbacks == 0)
    }
    // N: the nudge setting calls onNudge only when the value changes.
    @Test func nudgeCallsOnChangeOnly() {
        let probe = RDSettingsProbe()
        let model = probe.model(nudge: true)
        model.setNudge(true)
        #expect(probe.nudges.isEmpty && model.nudgeEnabled)
        model.setNudge(false); model.setNudge(false); model.setNudge(true)
        #expect(probe.nudges == [false, true] && model.nudgeEnabled)
    }
    // N: connect and about reach their callbacks; connect passes the account id.
    @Test func connectAndAboutReachTheirCallbacks() {
        let probe = RDSettingsProbe()
        let model = probe.model()
        model.connect("codex-default"); model.connect("claude-default"); model.showAbout()
        #expect(probe.connects == ["codex-default", "claude-default"] && probe.abouts == 1)
        #expect(probe.lists.isEmpty && probe.counts.isEmpty && probe.nudges.isEmpty)
    }

    // MARK: not editable (demo)

    // I: demo disables account, connect and nudge actions: with editable false the provider mutators, nudge and connect do
    // nothing and call nothing. F5 (Revision 2): setIndicatorCount and showAbout work whatever `editable` says.
    @Test func nonEditableModelIgnoresEveryMutator() {
        let probe = RDSettingsProbe()
        let extra = rdProfile("codex-2", "codex", "Account 2", .codexFile("/two"), enabled: false)
        let start = rdFreshInstall + [extra]
        let model = probe.model(start, count: 3, nudge: true, editable: false)
        #expect(model.editable == false)
        model.setProviderEnabled("claude", false); model.setProviderEnabled("cursor", true)
        model.setClaudeUsesKeychain(false)
        #expect(model.setSourcePath("codex-2", "/tmp/x") == false)
        model.setLabel("codex-2", "Renamed")
        model.setAccountEnabled("codex-2", true)
        #expect(model.addAccount("codex") == nil)
        model.removeAccount("codex-2")
        model.setNudge(false)
        model.connect("claude-default")
        #expect(model.profiles == start && model.nudgeEnabled)
        #expect(probe.callbacks == 0)
        model.setIndicatorCount(5)   // F5
        model.showAbout()            // F5
        #expect(model.indicatorCount == 5 && probe.counts == [5] && probe.abouts == 1)
        #expect(model.profiles == start && probe.lists.isEmpty && probe.nudges.isEmpty && probe.connects.isEmpty)
        model.setIndicatorCount(9)
        #expect(model.indicatorCount == 5 && probe.counts == [5])
    }
    // N: editable is stored as given.
    @Test func editableFlagIsExposed() {
        #expect(RDSettingsProbe().model(editable: true).editable)
        #expect(!RDSettingsProbe().model(editable: false).editable)
    }

    // MARK: statuses

    // N: every Health maps to its status, and the row's message is carried over.
    @Test(arguments: [(Health.healthy, AccountStatus.healthy), (.partial, .partial), (.throttled, .throttled), (.stale, .stale),
                      (.unavailable, .unavailable), (.failed, .failed), (.unauthenticated, .signIn)] as [(Health, AccountStatus)])
    func updateStatusesMapsHealth(_ health: Health, _ status: AccountStatus) {
        let model = RDSettingsProbe().model()
        model.updateStatuses([rdRow("claude-default", health: health, message: "note")])
        let account = rdSection(model, "claude")?.main
        #expect(account?.status == status && account?.message == "note")
    }
    // R, F7: the monitor's "Connecting account" placeholder (health .unavailable) shows as Connecting… with no message.
    @Test func connectingPlaceholderMapsToConnecting() {
        let model = RDSettingsProbe().model()
        model.updateStatuses([rdRow("claude-default", health: .unavailable, message: "Connecting account")])
        #expect(rdSection(model, "claude")?.main?.status == .connecting && rdSection(model, "claude")?.main?.message == nil)
    }
    // R, F7: other unavailable messages, and other health values with that text, keep their own status and message.
    @Test(arguments: [("Provider unavailable", Health.unavailable, AccountStatus.unavailable),
                      ("connecting account", .unavailable, .unavailable), ("Connecting account ", .unavailable, .unavailable),
                      ("Connecting account", .failed, .failed)] as [(String, Health, AccountStatus)])
    func otherMessagesKeepTheirStatus(_ message: String, _ health: Health, _ status: AccountStatus) {
        let model = RDSettingsProbe().model()
        model.updateStatuses([rdRow("claude-default", health: health, message: message)])
        #expect(rdSection(model, "claude")?.main?.status == status && rdSection(model, "claude")?.main?.message == message)
    }
    // R, G3: the shared row mapping gives .connecting only for an unavailable row with exactly "Connecting account".
    @Test func rowMappingConnectingPlaceholder() {
        #expect(AccountStatus(row: rdRow(health: .unavailable, message: "Connecting account")) == .connecting)
        #expect(AccountStatus(row: rdRow(health: .unavailable, message: "Other")) == .unavailable)
        #expect(AccountStatus(row: rdRow(health: .unavailable, message: nil)) == .unavailable)
        #expect(AccountStatus(row: rdRow(health: .failed, message: "Connecting account")) == .failed)
        #expect(AccountStatus(row: rdRow(health: .stale, message: "Connecting account")) == .stale)
    }
    // I, G3: every other row maps by health, with or without a message.
    @Test(arguments: [(Health.healthy, AccountStatus.healthy), (.partial, .partial), (.throttled, .throttled), (.stale, .stale),
                      (.unavailable, .unavailable), (.failed, .failed), (.unauthenticated, .signIn)] as [(Health, AccountStatus)])
    func rowMappingMatchesHealthMapping(_ health: Health, _ status: AccountStatus) {
        #expect(AccountStatus(row: rdRow(health: health, message: nil)) == status)
        #expect(AccountStatus(row: rdRow(health: health, message: "note")) == status)
        #expect(AccountStatus(health) == status)
    }
    // R, G3: Settings and the shared row mapping (which the dropdown card's chip uses) agree for every row, and a connecting
    // account carries no message in Settings while other messages are kept.
    @Test func settingsAgreeWithTheSharedRowMapping() {
        let model = RDSettingsProbe().model()
        let rows = [rdRow("claude-default", health: .unavailable, message: "Connecting account"),
                    rdRow("codex-default", provider: "codex", health: .unavailable, message: "Provider down")]
        model.updateStatuses(rows)
        #expect(rdSection(model, "claude")?.main?.status == AccountStatus(row: rows[0]))
        #expect(rdSection(model, "codex")?.main?.status == AccountStatus(row: rows[1]))
        #expect(rdSection(model, "claude")?.main?.status == .connecting && rdSection(model, "claude")?.main?.message == nil)
        #expect(rdSection(model, "codex")?.main?.status == .unavailable && rdSection(model, "codex")?.main?.message == "Provider down")
    }
    // N: an unavailable row with no message stays Unavailable.
    @Test func unavailableWithoutMessageStaysUnavailable() {
        let model = RDSettingsProbe().model()
        model.updateStatuses([rdRow("claude-default", health: .unavailable, message: nil)])
        #expect(rdSection(model, "claude")?.main?.status == .unavailable)
    }
    // N: rows map by profile id, not by position or provider; an enabled account without a row is Connecting…
    @Test func updateStatusesMapsByProfileIDAndShowsConnecting() throws {
        let model = RDSettingsProbe().model()
        let id = try #require(model.addAccount("codex"))
        model.setAccountEnabled(id, true)
        model.updateStatuses([rdRow("codex-default", provider: "codex", health: .throttled)])
        #expect(rdSection(model, "codex")?.main?.status == .throttled)
        #expect(rdSection(model, "claude")?.main?.status == .connecting)
        #expect(rdSection(model, "codex")?.others.first?.status == .connecting)
    }
    // N: a disabled account shows Off, even when a stale row for it arrives; the row's health does not leak.
    @Test func updateStatusesShowsOffForDisabledAccounts() {
        let model = RDSettingsProbe().model()
        model.setProviderEnabled("claude", false)
        model.updateStatuses([rdRow("claude-default", health: .healthy, message: "x")])
        #expect(rdSection(model, "claude")?.main?.status == .off)
        #expect(rdSection(model, "codex")?.main?.status == .connecting)
    }
    // N: a later update replaces earlier statuses, and a row that disappears returns the account to Connecting….
    @Test func updateStatusesReplacesPreviousStatuses() {
        let model = RDSettingsProbe().model()
        model.updateStatuses([rdRow("claude-default", health: .healthy), rdRow("codex-default", provider: "codex", health: .unauthenticated)])
        #expect(rdSection(model, "codex")?.main?.status == .signIn)
        model.updateStatuses([rdRow("claude-default", health: .failed)])
        #expect(rdSection(model, "claude")?.main?.status == .failed)
        #expect(rdSection(model, "codex")?.main?.status == .connecting)
    }
    // N: switching an account off and on again moves its status Off <-> Connecting… until a row arrives; no onProfiles surprises.
    @Test func statusFollowsTheSwitch() {
        let probe = RDSettingsProbe()
        let model = probe.model()
        model.updateStatuses([rdRow("claude-default", health: .healthy)])
        model.setProviderEnabled("claude", false)
        model.updateStatuses([])
        #expect(rdSection(model, "claude")?.main?.status == .off)
        model.setProviderEnabled("claude", true)
        model.updateStatuses([])
        #expect(rdSection(model, "claude")?.main?.status == .connecting)
        #expect(probe.lists.count == 2)
    }
}
