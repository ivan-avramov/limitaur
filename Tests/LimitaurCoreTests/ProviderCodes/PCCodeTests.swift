import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Specification: docs/proposals/provider-codes.md. Criteria C1 (normalizedProviderCode), C2 (providerGlyph overrides),
// C3 (validatedProviderCodes). Reserved defaults used below: claude CL, codex CX, cursor CU, budget SB.

private let pcEditable: [ProviderID] = ["claude", "codex", "cursor", "budget"]
private let pcDefaults: [String: String] = ["claude": "CL", "codex": "CX", "cursor": "CU", "budget": "SB"]

@Suite struct PCNormalizeTests {
    // N, C1: the listed examples.
    @Test(arguments: [(" cr ", "CR"), ("c", "C"), ("9z", "9Z")])
    func acceptsAndUppercases(_ raw: String, _ expected: String) {
        #expect(normalizedProviderCode(raw) == expected)
    }
    // N, C1: the listed rejects.
    @Test(arguments: ["", "ABC", "C?", "é", "Ⅻ"])
    func rejectsListedInputs(_ raw: String) {
        #expect(normalizedProviderCode(raw) == nil)
    }
    // N, C1: trimming covers whitespace and newlines at both ends; interior whitespace is not part of a code.
    @Test func trimsWhitespaceAndNewlines() {
        #expect(normalizedProviderCode("\n cr\t") == "CR")
        #expect(normalizedProviderCode("  7  ") == "7")
        #expect(normalizedProviderCode("   ") == nil)
        #expect(normalizedProviderCode("\n") == nil)
        #expect(normalizedProviderCode("C R") == nil)
        #expect(normalizedProviderCode("C\nR") == nil)
    }
    // N, C1: one or two characters; every ASCII letter and digit is allowed in either position.
    @Test func lengthBoundariesAndFullAlphabet() {
        for c in Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") {
            #expect(normalizedProviderCode(String(c)) == String(c))
            #expect(normalizedProviderCode(String(c).lowercased()) == String(c))
            #expect(normalizedProviderCode(String(c) + "0") == String(c) + "0")
        }
        #expect(normalizedProviderCode("00") == "00")
        #expect(normalizedProviderCode("A1B") == nil)
        #expect(normalizedProviderCode("123") == nil)
    }
    // N, C1: only ASCII counts, including inputs whose uppercase form would otherwise be ASCII letters (ß -> SS, ı -> I, ﬁ -> FI).
    @Test(arguments: ["ß", "ı", "ﬁ", "Ａ", "１", "C\u{0301}", "\u{200B}", "٣", "日本", "😀", "a-", "_", "."])
    func rejectsNonAsciiAndPunctuation(_ raw: String) {
        #expect(normalizedProviderCode(raw) == nil, "\(raw.unicodeScalars.map(\.value))")
    }
}

@Suite struct PCGlyphTests {
    // N, C2: a valid override is returned, normalized.
    @Test func validOverrideWins() {
        #expect(providerGlyph(for: "cursor", overrides: ["cursor": "CR"]) == "CR")
        #expect(providerGlyph(for: "cursor", overrides: ["cursor": " cr "]) == "CR")
        #expect(providerGlyph(for: "budget", overrides: ["budget": "7"]) == "7")
    }
    // N, C2: a missing or invalid override falls back to the default.
    @Test func missingOrInvalidFallsBack() {
        #expect(providerGlyph(for: "cursor", overrides: [:]) == "CU")
        #expect(providerGlyph(for: "cursor", overrides: ["claude": "ZZ"]) == "CU")
        for bad in ["", " ", "ABC", "C?", "é", "Ⅻ"] {
            #expect(providerGlyph(for: "cursor", overrides: ["cursor": bad]) == "CU", "\(bad)")
        }
    }
    // N, C2: the override map is keyed by the lowercased raw provider identifier.
    @Test func lookupUsesLowercasedProviderID() {
        #expect(providerGlyph(for: ProviderID("Cursor"), overrides: ["cursor": "CR"]) == "CR")
    }
    // N, C2: only the asked provider is affected.
    @Test func overridesAreForOneProvider() {
        let overrides = ["cursor": "CR"]
        #expect(providerGlyph(for: "claude", overrides: overrides) == "CL")
        #expect(providerGlyph(for: "codex", overrides: overrides) == "CX")
        #expect(providerGlyph(for: "budget", overrides: overrides) == "SB")
    }
    // I, C2: the one-argument function, the table and the distinguishability rule keep their meaning.
    @Test func defaultFunctionIsUnchanged() {
        for (key, code) in pcDefaults { #expect(providerGlyph(for: ProviderID(key)) == code) }
        #expect(providerGlyph(for: "gemini") == "GM")
        #expect(providerGlyph(for: "q") == "Q?")
        #expect(providerGlyph(for: "zzzz") == "ZZ")
        #expect(providerCodes["claude"] == "CL" && providerCodes["budget"] == "SB")
        #expect(providerName("budget") == "Shared budget" && providerName("cursor") == "Cursor")
        #expect(providerCodesAreDistinguishable("CL", "CU") && !providerCodesAreDistinguishable("CL", "GL"))
    }
    // N: the editable list is exactly the four, in this order (the look-alike order depends on it).
    @Test func editableList() {
        #expect(editableProviderCodes == pcEditable)
    }
}

@Suite struct PCValidationTests {
    // N, C3: unknown keys are dropped, valid ones kept and normalized.
    @Test func dropsUnknownKeysAndNormalizes() {
        #expect(validatedProviderCodes(["cursor": "cr"]) == ["cursor": "CR"])
        #expect(validatedProviderCodes(["gemini": "ZZ", "copilot": "ZZ"]) == [:])
        #expect(validatedProviderCodes(["gemini": "ZZ", "cursor": " 9z "]) == ["cursor": "9Z"])
        #expect(validatedProviderCodes([:]) == [:])
        #expect(validatedProviderCodes(["claude": "AA", "codex": "BB", "cursor": "DD", "budget": "EE"])
                == ["claude": "AA", "codex": "BB", "cursor": "DD", "budget": "EE"])
    }
    // N, C3: invalid values are dropped, whatever their key.
    @Test func dropsInvalidValues() {
        #expect(validatedProviderCodes(["cursor": "??", "codex": "", "claude": "ABC", "budget": "é"]) == [:])
        #expect(validatedProviderCodes(["cursor": "??", "codex": "zz"]) == ["codex": "ZZ"])
    }
    // N, C3: a value equal to the provider's own default is not an override.
    @Test func dropsValuesEqualToTheDefault() {
        #expect(validatedProviderCodes(["cursor": "CU", "claude": "cl", "codex": " cx ", "budget": "sb"]) == [:])
        #expect(validatedProviderCodes(["cursor": "cu", "codex": "ZZ"]) == ["codex": "ZZ"])
    }
    // N, C3: both sides of an exact duplicate are dropped, in either spelling and any pairing.
    @Test func dropsBothSidesOfADuplicate() {
        #expect(validatedProviderCodes(["cursor": "XY", "codex": "xy"]) == [:])
        #expect(validatedProviderCodes(["cursor": "XY", "codex": "xy", "budget": "QQ"]) == ["budget": "QQ"])
        #expect(validatedProviderCodes(["claude": "7", "codex": "7", "cursor": "7"]) == [:])
        for pair in [["claude", "budget"], ["budget", "claude"], ["codex", "cursor"], ["cursor", "claude"]] {
            #expect(validatedProviderCodes([pair[0]: "Q1", pair[1]: "q1"]) == [:], "\(pair)")
        }
    }
    // N, C3: an override equal to another provider's default code is dropped.
    @Test func dropsADuplicateOfAnotherDefault() {
        #expect(validatedProviderCodes(["cursor": "CL"]) == [:])
        #expect(validatedProviderCodes(["claude": "cx"]) == [:])
        #expect(validatedProviderCodes(["codex": "SB"]) == [:])
        #expect(validatedProviderCodes(["budget": "CU", "codex": "ZZ"]) == ["codex": "ZZ"])
    }
    // R, C3 traced failure: the tampered stored value loads as nothing.
    @Test func tamperedStoredValueLoadsEmpty() {
        #expect(validatedProviderCodes(["cursor": "CL", "codex": "??"]) == [:])
    }
    // N, C3: the result never depends on the order the entries arrive in.
    @Test func orderIndependent() {
        let entries: [(String, String)] = [("claude", "ZZ"), ("codex", "zz"), ("cursor", "CR"), ("budget", "??"), ("gemini", "GM")]
        let expected = validatedProviderCodes(Dictionary(uniqueKeysWithValues: entries))
        #expect(expected == ["cursor": "CR"])
        for shift in entries.indices {
            let rotated = Array(entries[shift...] + entries[..<shift])
            #expect(validatedProviderCodes(Dictionary(uniqueKeysWithValues: rotated)) == expected)
            #expect(validatedProviderCodes(Dictionary(uniqueKeysWithValues: rotated.reversed())) == expected)
        }
    }
    // I, C3: over many inputs, the result holds only editable keys with normalized, non-default values,
    // and no two kept overrides share a code.
    @Test func resultAlwaysSatisfiesTheInvariants() {
        let values = ["", "cr", "CR", "CL", "cx", "SB", "XY", "xy", "??", "9", " 9 ", "ABC", "CU", "zz"]
        var checked = 0
        for a in values { for b in values { for c in values { for d in values {
            let result = validatedProviderCodes(["claude": a, "codex": b, "cursor": c, "budget": d, "gemini": "GM"])
            checked += 1
            #expect(Set(result.keys).isSubset(of: Set(pcEditable.map(\.rawValue))))
            for (key, value) in result {
                #expect(normalizedProviderCode(value) == value && value != pcDefaults[key])
                #expect(result.filter { $0.key != key && $0.value == value }.isEmpty, "no two overrides share a code")
            }
        } } } }
        #expect(checked == values.count * values.count * values.count * values.count)
    }
}
