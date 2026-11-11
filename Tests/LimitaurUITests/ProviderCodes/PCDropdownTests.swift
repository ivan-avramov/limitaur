import AppKit
import SwiftUI
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Criteria C7/C8 (dropdown). No view-inspection seam exists, so the panel is hosted off-screen: the card header text is read
// from the accessibility tree (the spec says the header's accessibility follows the visible text) and the badge from rendered
// pixels. The badge is hidden from accessibility by design, so only its pixels can be compared.
// C9 (P44, "Other accounts" expanding from its label and from AXPress) has no seam: manual or gate check, not covered here.

private let pcNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor private func pcRow(_ id: String, _ provider: ProviderID, _ label: String) -> ProfileDisplay {
    ProfileDisplay(profile: AccountProfile(id: id, providerID: provider, label: label,
                                           source: provider == "codex" ? .codexFile("/invented/" + id) : .claudeFile("/invented/" + id)),
                   snapshot: nil, health: .healthy, message: nil, fetchedAge: nil)
}
@MainActor private func pcModel(_ rows: [ProfileDisplay], codes: [String: String] = [:]) -> DropdownModel {
    let model = DropdownModel()
    model.rows = rows; model.now = pcNow; model.providerCodes = codes
    return model
}
@MainActor private func pcHost(_ model: DropdownModel) -> (NSHostingView<DropdownPanel>, NSWindow) {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: DropdownPanel(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 360, height: 560)
    host.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    host.layoutSubtreeIfNeeded()
    return (host, window)
}
// Retired by designer ruling: four P41 header tests read the accessibility tree, which has no children in this test process.
// C8 is covered by the pixel tests in PCSupplementTests.swift.
@MainActor private func pcPixelsOfPanel(_ model: DropdownModel) -> [UInt8] {
    let (host, window) = pcHost(model); defer { window.close() }
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.bitmapData.map { Array(UnsafeBufferPointer(start: $0, count: rep.bytesPerRow * rep.pixelsHigh)) } ?? []
}

@Suite(.serialized) @MainActor struct PCDropdownTests {
    // N: the dropdown model starts without overrides.
    @Test func modelStartsEmpty() {
        #expect(DropdownModel().providerCodes.isEmpty)
    }
    // I, C8 (P41): the Connect / Authorize action keeps naming the account label.
    @Test func connectActionKeepsTheLabel() {
        let model = pcModel([ProfileDisplay(profile: AccountProfile(id: "claude-default", providerID: "claude", label: "Default", source: .claudeFile("/invented")),
                                            snapshot: nil, health: .unauthenticated, message: nil, fetchedAge: nil)])
        #expect(model.actionTitles().contains("Connect / Authorize Default"))
    }
    // N, C7: the badge shows the override: the rendered panel differs from the default and is stable.
    @Test func accountBadgeShowsTheOverride() {
        let rows = [pcRow("claude-default", "claude", "Default")]
        let plain = pcPixelsOfPanel(pcModel(rows)), overridden = pcPixelsOfPanel(pcModel(rows, codes: ["claude": "ZQ"]))
        #expect(!plain.isEmpty && plain == pcPixelsOfPanel(pcModel(rows)), "rendering is deterministic")
        #expect(overridden != plain)
        #expect(overridden == pcPixelsOfPanel(pcModel(rows, codes: ["claude": " zq "])), "the effective code is the normalized one")
    }
    // I, C7: overrides for other providers, the default itself or an unusable value leave the card as it was.
    @Test func unrelatedOrUnusableOverridesChangeNothing() {
        let rows = [pcRow("claude-default", "claude", "Default")]
        let plain = pcPixelsOfPanel(pcModel(rows))
        for codes in [["codex": "ZQ"], ["claude": "CL"], ["claude": "???"], ["claude": ""], ["budget": "ZQ"]] {
            #expect(pcPixelsOfPanel(pcModel(rows, codes: codes)) == plain, "\(codes)")
        }
    }
    // N, C7: the budget card's badge shows the budget override.
    @Test func budgetBadgeShowsTheOverride() {
        let config = SharedBudgetConfig(enabled: true, amount: 5000, currency: "USD", members: ["claude"], resetDay: .day(1))
        let state = SharedBudgetState(config: config, members: [], total: 5000, usedPercent: 25, resetsAt: Date(timeIntervalSince1970: 1_802_000_000),
                                      freshnessDeadline: nil, warning: nil)
        func panel(_ codes: [String: String]) -> [UInt8] {
            let model = pcModel([], codes: codes); model.budget = state
            return pcPixelsOfPanel(model)
        }
        let plain = panel([:])
        #expect(!plain.isEmpty && panel(["budget": "ZQ"]) != plain)
        #expect(panel(["claude": "ZQ"]) == plain, "another provider's override does not touch the budget card")
        #expect(panel(["budget": "SB"]) == plain)
    }
}
