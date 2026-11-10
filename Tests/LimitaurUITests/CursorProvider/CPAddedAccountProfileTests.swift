import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Ported from the Accounts dialog's "Add" button mapping (addedAccountProfile) to SettingsModel.addAccount: the button
// mapping is gone by specification (S1, S3); the surviving invariants are that adding appends a disabled profile and that
// only Codex and Claude can be added.

@Suite @MainActor struct CPAddedAccountProfileTests {
    // I: adding a Codex or Claude account appends a disabled profile (no expected account id) on the provider's file source.
    // The label ("Account <n>") and the Claude source (a file, not Keychain discovery) changed by specification I1.
    @Test func addCodexAndAddClaudeAreUnchanged() throws {
        let probe = RDSettingsProbe()
        let model = probe.model([])
        let codexID = try #require(model.addAccount("codex")), claudeID = try #require(model.addAccount("claude"))
        #expect(model.profiles == [
            AccountProfile(id: codexID, providerID: "codex", label: "Account 2", source: .codexFile(CredentialStore.defaultCodexPath),
                           expectedAccountID: nil, enabled: false),
            AccountProfile(id: claudeID, providerID: "claude", label: "Account 2", source: .claudeFile(CredentialStore.defaultClaudePath),
                           expectedAccountID: nil, enabled: false)])
        #expect(probe.lists.count == 2)
    }
    // N (replaces otherResponsesAddNothing): no other provider adds anything; Cursor is refused by specification S3.
    @Test func otherProvidersAddNothing() {
        let probe = RDSettingsProbe()
        let model = probe.model()
        for provider in ["cursor", "unknown", "Codex", "CLAUDE", ""] as [ProviderID] { #expect(model.addAccount(provider) == nil) }
        #expect(model.profiles == rdFreshInstall && probe.callbacks == 0)
    }
    // N (replaces idIsUsedVerbatim): each added account gets its own fresh identifier, distinct from every existing id.
    @Test func addedAccountsGetDistinctIdentifiers() throws {
        let model = RDSettingsProbe().model()
        let ids = try (0..<4).map { try #require(model.addAccount($0.isMultiple(of: 2) ? "codex" : "claude")) }
        #expect(Set(ids).count == 4 && Set(ids).isDisjoint(with: rdFreshInstall.map(\.id)))
        #expect(model.profiles.suffix(4).map(\.id) == ids && model.profiles.suffix(4).allSatisfy { !$0.enabled })
    }
    // R (replaces addCursorMapsToTheCursorProfile): a Cursor profile is created by the section switch, not an Add button:
    // it is the main account on the cursor-agent source, enabled, with label "Default".
    @Test func cursorProfileComesFromTheSectionSwitch() {
        let model = RDSettingsProbe().model()
        model.setProviderEnabled("cursor", true)
        #expect(model.profiles.last == AccountProfile(id: "cursor-default", providerID: "cursor", label: "Default",
                                                      source: .cursorDefaultDiscovery, expectedAccountID: nil, enabled: true))
    }
}
