import AppKit
import Foundation
import Testing
@testable import LimitaurCore
@testable import Limitaur

@MainActor private func codesModel(_ codes: [String: String] = [:], editable: Bool = true,
                                   calls: @escaping ([String: String]) -> Void = { _ in }) -> SettingsModel {
    SettingsModel(profiles: [], indicatorCount: 3, nudgeEnabled: true, editable: editable,
                  onProfiles: { _ in }, onIndicatorCount: { _ in }, onNudge: { _ in }, onConnect: { _ in }, onAbout: {},
                  providerCodes: codes, onProviderCodes: calls)
}

@MainActor @Test func setProviderCodeReturnsEachCaseAndCallsBackOnlyOnSaveOrReset() {
    var calls: [[String: String]] = []
    let model = codesModel { calls.append($0) }
    #expect(model.setProviderCode("cursor", " cr ") == .saved("CR"))
    #expect(calls == [["cursor": "CR"]])
    #expect(model.setProviderCode("cursor", "CR") == .unchanged)
    #expect(model.setProviderCode("cursor", "CL") == .duplicate("claude"))
    #expect(model.setProviderCode("cursor", "C?") == .invalid)
    #expect(model.setProviderCode("gemini", "ZZ") == .invalid)
    #expect(model.code(for: "cursor") == "CR" && calls.count == 1)
    #expect(model.setProviderCode("cursor", "  ") == .reset)
    #expect(model.setProviderCode("cursor", "cu") == .unchanged)
    #expect(calls == [["cursor": "CR"], [:]])
    // Codex's default is in use by Cursor, so resetting Codex is refused.
    #expect(model.setProviderCode("codex", "Z1") == .saved("Z1"))
    #expect(model.setProviderCode("cursor", "CX") == .saved("CX"))
    #expect(model.setProviderCode("codex", "") == .duplicate("cursor"))
    #expect(model.code(for: "codex") == "Z1")

    let readOnly = codesModel(["cursor": "CR"], editable: false) { calls.append($0) }
    #expect(readOnly.setProviderCode("cursor", "XY") == .readOnly)
    #expect(readOnly.providerCodes == ["cursor": "CR"] && calls.count == 4)
}

@MainActor @Test func initialCodesAreValidatedAndLookalikesReported() {
    #expect(codesModel(["cursor": "CL", "codex": "??", "budget": "b1"]).providerCodes == ["budget": "B1"])
    let model = codesModel()
    #expect(model.lookalike(for: "cursor") == nil)
    model.setProviderCode("cursor", "GL")
    #expect(model.lookalike(for: "cursor") == "claude" && model.lookalike(for: "claude") == "cursor")
    model.setProviderCode("cursor", "CR")
    #expect(model.lookalike(for: "cursor") == nil)
}

@MainActor @Test func controllerLoadsPersistsAndAppliesCodes() {
    _ = NSApplication.shared
    let suite = "limitaur-codes-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["cursor": "cr", "codex": "CL", "gemini": "GG"], forKey: "providerCodes")
    let controller = AppController(countStore: MemoryIndicatorStore(), defaults: defaults, nudger: nil)
    #expect(controller.providerCodes == ["cursor": "CR"])
    #expect(controller.statusDrawingView.providerCodes == ["cursor": "CR"])
    #expect(controller.dropdownModel.providerCodes == ["cursor": "CR"])
    #expect(controller.settings.code(for: "cursor") == "CR")
    #expect(controller.settings.setProviderCode("budget", "bu") == .saved("BU"))
    #expect(defaults.dictionary(forKey: "providerCodes") as? [String: String] == ["cursor": "CR", "budget": "BU"])
    #expect(controller.statusDrawingView.providerCodes["budget"] == "BU" && controller.dropdownModel.providerCodes["budget"] == "BU")
    #expect(AppController(countStore: MemoryIndicatorStore(), defaults: defaults, nudger: nil).providerCodes == ["cursor": "CR", "budget": "BU"])

    let demoSuite = "limitaur-codes-demo-" + UUID().uuidString
    let demoDefaults = UserDefaults(suiteName: demoSuite)!
    defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
    demoDefaults.set(["cursor": "CR"], forKey: "providerCodes")
    let demo = AppController(demo: true, countStore: MemoryIndicatorStore(), defaults: demoDefaults, nudger: nil)
    #expect(demo.providerCodes.isEmpty)
    #expect(demo.settings.setProviderCode("cursor", "XY") == .readOnly)
    #expect(demoDefaults.dictionary(forKey: "providerCodes") as? [String: String] == ["cursor": "CR"])
}

@MainActor private func pixels(_ provider: ProviderID, codes: [String: String], unavailable: Bool = false) -> Data {
    let snapshot = UsageSnapshot(providerID: provider, accountID: "a", accountLabel: "A", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 metrics: [UsageMetric(id: "spend", label: "Monthly spend", usedPercent: 40)])
    let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: 1), height: 22))
    view.count = 1; view.providerCodes = codes
    if unavailable { view.unavailableProviders = [provider] }
    else { view.selected = [RankedMetric(snapshot: snapshot, metric: snapshot.metrics[0])] }
    view.appearance = NSAppearance(named: .darkAqua)
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])!
}

@MainActor @Test func ringViewDrawsTheOverride() {
    for unavailable in [false, true] {
        let overridden = pixels("cursor", codes: ["cursor": "MS"], unavailable: unavailable)
        #expect(overridden != pixels("cursor", codes: [:], unavailable: unavailable))
        // Mistral's reserved code is MS: the override renders exactly as the table's entry.
        #expect(overridden == pixels("mistral", codes: [:], unavailable: unavailable))
    }
}

@MainActor @Test func providerIdsAreCaseInsensitiveAndStoredLowercase() {
    let model = codesModel()
    #expect(model.setProviderCode("Cursor", "gl") == .saved("GL"))
    #expect(model.providerCodes == ["cursor": "GL"])
    #expect(model.code(for: "CURSOR") == "GL")
    #expect(model.lookalike(for: "Cursor") == "claude")
    #expect(model.lookalike(for: "CLAUDE") == "cursor")
    #expect(model.setProviderCode("CLAUDE", "GL") == .duplicate("cursor"))
}

@MainActor @Test func providerFontShrinksOnlyCodesThatDoNotFit() {
    #expect(RingView.providerFont("CL", width: 18).pointSize == 8)
    #expect(RingView.providerFont("C", width: 18).pointSize == 9.5)
    let wide = RingView.providerFont("WW", width: 10)
    #expect(wide.pointSize < 8 && ("WW" as NSString).size(withAttributes: [.font: wide]).width <= 10)
}
