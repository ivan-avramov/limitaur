import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Revision 3, R3.1 (case at every entry point), Core part. R2.3 tests in PCRevision2Tests.swift already cover mixed-case keys.

@Suite struct PCRevision3CoreTests {
    // R, R3.1: two raw keys that differ only in case drop that provider's override, whatever their values.
    @Test func keysDifferingOnlyInCaseDropTheOverride() {
        #expect(validatedProviderCodes(["Cursor": "CR", "cursor": "ZZ"]) == [:])
        #expect(validatedProviderCodes(["Cursor": "CR", "cursor": "CR"]) == [:], "even when the values agree")
        #expect(validatedProviderCodes(["CURSOR": "AA", "Cursor": "BB", "cursor": "CC"]) == [:])
    }
    // R, R3.1: the drop is for that provider only; other providers' overrides survive, in any case.
    @Test func theDropTouchesOnlyThatProvider() {
        #expect(validatedProviderCodes(["Cursor": "CR", "cursor": "ZZ", "codex": "QQ"]) == ["codex": "QQ"])
        #expect(validatedProviderCodes(["Cursor": "CR", "cursor": "ZZ", "CODEX": "qq", "Budget": "7"]) == ["codex": "QQ", "budget": "7"])
    }
    // R, R3.1: a dropped provider returns to its default, which can then clash: the result is still stable.
    @Test func dropRestoresTheDefaultAndStaysStable() {
        // claude's two keys drop; claude reads CL again, which clashes with cursor's CL override, so that goes too.
        let result = validatedProviderCodes(["Claude": "AA", "claude": "BB", "cursor": "CL"])
        #expect(result == [:])
        #expect(validatedProviderCodes(result) == result)
    }
    // N, R3.1: overrides are always stored under the lowercase id.
    @Test func resultKeysAreLowercase() {
        let result = validatedProviderCodes(["CLAUDE": "zz", "Codex": "yy", "cursor": "xx", "BUDGET": "7"])
        #expect(result == ["claude": "ZZ", "codex": "YY", "cursor": "XX", "budget": "7"])
        #expect(result.keys.allSatisfy { $0 == $0.lowercased() })
    }
    // I, R3.1: a single mixed-case key with a default or unusable value is still dropped.
    @Test func mixedCaseKeysStillFollowTheValueRules() {
        #expect(validatedProviderCodes(["Cursor": "cu"]) == [:])
        #expect(validatedProviderCodes(["Cursor": "???"]) == [:])
        #expect(validatedProviderCodes(["Gemini": "ZZ", "GEMINI": "YY"]) == [:])
    }
}
