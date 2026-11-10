import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline has no Add Cursor result mapping),
// I = preserves an invariant, N = exercises new behaviour.

private func cpResponse(offset: Int) -> NSApplication.ModalResponse {
    NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + offset)
}

@Suite @MainActor struct CPAddedAccountProfileTests {
    // R, I7: the third button + 2 appends a disabled Cursor profile on the cursor-agent source.
    @Test func addCursorMapsToTheCursorProfile() {
        let profile = addedAccountProfile(for: cpResponse(offset: 2), id: "id-cursor")
        #expect(profile == AccountProfile(id: "id-cursor", providerID: "cursor", label: "New account",
                                          source: .cursorDefaultDiscovery, expectedAccountID: nil, enabled: false))
    }
    // I, I7: the existing Codex and Claude results keep their profiles, now with explicit mapping.
    @Test func addCodexAndAddClaudeAreUnchanged() {
        let codex = addedAccountProfile(for: .alertThirdButtonReturn, id: "id-codex")
        #expect(codex == AccountProfile(id: "id-codex", providerID: "codex", label: "New account",
                                        source: .codexFile(CredentialStore.defaultCodexPath), expectedAccountID: nil, enabled: false))
        let claude = addedAccountProfile(for: cpResponse(offset: 1), id: "id-claude")
        #expect(claude == AccountProfile(id: "id-claude", providerID: "claude", label: "New account",
                                         source: .claudeDefaultDiscovery, expectedAccountID: nil, enabled: false))
    }
    // N, I7: any other result changes nothing, including Save, Cancel and results beyond the Cursor button.
    @Test func otherResponsesAddNothing() {
        let others: [NSApplication.ModalResponse] = [.alertFirstButtonReturn, .alertSecondButtonReturn, cpResponse(offset: 3), cpResponse(offset: 4),
                                                     cpResponse(offset: -1), .OK, .cancel, .stop, .abort, .continue,
                                                     NSApplication.ModalResponse(rawValue: 0), NSApplication.ModalResponse(rawValue: Int.max),
                                                     NSApplication.ModalResponse(rawValue: Int.min)]
        for response in others { #expect(addedAccountProfile(for: response, id: "x") == nil) }
    }
    // N, I7: the given ID is used verbatim and the three results produce three distinct providers.
    @Test func idIsUsedVerbatim() {
        let ids = (0...2).compactMap { addedAccountProfile(for: cpResponse(offset: $0), id: "fixed-\($0)") }
        #expect(ids.map(\.id) == ["fixed-0", "fixed-1", "fixed-2"])
        #expect(ids.map(\.providerID.rawValue) == ["codex", "claude", "cursor"])
        #expect(Set(ids.map(\.source.stableID)).count == 3 && ids.allSatisfy { !$0.enabled && $0.label == "New account" })
    }
}
