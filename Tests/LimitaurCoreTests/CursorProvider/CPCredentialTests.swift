import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline cannot load a Cursor credential),
// I = preserves an invariant, N = exercises new behaviour.

private func cpLoad(_ outcome: KeychainReadOutcome, interactive: Bool = false,
                    claude: CPKeychain = CPKeychain(cpNotFound), files: CPFiles = CPFiles())
    -> (result: Result<Credential, CredentialFailure>, viaKeychain: Bool, suspended: Bool, busy: Bool, cursor: CPKeychain) {
    let cursor = CPKeychain(outcome)
    let store = CredentialStore(files: files, keychain: claude, cursorKeychain: cursor)
    let loaded = store.loadDetailed(.cursorDefaultDiscovery, now: cpNow, interactive: interactive)
    return (loaded.result, loaded.viaKeychain, loaded.suspended, loaded.busy, cursor)
}
private func cpFailure(_ result: Result<Credential, CredentialFailure>) -> CredentialFailure? {
    if case .failure(let error) = result { return error }
    return nil
}

@Suite struct CPCredentialTests {
    // R, C2/I2.1-4: a found JWT with a future exp yields the specified credential.
    @Test func futureExpJWTYieldsCredential() throws {
        let token = cpJWT(exp: 1_800_003_600)
        let loaded = cpLoad(cpFound(token))
        let credential = try loaded.result.get()
        #expect(credential.accessToken == token)
        #expect(credential.selectedAccountID == nil)
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(loaded.viaKeychain && !loaded.suspended && !loaded.busy)
    }

    // N, C2: a non-JWT token succeeds without expiry.
    @Test(arguments: ["opaque-token", "a.b", "a.b.c.d", "x..y", "!.!.!"])
    func nonJWTTokenHasNoExpiry(_ token: String) throws {
        let credential = try cpLoad(cpFound(token)).result.get()
        #expect(credential.accessToken == token)
        #expect(credential.expiresAt == nil)
    }

    // N, I2.3: only exactly three parts are inspected, so a four-part token with a past exp is not expired.
    @Test func fourPartTokenIsNotInspected() throws {
        let past = cpJWT(exp: 1_000_000_000) + ".extra"
        #expect(try cpLoad(cpFound(past)).result.get().expiresAt == nil)
        let two = cpB64URL(Data("{}".utf8)) + "." + cpB64URL(Data("{\"exp\":1000000000}".utf8))
        #expect(try cpLoad(cpFound(two)).result.get().expiresAt == nil)
    }

    // N, I2.3: exp must be a non-boolean integral number in 0...8_640_000_000_000; anything else means no expiry (still success).
    @Test(arguments: [
        ("{\"exp\":1800003600}", 1_800_003_600.0 as Double?), ("{\"exp\":1800003600.0}", 1_800_003_600),
        ("{\"exp\":8640000000000}", 8_640_000_000_000), ("{\"exp\":8640000000001}", nil),
        ("{\"exp\":1800003600.5}", nil), ("{\"exp\":true}", nil), ("{\"exp\":\"1800003600\"}", nil),
        ("{\"exp\":-1}", nil), ("{\"exp\":null}", nil), ("{}", nil), ("[1800003600]", nil), ("\"text\"", nil), ("not json", nil)
    ])
    func expiryDerivation(_ payload: String, _ expected: Double?) throws {
        let credential = try cpLoad(cpFound(cpJWT(payload: payload))).result.get()
        #expect(credential.expiresAt == expected.map { Date(timeIntervalSince1970: $0) })
    }

    // N, I2.3: padding is optional; an undecodable middle part means no expiry.
    @Test func paddingIsOptionalAndGarbageMiddleIsIgnored() throws {
        for padded in [false, true] {
            let token = cpJWT(payload: "{\"exp\":1800003600,\"p\":\"xx\"}", padded: padded)
            #expect(try cpLoad(cpFound(token)).result.get().expiresAt == Date(timeIntervalSince1970: 1_800_003_600))
        }
        #expect(try cpLoad(cpFound("aaa.@@@@.ccc")).result.get().expiresAt == nil)
    }

    // N, I2.3 boundary: expiresAt <= now is expired; now + 1 s is not.
    @Test(arguments: [1_800_000_000, 1_799_999_999, 0])
    func expiredAtOrBeforeNow(_ exp: Int) {
        let loaded = cpLoad(cpFound(cpJWT(exp: exp)))
        #expect(cpFailure(loaded.result) == .expired)
        #expect(loaded.viaKeychain)
    }
    @Test func oneSecondBeforeExpiryIsAccepted() throws {
        #expect(try cpLoad(cpFound(cpJWT(exp: 1_800_000_001))).result.get().expiresAt == Date(timeIntervalSince1970: 1_800_000_001))
    }

    // N, C2: not-found throws missing with no file fallback; denied throws keychainDenied.
    @Test func notFoundIsMissingWithoutFileFallback() {
        let files = CPFiles()
        let loaded = cpLoad(cpNotFound, files: files)
        #expect(cpFailure(loaded.result) == .missing)
        #expect(!loaded.viaKeychain)
        #expect(files.count() == 0)
    }
    @Test func deniedIsKeychainDeniedWithoutFileFallback() {
        let files = CPFiles()
        let loaded = cpLoad(cpDenied(), files: files)
        #expect(cpFailure(loaded.result) == .keychainDenied)
        #expect(!loaded.viaKeychain && !loaded.suspended && !loaded.busy)
        #expect(files.count() == 0)
    }
    // N, I2.1: suspended, busy and suspendedNow follow the existing denied path.
    @Test func deniedFlagsFollowTheExistingPath() {
        let suspended = cpLoad(cpDenied(.suspended)), busy = cpLoad(cpDenied(.busy)), now = cpLoad(cpDenied(.timeout, suspendedNow: true))
        #expect(suspended.suspended && !suspended.busy && cpFailure(suspended.result) == .keychainDenied)
        #expect(busy.busy && !busy.suspended && cpFailure(busy.result) == .keychainDenied)
        #expect(now.suspended && !now.busy)
    }

    // N, I2.2/C2: empty, out-of-range bytes and over-long tokens are malformed; viaKeychain stays true.
    @Test(arguments: [[], [0x61, 0x20, 0x62], [0x20], [0x61, 0x7F], [0x61, 0x00], [0x61, 0x0A], [0x61, 0x0A, 0x62],
                      [0x61, 0x80], [0xC3, 0xA9], [0x61, 0x09]] as [[UInt8]])
    func invalidBytesAreMalformed(_ bytes: [UInt8]) {
        let loaded = cpLoad(cpFound(bytes: bytes))
        #expect(cpFailure(loaded.result) == .malformed)
        #expect(loaded.viaKeychain)
    }
    // N, I2.2 boundaries: 1 and 8192 bytes pass, 8193 fails; 0x21 and 0x7E are the inclusive limits.
    @Test func lengthAndByteBoundaries() throws {
        #expect(try cpLoad(cpFound("a")).result.get().accessToken == "a")
        #expect(try cpLoad(cpFound(bytes: [0x21, 0x7E])).result.get().accessToken == "!~")
        let longest = String(repeating: "a", count: 8192)
        #expect(try cpLoad(cpFound(longest)).result.get().accessToken == longest)
        #expect(cpFailure(cpLoad(cpFound(longest + "a")).result) == .malformed)
    }
    // N, I2.2: the loader does not strip a trailing newline itself (the reader's classify already did).
    @Test func trailingNewlineIsNotStrippedByTheLoader() {
        #expect(cpFailure(cpLoad(cpFound("token\n")).result) == .malformed)
    }

    // N, I2.1: the interactive flag reaches the Cursor keychain unchanged.
    @Test(arguments: [false, true]) func interactiveFlagIsPassedThrough(_ interactive: Bool) {
        let loaded = cpLoad(cpFound("opaque"), interactive: interactive)
        #expect(loaded.cursor.interactions() == [interactive])
    }
    // I, C2: the Claude keychain is not read for Cursor, nor the Cursor keychain for Claude or file sources.
    @Test func keychainsAreNeverCrossed() throws {
        let claude = CPKeychain(cpFound("claude-never"))
        let files = CPFiles()
        let loaded = cpLoad(cpFound("opaque"), claude: claude, files: files)
        _ = try loaded.result.get()
        #expect(claude.count() == 0 && files.count() == 0 && loaded.cursor.count() == 1)

        let cursor = CPKeychain(cpFound("cursor-never"))
        let claudeData = cpClaudeData(token: "claude-token", expiresAt: cpNow.addingTimeInterval(600))
        let store = CredentialStore(files: CPFiles(), keychain: CPKeychain(KeychainReadOutcome(result: .found(claudeData), reason: .found)),
                                    cursorKeychain: cursor)
        #expect(try store.load(.claudeDefaultDiscovery, now: cpNow).accessToken == "claude-token")
        #expect(cpFailure(store.loadDetailed(.claudeFile("/cp/none"), now: cpNow).result) == .missing)
        #expect(cpFailure(store.loadDetailed(.codexFile("/cp/none"), now: cpNow).result) == .missing)
        let fallback = CredentialStore(files: CPFiles(), keychain: CPKeychain(cpNotFound), cursorKeychain: cursor)
        #expect(cpFailure(fallback.loadDetailed(.claudeDefaultDiscovery, now: cpNow).result) == .missing)
        #expect(cursor.count() == 0)
    }
    // I, I2: the two-argument initialiser still works and defaults the Cursor reader to the cursor-agent item.
    @Test func defaultCursorReaderTargetsTheCursorAgentItem() {
        let store = CredentialStore(files: CPFiles(), keychain: CPKeychain(cpNotFound))
        #expect(store.cursorKeychain is SecurityToolKeychainReader)
        let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: store.cursorKeychain).children.compactMap { child in
            (child.value as? String).flatMap { value in child.label.map { ($0, value) } }
        })
        #expect(fields["service"] == "cursor-access-token" && fields["account"] == "cursor-user")
        #expect(CredentialStore().cursorKeychain is SecurityToolKeychainReader)
    }

    // N, I1: stable ID, equality and persistence round trip; the encoding carries no path.
    @Test func sourceIdentityAndPersistence() throws {
        #expect(CredentialSource.cursorDefaultDiscovery.stableID == "cursor:default")
        #expect(CredentialSource.cursorDefaultDiscovery != .claudeDefaultDiscovery)
        let profiles = [AccountProfile(id: "a", providerID: "codex", label: "A", source: .codexFile("/x")),
                        AccountProfile(id: "b", providerID: "claude", label: "B", source: .claudeDefaultDiscovery),
                        AccountProfile(id: "c", providerID: "cursor", label: "C", source: .cursorDefaultDiscovery, enabled: false)]
        let decoded = try JSONDecoder().decode([AccountProfile].self, from: JSONEncoder().encode(profiles))
        #expect(decoded == profiles)
        #expect(normalizedProfiles(decoded) == profiles)
    }

    // I, C2/S8: neither the credential nor any request form exposes the token or its parts in text or reflection.
    @Test func descriptionsAndMirrorsNeverContainTheToken() {
        let token = cpJWT(exp: 1_800_003_600, salt: "secret-marker-payload")
        let parts = token.split(separator: ".").map(String.init) + [token]
        let credential = Credential(accessToken: token, selectedAccountID: nil, expiresAt: cpNow)
        let requests = [HTTPRequest(providerID: "cursor", bearer: token, accountID: nil),
                        HTTPRequest(providerID: "cursor", bearer: token, accountID: nil, cursorOperation: .currentBillingCycle),
                        HTTPRequest(providerID: "cursor", bearer: token, accountID: nil, cursorOperation: .dailySpend(startMs: "1", endMs: "2"))]
        var texts = [String(describing: credential), String(reflecting: credential), "\(credential)", String(describing: Mirror(reflecting: credential).children)]
        var dumped = ""; dump(credential, to: &dumped); texts.append(dumped)
        for request in requests {
            var dump = ""; Swift.dump(request, to: &dump)
            texts += [String(describing: request), String(reflecting: request), "\(request)", String(describing: Mirror(reflecting: request).children), dump]
        }
        for text in texts { for part in parts { #expect(!text.contains(part)) } }
        for text in texts { #expect(!text.localizedCaseInsensitiveContains("bearer " + token)) }
    }
}
