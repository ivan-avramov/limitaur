import Testing
@testable import LimitaurCore

@Test func normalizedProviderCodeAcceptsOnlyOneOrTwoASCIILettersOrDigits() {
    #expect(normalizedProviderCode(" cr ") == "CR")
    #expect(normalizedProviderCode("c") == "C")
    #expect(normalizedProviderCode("9z") == "9Z")
    #expect(normalizedProviderCode("\ncu\t") == "CU")
    for bad in ["", "  ", "ABC", "C?", "é", "Ⅻ", "ß", "ﬁ", "C U", "１"] { #expect(normalizedProviderCode(bad) == nil, "\(bad)") }
}

@Test func overrideGlyphFallsBackToTheDefault() {
    #expect(providerGlyph(for: "cursor", overrides: ["cursor": "cr"]) == "CR")
    #expect(providerGlyph(for: "cursor", overrides: ["cursor": "??"]) == "CU")
    #expect(providerGlyph(for: "cursor", overrides: [:]) == "CU")
    #expect(providerGlyph(for: "Cursor", overrides: ["cursor": "CR"]) == "CR")
    #expect(providerGlyph(for: "cursor") == "CU")
}

@Test func validatedProviderCodesDropsUnknownInvalidDefaultAndDuplicates() {
    #expect(validatedProviderCodes(["cursor": "cr", "gemini": "ZZ", "codex": "??", "claude": "CL"]) == ["cursor": "CR"])
    #expect(validatedProviderCodes(["cursor": "CL", "codex": "??"]) == [:])
    #expect(validatedProviderCodes(["cursor": "ZZ", "budget": "zz"]) == [:])
    #expect(validatedProviderCodes(["claude": "CX", "codex": "CL"]) == ["claude": "CX", "codex": "CL"])
    // Dropping a duplicate pair restores Codex's CX, which then collides with Cursor's override.
    #expect(validatedProviderCodes(["codex": "Z1", "claude": "Z1", "cursor": "CX"]) == [:])
}

@Test func validatedProviderCodesMatchesKeysCaseInsensitively() {
    #expect(validatedProviderCodes(["Cursor": "cr"]) == ["cursor": "CR"])
    #expect(validatedProviderCodes(["cursor": "CR", "CURSOR": "CZ", "codex": "Z1"]) == ["codex": "Z1"])
}
