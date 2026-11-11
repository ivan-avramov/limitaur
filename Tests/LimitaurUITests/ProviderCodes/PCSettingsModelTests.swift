import Combine
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Criteria C4 (setProviderCode) and C5 (lookalike). Reserved defaults: claude CL, codex CX, cursor CU, budget SB.

/// Records every `onProviderCodes` call with the whole override map it carried.
@MainActor final class PCProbe {
    var calls: [[String: String]] = []
    var otherCallbacks = 0
    func model(codes: [String: String] = [:], editable: Bool = true) -> SettingsModel {
        SettingsModel(profiles: [rdClaudeDefault, rdCodexDefault, rdProfile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)],
                      indicatorCount: 3, nudgeEnabled: true, editable: editable,
                      onProfiles: { _ in self.otherCallbacks += 1 }, onIndicatorCount: { _ in self.otherCallbacks += 1 },
                      onNudge: { _ in self.otherCallbacks += 1 }, onConnect: { _ in self.otherCallbacks += 1 },
                      onAbout: { self.otherCallbacks += 1 }, providerCodes: codes, onProviderCodes: { self.calls.append($0) })
    }
}

@Suite @MainActor struct PCSettingsModelTests {
    // N: defaults: nothing is overridden, effective codes are the reserved ones, no callback at construction.
    @Test func startsWithTheReservedCodes() {
        let probe = PCProbe(), model = probe.model()
        #expect(model.providerCodes.isEmpty && probe.calls.isEmpty)
        #expect(["claude", "codex", "cursor", "budget"].map { model.code(for: ProviderID($0)) } == ["CL", "CX", "CU", "SB"])
        for provider in editableProviderCodes { #expect(model.lookalike(for: provider) == nil, "\(provider)") }
    }
    // N, C6: initial overrides pass through validatedProviderCodes and do not call back.
    @Test func initialOverridesAreValidated() {
        let probe = PCProbe()
        let good = probe.model(codes: ["cursor": "cr", "gemini": "ZZ"])
        #expect(good.providerCodes == ["cursor": "CR"] && good.code(for: "cursor") == "CR" && good.code(for: "claude") == "CL")
        #expect(probe.model(codes: ["cursor": "CL", "codex": "??"]).providerCodes.isEmpty)
        #expect(probe.model(codes: ["cursor": "XY", "codex": "xy"]).providerCodes.isEmpty)
        #expect(probe.model(codes: ["cursor": "CU"]).providerCodes.isEmpty)
        #expect(probe.calls.isEmpty && probe.otherCallbacks == 0)
    }
    // N, C4 and the success trace: a valid code is saved normalized, once, with the whole map; the property is published.
    @Test func savedCallsBackOnceAndPublishes() {
        let probe = PCProbe(), model = probe.model()
        var seen: [[String: String]] = []
        let token = model.$providerCodes.sink { seen.append($0) }; defer { token.cancel() }
        #expect(model.setProviderCode("cursor", "cr") == .saved("CR"))
        #expect(model.providerCodes == ["cursor": "CR"] && model.code(for: "cursor") == "CR")
        #expect(probe.calls == [["cursor": "CR"]])
        #expect(seen.last == ["cursor": "CR"] && seen.count == 2)
        #expect(model.setProviderCode("budget", " 7 ") == .saved("7"))
        #expect(probe.calls == [["cursor": "CR"], ["cursor": "CR", "budget": "7"]], "each call carries the whole map")
        #expect(probe.otherCallbacks == 0)
    }
    // N, C4: the same code again is unchanged, in any spelling, without a callback.
    @Test func repeatIsUnchanged() {
        let probe = PCProbe(), model = probe.model()
        model.setProviderCode("cursor", "CR")
        #expect(model.setProviderCode("cursor", "CR") == .unchanged)
        #expect(model.setProviderCode("cursor", " cr ") == .unchanged)
        #expect(probe.calls.count == 1 && model.providerCodes == ["cursor": "CR"])
    }
    // N, C4: an override is replaced by another valid code.
    @Test func replacingAnOverride() {
        let probe = PCProbe(), model = probe.model(codes: ["cursor": "CR"])
        #expect(model.setProviderCode("cursor", "QQ") == .saved("QQ"))
        #expect(model.providerCodes == ["cursor": "QQ"] && probe.calls == [["cursor": "QQ"]])
    }
    // N, C4: empty (after trimming) or the default code removes the override; with none it is unchanged.
    @Test func resetAndUnchangedWithoutOverride() {
        let probe = PCProbe(), model = probe.model(codes: ["cursor": "CR", "codex": "ZZ"])
        #expect(model.setProviderCode("cursor", "") == .reset)
        #expect(model.providerCodes == ["codex": "ZZ"] && model.code(for: "cursor") == "CU")
        #expect(probe.calls == [["codex": "ZZ"]])
        #expect(model.setProviderCode("cursor", "  \n") == .unchanged)
        #expect(model.setProviderCode("cursor", "cu") == .unchanged, "the default typed with no override")
        #expect(model.setProviderCode("codex", "cx") == .reset, "the default typed over an override")
        #expect(model.providerCodes.isEmpty && probe.calls == [["codex": "ZZ"], [:]])
        #expect(model.setProviderCode("codex", "") == .unchanged)
        #expect(probe.calls.count == 2)
    }
    // N, C4: a code that fails normalization is invalid, changes nothing and calls nothing.
    @Test func invalidCodes() {
        let probe = PCProbe(), model = probe.model(codes: ["cursor": "CR"])
        for bad in ["ABC", "C?", "é", "Ⅻ", "C R", "ß", "😀"] {
            #expect(model.setProviderCode("cursor", bad) == .invalid, "\(bad)")
            #expect(model.setProviderCode("claude", bad) == .invalid, "\(bad)")
        }
        #expect(model.providerCodes == ["cursor": "CR"] && probe.calls.isEmpty)
    }
    // N, C4: a provider without an editable code is invalid (even for an empty or good code); the model stays as it was.
    @Test func providerOutsideTheEditableListIsInvalid() {
        let probe = PCProbe(), model = probe.model()
        for provider: ProviderID in ["gemini", "copilot", "unknown"] {
            #expect(model.setProviderCode(provider, "ZZ") == .invalid, "\(provider)")
            #expect(model.setProviderCode(provider, "") == .invalid, "\(provider)")
        }
        #expect(model.providerCodes.isEmpty && probe.calls.isEmpty)
    }
    // R, C4: a duplicate of another provider's effective code, default or override, is refused with that provider.
    @Test func duplicatesAreRefused() {
        let probe = PCProbe(), model = probe.model()
        #expect(model.setProviderCode("cursor", "CL") == .duplicate("claude"))
        #expect(model.setProviderCode("cursor", "cx") == .duplicate("codex"))
        #expect(model.setProviderCode("claude", "SB") == .duplicate("budget"))
        #expect(model.setProviderCode("budget", " cu ") == .duplicate("cursor"))
        #expect(model.providerCodes.isEmpty && probe.calls.isEmpty)
        model.setProviderCode("codex", "ZZ")
        #expect(model.setProviderCode("claude", "zz") == .duplicate("codex"), "another's override")
        #expect(model.providerCodes == ["codex": "ZZ"] && probe.calls.count == 1)
    }
    // N, C4: once a provider moves off its default, that default code is free for the others, and a typed code never conflicts with itself.
    @Test func freedDefaultsAndSelf() {
        let probe = PCProbe(), model = probe.model()
        model.setProviderCode("codex", "ZZ")
        #expect(model.setProviderCode("cursor", "CX") == .saved("CX"))
        #expect(model.setProviderCode("cursor", "cx") == .unchanged)
        #expect(model.providerCodes == ["codex": "ZZ", "cursor": "CX"])
    }
    // N, C4: a read-only model never changes and never calls back, whatever the input; overrides it was given stay visible.
    @Test func readOnlyNeverChanges() {
        let probe = PCProbe(), model = probe.model(codes: ["cursor": "CR"], editable: false)
        #expect(!model.editable)
        for (provider, raw) in [("cursor", "QQ"), ("cursor", ""), ("cursor", "CR"), ("codex", "??"), ("claude", "CU"), ("gemini", "ZZ")] as [(ProviderID, String)] {
            #expect(model.setProviderCode(provider, raw) == .readOnly, "\(provider) \(raw)")
        }
        #expect(model.providerCodes == ["cursor": "CR"] && model.code(for: "cursor") == "CR" && probe.calls.isEmpty)
    }
    // N, C4: only .saved and .reset call back; every other case is silent (checked over a mixed sequence).
    @Test func callbacksOnlyForSavedAndReset() {
        let probe = PCProbe(), model = probe.model()
        let steps: [(ProviderID, String, ProviderCodeChange)] = [
            ("cursor", "CR", .saved("CR")), ("cursor", "CR", .unchanged), ("cursor", "CL", .duplicate("claude")), ("cursor", "???", .invalid),
            ("gemini", "AB", .invalid), ("claude", "", .unchanged), ("cursor", "", .reset), ("cursor", "", .unchanged)]
        var expectedCalls = 0
        for (provider, raw, expected) in steps {
            #expect(model.setProviderCode(provider, raw) == expected, "\(provider) \(raw)")
            if expected == .saved("CR") || expected == .reset { expectedCalls += 1 }
            #expect(probe.calls.count == expectedCalls, "\(provider) \(raw)")
        }
        #expect(probe.calls == [["cursor": "CR"], [:]])
    }
    // I: the result is discardable and the change type is Equatable with its payloads.
    @Test func changeValuesCompareByPayload() {
        #expect(ProviderCodeChange.saved("A") != .saved("B") && ProviderCodeChange.duplicate("claude") != .duplicate("codex"))
        #expect(ProviderCodeChange.reset != .unchanged)
    }

    // N, C5: setting Cursor to GL reports Claude (CL); CR reports none; the code is still saved.
    @Test func lookalikeReportsTheSimilarProvider() {
        let probe = PCProbe(), model = probe.model()
        #expect(model.setProviderCode("cursor", "GL") == .saved("GL"), "a look-alike is saved, not refused")
        #expect(model.lookalike(for: "cursor") == "claude")
        #expect(model.lookalike(for: "claude") == "cursor", "symmetric")
        #expect(model.lookalike(for: "codex") == nil && model.lookalike(for: "budget") == nil)
        #expect(probe.calls == [["cursor": "GL"]])
        #expect(model.setProviderCode("cursor", "CR") == .saved("CR"))
        for provider in editableProviderCodes { #expect(model.lookalike(for: provider) == nil, "\(provider)") }
    }
    // N, C5: the first match in the editable order is reported; clearing removes the report.
    @Test func lookalikeOrderAndClearing() {
        let probe = PCProbe(), model = probe.model()
        model.setProviderCode("cursor", "GL"); model.setProviderCode("budget", "OL")
        #expect(model.lookalike(for: "budget") == "claude", "claude comes first in the editable order")
        #expect(model.lookalike(for: "claude") == "cursor")
        #expect(model.lookalike(for: "cursor") == "claude")
        model.setProviderCode("cursor", "")
        #expect(model.lookalike(for: "budget") == "claude" && model.lookalike(for: "cursor") == nil)
        model.setProviderCode("claude", "QQ")
        #expect(model.lookalike(for: "budget") == nil && model.lookalike(for: "claude") == nil)
    }
    // N, C5: only codes of the same length can look alike.
    @Test func lookalikeNeedsTheSameLength() {
        let probe = PCProbe(), model = probe.model()
        model.setProviderCode("claude", "C"); model.setProviderCode("cursor", "CL")
        #expect(model.lookalike(for: "cursor") == nil && model.lookalike(for: "claude") == nil)
        model.setProviderCode("codex", "G")
        #expect(model.lookalike(for: "codex") == "claude" && model.lookalike(for: "claude") == "codex")
    }
}
