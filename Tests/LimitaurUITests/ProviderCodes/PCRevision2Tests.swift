import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Revision 2 of docs/proposals/provider-codes.md: R2.1 (stable validation), R2.2 (reset checks for duplicates),
// R2.3 (case-insensitive provider ids), UI-target part. Uses PCProbe from PCSettingsModelTests.swift.

private func pcrSuite() -> (UserDefaults, () -> Void) {
    let name = "limitaur-synthetic-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}

@Suite @MainActor struct PCRevision2SettingsTests {
    // R, R2.1: the settings model loads the cascading input as no overrides, with no callback.
    @Test func cascadingInitialOverridesLoadEmpty() {
        let probe = PCProbe()
        #expect(probe.model(codes: ["claude": "AA", "codex": "AA", "cursor": "CL"]).providerCodes.isEmpty)
        #expect(probe.model(codes: ["claude": "AA", "codex": "AA", "cursor": "CL", "budget": "CU"]).providerCodes.isEmpty)
        #expect(probe.model(codes: ["claude": "CU", "cursor": "CL"]).providerCodes == ["claude": "CU", "cursor": "CL"])
        #expect(probe.calls.isEmpty)
    }
    // R, R2.2: the spec's example: clearing Claude would restore CL, which Cursor holds.
    @Test func resetIsRefusedWhenTheDefaultIsTaken() {
        let probe = PCProbe(), model = probe.model(codes: ["claude": "AB", "cursor": "CL"])
        #expect(model.setProviderCode("claude", "") == .duplicate("cursor"))
        #expect(model.setProviderCode("claude", "  \n") == .duplicate("cursor"))
        #expect(model.providerCodes == ["claude": "AB", "cursor": "CL"] && model.code(for: "claude") == "AB")
        #expect(probe.calls.isEmpty, "nothing changes and nothing is called back")
    }
    // R, R2.2: typing the provider's own default is refused the same way.
    @Test func typingTheDefaultIsRefusedWhenTheDefaultIsTaken() {
        let probe = PCProbe(), model = probe.model(codes: ["claude": "AB", "cursor": "CL"])
        #expect(model.setProviderCode("claude", "CL") == .duplicate("cursor"))
        #expect(model.setProviderCode("claude", " cl ") == .duplicate("cursor"))
        #expect(model.providerCodes == ["claude": "AB", "cursor": "CL"] && probe.calls.isEmpty)
    }
    // I, R2.2: when the default is free, reset and default-typing still work and call back once.
    @Test func resetStillWorksWhenTheDefaultIsFree() {
        let probe = PCProbe(), model = probe.model(codes: ["claude": "AB", "cursor": "CR"])
        #expect(model.setProviderCode("claude", "") == .reset)
        #expect(model.providerCodes == ["cursor": "CR"] && probe.calls == [["cursor": "CR"]])
        model.setProviderCode("claude", "AB")
        #expect(model.setProviderCode("claude", "cl") == .reset)
        #expect(probe.calls.count == 3)
    }
    // N, R2.2: once the other provider moves away, the reset goes through.
    @Test func resetSucceedsAfterTheHolderMovesAway() {
        let probe = PCProbe(), model = probe.model(codes: ["claude": "AB", "cursor": "CL"])
        #expect(model.setProviderCode("claude", "") == .duplicate("cursor"))
        #expect(model.setProviderCode("cursor", "") == .reset, "cursor's own default CU is free")
        #expect(model.setProviderCode("claude", "") == .reset)
        #expect(model.providerCodes.isEmpty && probe.calls == [["claude": "AB"], [:]])
    }
    // N, R2.2: reached through sequence: a default another provider took while this one was away is not reclaimable.
    @Test func defaultTakenWhileAwayIsNotReclaimable() {
        let probe = PCProbe(), model = probe.model()
        model.setProviderCode("codex", "ZZ")
        #expect(model.setProviderCode("cursor", "CX") == .saved("CX"))
        #expect(model.setProviderCode("codex", "") == .duplicate("cursor"))
        #expect(model.setProviderCode("codex", "cx") == .duplicate("cursor"))
        #expect(model.providerCodes == ["codex": "ZZ", "cursor": "CX"] && probe.calls.count == 2)
    }
    // N, R2.2: whatever the sequence, effective codes stay distinct; checked over a scripted run.
    @Test func effectiveCodesStayDistinct() {
        let probe = PCProbe(), model = probe.model()
        let providers: [ProviderID] = ["claude", "codex", "cursor", "budget"]
        let inputs = ["", "AB", "CL", "CX", "CU", "SB", "ab", "zz", "cl"]
        var step = 0
        for round in 0..<3 { for provider in providers { for input in inputs {
            step += 1
            model.setProviderCode(providers[(step + round) % 4], input)
            _ = provider
            let effective = providers.map { model.code(for: $0) }
            #expect(Set(effective).count == 4, "step \(step): \(effective)")
        } } }
        for call in probe.calls { #expect(validatedProviderCodes(call) == call, "every reported map is a fixed point") }
    }
    // N, R2.3: setProviderCode and code(for:) accept any case of the provider id and key the override by the lowercase id.
    @Test func setAndReadIgnoreIdCase() {
        let probe = PCProbe(), model = probe.model()
        #expect(model.setProviderCode("Cursor", "cr") == .saved("CR"))
        #expect(model.providerCodes == ["cursor": "CR"] && probe.calls == [["cursor": "CR"]])
        #expect(model.code(for: "CURSOR") == "CR" && model.code(for: "cursor") == "CR" && model.code(for: "Claude") == "CL")
        #expect(model.setProviderCode("CURSOR", "cr") == .unchanged)
        #expect(model.setProviderCode("cUrSoR", "") == .reset)
        #expect(model.providerCodes.isEmpty && model.code(for: "Cursor") == "CU")
    }
    // N, R2.3: refusals work for mixed-case ids, and the duplicate names the other provider.
    @Test func refusalsIgnoreIdCase() {
        let probe = PCProbe(), model = probe.model()
        #expect(model.setProviderCode("CURSOR", "CL") == .duplicate("claude"))
        #expect(model.setProviderCode("Cursor", "???") == .invalid)
        #expect(model.setProviderCode("Gemini", "ZZ") == .invalid, "still outside the editable list")
        #expect(model.providerCodes.isEmpty && probe.calls.isEmpty)
        let readOnly = PCProbe().model(editable: false)
        #expect(readOnly.setProviderCode("Cursor", "QQ") == .readOnly)
    }
    // N, R2.3: look-alike lookups ignore the case of the id.
    @Test func lookalikeIgnoresIdCase() {
        let probe = PCProbe(), model = probe.model()
        model.setProviderCode("cursor", "GL")
        #expect(model.lookalike(for: "CURSOR") == "claude" && model.lookalike(for: "Claude") == "cursor")
    }
    // N, R2.3: init overrides with mixed-case keys are honoured.
    @Test func initialOverridesIgnoreKeyCase() {
        let model = PCProbe().model(codes: ["Cursor": "cr"])
        #expect(model.providerCodes == ["cursor": "CR"] && model.code(for: "cursor") == "CR")
    }
    // N, R2.3: the status view reads overrides for a mixed-case provider id.
    @Test func ringViewIgnoresIdCase() {
        _ = NSApplication.shared
        func slot(_ provider: ProviderID, _ codes: [String: String]) -> [SIMD4<Double>] {
            let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: 1), height: 22))
            view.count = 1; view.unavailableProviders = [provider]; view.providerCodes = codes
            view.appearance = NSAppearance(named: .aqua)
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            return (0..<rep.pixelsWide).flatMap { x in (0..<rep.pixelsHigh).map { y in
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                return SIMD4(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
            } }
        }
        let plain = slot("Cursor", [:]), overridden = slot("Cursor", ["cursor": "RP"])
        #expect(overridden != plain)
        #expect(overridden == slot("cursor", ["cursor": "RP"]) && overridden == slot("replit", [:]))
    }
}

@Suite(.serialized) @MainActor struct PCRevision2ControllerTests {
    // R, R2.1: the cascading stored value loads as no overrides, in the controller and in Settings.
    @Test func cascadingStoredValueLoadsEmpty() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcrSuite(); defer { cleanup() }
        defaults.set(["claude": "AA", "codex": "AA", "cursor": "CL"], forKey: "providerCodes")
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(controller.providerCodes.isEmpty && controller.settings.providerCodes.isEmpty)
        #expect(controller.settings.code(for: "claude") == "CL" && controller.settings.code(for: "cursor") == "CU")
    }
    // R, R2.2: a refused reset writes nothing and leaves every view as it was.
    @Test func refusedResetChangesNothing() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcrSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        controller.settings.setProviderCode("claude", "AB"); controller.settings.setProviderCode("cursor", "CL")
        let stored = defaults.dictionary(forKey: "providerCodes") as? [String: String]
        #expect(stored == ["claude": "AB", "cursor": "CL"])
        #expect(controller.settings.setProviderCode("claude", "") == .duplicate("cursor"))
        #expect(defaults.dictionary(forKey: "providerCodes") as? [String: String] == stored)
        #expect(controller.providerCodes == stored && controller.statusDrawingView.providerCodes == stored
                && controller.dropdownModel.providerCodes == stored)
    }
    // N, R2.3: a change made with a mixed-case id is stored under the lowercase key and applied everywhere.
    @Test func mixedCaseChangeIsStoredLowercase() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcrSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(controller.settings.setProviderCode("Cursor", "cr") == .saved("CR"))
        #expect(defaults.dictionary(forKey: "providerCodes") as? [String: String] == ["cursor": "CR"])
        #expect(controller.statusDrawingView.providerCodes == ["cursor": "CR"] && controller.dropdownModel.providerCodes == ["cursor": "CR"])
    }
}
