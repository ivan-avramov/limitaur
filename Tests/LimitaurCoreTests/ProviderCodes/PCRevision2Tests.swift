import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Revision 2 of docs/proposals/provider-codes.md: R2.1 (stable validation) and R2.3 (case-insensitive provider ids), Core part.

private let pcrEditable = ["claude", "codex", "cursor", "budget"]
private let pcrDefaults = ["claude": "CL", "codex": "CX", "cursor": "CU", "budget": "SB"]

@Suite struct PCRevision2CoreTests {
    // R, R2.1: the spec's example: dropping both AA overrides gives Claude CL back, which then duplicates Cursor's override.
    @Test func cascadingDuplicateLoadsEmpty() {
        #expect(validatedProviderCodes(["claude": "AA", "codex": "AA", "cursor": "CL"]) == [:])
        #expect(validatedProviderCodes(["claude": "aa", "codex": " AA ", "cursor": "cl"]) == [:])
    }
    // R, R2.1: a longer chain: AA/AA drops, CL then clashes with Claude's restored default, CU then clashes with Budget's override.
    @Test func longerChainSettles() {
        #expect(validatedProviderCodes(["claude": "AA", "codex": "AA", "cursor": "CL", "budget": "CU"]) == [:])
        #expect(validatedProviderCodes(["claude": "AA", "codex": "AA", "cursor": "CL", "budget": "CU", "gemini": "ZZ"]) == [:])
    }
    // R, R2.1: an override unrelated to the chain survives it.
    @Test func unrelatedOverrideSurvivesTheChain() {
        // claude/budget AA clash, Claude's restored CL then clashes with cursor; codex ZZ takes no part.
        #expect(validatedProviderCodes(["claude": "AA", "codex": "ZZ", "cursor": "CL", "budget": "AA"]) == ["codex": "ZZ"])
    }
    // I, R2.1: swapped codes have no duplicate and are kept.
    @Test func swappedCodesAreKept() {
        #expect(validatedProviderCodes(["claude": "CU", "cursor": "CL"]) == ["claude": "CU", "cursor": "CL"])
        #expect(validatedProviderCodes(["claude": "cu", "cursor": "cl"]) == ["claude": "CU", "cursor": "CL"])
    }
    // N, R2.1: the result is a fixed point, and no two editable providers share an effective code, over a broad sweep.
    @Test func resultIsAStableFixedPoint() {
        let values = ["", "cr", "CL", "CX", "CU", "SB", "XY", "xy", "??", "9", "AA", "aa"]
        var checked = 0
        for a in values { for b in values { for c in values { for d in values {
            let input = ["claude": a, "codex": b, "cursor": c, "budget": d]
            let result = validatedProviderCodes(input)
            checked += 1
            #expect(validatedProviderCodes(result) == result, "\(input)")
            let effective = pcrEditable.map { result[$0] ?? pcrDefaults[$0]! }
            #expect(Set(effective).count == effective.count, "\(input) -> \(result)")
        } } } }
        #expect(checked == values.count * values.count * values.count * values.count)
    }
    // N, R2.1: the stable result does not depend on the order entries arrive in, for the cascading input.
    @Test func cascadeIsOrderIndependent() {
        let entries: [(String, String)] = [("claude", "AA"), ("codex", "AA"), ("cursor", "CL"), ("budget", "CU")]
        for shift in entries.indices {
            let rotated = Array(entries[shift...] + entries[..<shift])
            #expect(validatedProviderCodes(Dictionary(uniqueKeysWithValues: rotated)) == [:])
            #expect(validatedProviderCodes(Dictionary(uniqueKeysWithValues: rotated.reversed())) == [:])
        }
    }
    // N, R2.3: override keys and provider ids are matched case-insensitively in the glyph lookup.
    @Test func glyphLookupIgnoresIdCase() {
        #expect(providerGlyph(for: "CURSOR", overrides: ["cursor": "CR"]) == "CR")
        #expect(providerGlyph(for: "Cursor", overrides: ["cursor": "CR"]) == "CR")
        #expect(providerGlyph(for: "CuRsOr", overrides: [:]) == "CU")
    }
    // N, R2.3: validation accepts a mixed-case key for an editable provider and keeps it under the lowercase id.
    @Test func validationAcceptsMixedCaseKeys() {
        #expect(validatedProviderCodes(["Cursor": "cr"]) == ["cursor": "CR"])
        #expect(validatedProviderCodes(["CLAUDE": "zz", "Codex": "yy"]) == ["claude": "ZZ", "codex": "YY"])
        #expect(validatedProviderCodes(["Gemini": "ZZ"]) == [:])
    }
    // N, R2.3: a mixed-case key counts for duplicates and for the default comparison.
    @Test func mixedCaseKeysTakePartInDuplicateRemoval() {
        #expect(validatedProviderCodes(["Cursor": "XY", "codex": "xy"]) == [:])
        #expect(validatedProviderCodes(["Cursor": "CU"]) == [:])
        #expect(validatedProviderCodes(["Cursor": "CL"]) == [:])
    }
}
