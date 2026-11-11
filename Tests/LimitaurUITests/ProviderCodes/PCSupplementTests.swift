import AppKit
import SwiftUI
import Testing
@testable import Limitaur
@testable import LimitaurCore

// SUPPLEMENT written after the candidate was revealed (not part of the frozen set). The frozen PCDropdownTests read header text
// through the accessibility tree, which is empty for an off-screen hosting view in the test process (probed: the tree has no
// children even with the window ordered front), so those four header tests cannot pass on any implementation. These tests
// check the same C8 behaviour through pixels: a header that omits the label does not change with the label.
// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant.

@MainActor private func pcsRow(_ id: String, _ provider: ProviderID, _ label: String) -> ProfileDisplay {
    ProfileDisplay(profile: AccountProfile(id: id, providerID: provider, label: label,
                                           source: provider == "codex" ? .codexFile("/invented/" + id) : .claudeFile("/invented/" + id)),
                   snapshot: nil, health: .healthy, message: nil, fetchedAge: nil)
}
@MainActor private func pcsPanel(_ rows: [ProfileDisplay]) -> [UInt8] {
    _ = NSApplication.shared
    let model = DropdownModel(); model.rows = rows; model.now = Date(timeIntervalSince1970: 1_800_000_000)
    let host = NSHostingView(rootView: DropdownPanel(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 360, height: 560); host.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; defer { window.close() }
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.bitmapData.map { Array(UnsafeBufferPointer(start: $0, count: rep.bytesPerRow * rep.pixelsHigh)) } ?? []
}

@Suite(.serialized) @MainActor struct PCSupplementTests {
    // R, C8: a single card's header does not depend on the account label ("Default" or any other).
    @Test func singleCardIgnoresItsLabel() {
        let a = pcsPanel([pcsRow("claude-default", "claude", "Default")]), b = pcsPanel([pcsRow("claude-default", "claude", "Work")])
        #expect(!a.isEmpty && a == b)
    }
    // N, C8: with two cards of one provider the label is part of the header.
    @Test func twoCardsShowTheirLabels() {
        let a = pcsPanel([pcsRow("codex-default", "codex", "Default"), pcsRow("codex-work", "codex", "Work")])
        let b = pcsPanel([pcsRow("codex-default", "codex", "Default"), pcsRow("codex-work", "codex", "Home")])
        let c = pcsPanel([pcsRow("codex-default", "codex", "Other"), pcsRow("codex-work", "codex", "Work")])
        #expect(a != b && a != c, "each card's header carries its own label")
    }
    // I, C8: the count is per provider: a lone Claude card stays label-free beside two Codex cards.
    @Test func countIsPerProvider() {
        let codex = [pcsRow("codex-default", "codex", "Default"), pcsRow("codex-work", "codex", "Work")]
        let a = pcsPanel(codex + [pcsRow("claude-default", "claude", "Default")]), b = pcsPanel(codex + [pcsRow("claude-default", "claude", "Other")])
        #expect(a == b)
    }
}
