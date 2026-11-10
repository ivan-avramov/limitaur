import AppKit
import Foundation
@testable import Limitaur
@testable import LimitaurCore

let rdCodexDefault = AccountProfile(id: "codex-default", providerID: "codex", label: "Default",
                                    source: .codexFile(CredentialStore.defaultCodexPath))
let rdClaudeDefault = AccountProfile(id: "claude-default", providerID: "claude", label: "Default",
                                     source: .claudeDefaultDiscovery)
let rdFreshInstall = [rdCodexDefault, rdClaudeDefault]

func rdProfile(_ id: String, _ provider: ProviderID, _ label: String, _ source: CredentialSource,
               enabled: Bool = true) -> AccountProfile {
    AccountProfile(id: id, providerID: provider, label: label, source: source, enabled: enabled)
}

/// Records every callback a SettingsModel makes.
@MainActor final class RDSettingsProbe {
    var lists: [[AccountProfile]] = []
    var counts: [Int] = []
    var nudges: [Bool] = []
    var connects: [String] = []
    var abouts = 0
    var callbacks: Int { lists.count + counts.count + nudges.count + connects.count + abouts }
    func model(_ profiles: [AccountProfile] = rdFreshInstall, count: Int = 3, nudge: Bool = true,
               editable: Bool = true) -> SettingsModel {
        SettingsModel(profiles: profiles, indicatorCount: count, nudgeEnabled: nudge, editable: editable,
                      onProfiles: { self.lists.append($0) }, onIndicatorCount: { self.counts.append($0) },
                      onNudge: { self.nudges.append($0) }, onConnect: { self.connects.append($0) },
                      onAbout: { self.abouts += 1 })
    }
}

@MainActor func rdSection(_ model: SettingsModel, _ provider: ProviderID) -> SettingsSection? {
    model.sections.first { $0.provider == provider }
}

/// Records router actions with their arguments.
@MainActor final class RDRouterProbe {
    var refreshes = 0, accounts = 0, quits = 0
    var connected: [String] = []
    func router(demo: Bool) -> AppActionRouter {
        AppActionRouter(demo: demo, refresh: { self.refreshes += 1 }, connect: { self.connected.append($0) },
                        accounts: { self.accounts += 1 }, quit: { self.quits += 1 })
    }
}

@MainActor final class RDCountStore: IndicatorPreferenceStore {
    var reads = 0
    var writes: [Int] = []
    private var value: Int
    init(_ value: Int = 3) { self.value = value }
    func loadCount() -> Int { reads += 1; return value }
    func saveCount(_ count: Int) { writes.append(count); value = count }
}

func rdRow(_ id: String = "claude-default", provider: ProviderID = "claude", label: String = "Synthetic",
           health: Health = .healthy, message: String? = nil, enabled: Bool = true) -> ProfileDisplay {
    ProfileDisplay(profile: AccountProfile(id: id, providerID: provider, label: label,
                                           source: provider == "codex" ? .codexFile("/invented") : .claudeFile("/invented"),
                                           enabled: enabled),
                   snapshot: nil, health: health, message: message, fetchedAge: nil)
}
