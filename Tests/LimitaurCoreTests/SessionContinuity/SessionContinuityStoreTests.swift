import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityStoreTests {
    // Exercises new behaviour A8: type inspection only, never invoke the default reader.
    @Test func defaultReaderIsSecurityToolReaderWithoutReadingIt() {
        #expect(CredentialStore().keychain is SecurityToolKeychainReader)
    }

    // Preserves invariant A2/A8: found data has provenance even if parsing fails/expired.
    // "viaKeychain ... only for a Keychain .found" is read as acquisition provenance,
    // independent of parser success; Part C explicitly requires expired + viaKeychain.
    @Test(arguments: [0, 1, 2])
    func foundProvenanceSurvivesParsingAndExpiry(_ variant: Int) {
        let now = SCClock().wallNow(), files = SCFiles()
        let data = variant == 0 ? scClaude(1) : variant == 1 ? scClaude(1, expiry: now) : Data("invalid-json".utf8)
        let rig = SCReaderRig([scResult(data: data)])
        let result = CredentialStore(files: files, keychain: rig.reader()).loadDetailed(.claudeDefaultDiscovery, now: now)
        #expect(result.viaKeychain); #expect(!result.suspended); #expect(files.count() == 0)
        if variant == 0 { scExpectLoaded(result.result, token: 1) }
        else { scExpectFailure(result.result, variant == 1 ? .expired : .malformed) }
    }

    // Preserves invariant A8: only notFound reaches the single fixed fallback path.
    @Test func notFoundUsesOnlyFixedFallbackAndNeverClaimsKeychainProvenance() throws {
        let rig = SCReaderRig([scResult(44), scResult(44)]), files = SCFiles(), now = SCClock().wallNow()
        files.set(CredentialStore.defaultClaudePath, scClaude(2))
        let store = CredentialStore(files: files, keychain: rig.reader())
        let detailed = store.loadDetailed(.claudeDefaultDiscovery, now: now)
        scExpectLoaded(detailed.result, token: 2); #expect(!detailed.viaKeychain && !detailed.suspended)
        #expect(files.onlyFallback())
        let credential = try store.load(.claudeDefaultDiscovery, now: now)
        let correct = credential.accessToken == scToken(2)
        #expect(correct)
    }

    // Preserves credential boundary A8: denial/suspension never falls through to disk.
    @Test func denialAndSuspensionReportTypedFailureAndNoFallback() {
        let rig = SCReaderRig([scResult(51)]), files = SCFiles(), now = SCClock().wallNow()
        files.set(CredentialStore.defaultClaudePath, scClaude(2))
        let store = CredentialStore(files: files, keychain: rig.reader())
        let first = store.loadDetailed(.claudeDefaultDiscovery, now: now)
        scExpectFailure(first.result, .keychainDenied); #expect(!first.viaKeychain && first.suspended)
        let second = store.loadDetailed(.claudeDefaultDiscovery, now: now)
        scExpectFailure(second.result, .keychainDenied); #expect(!second.viaKeychain && second.suspended)
        do { _ = try store.load(.claudeDefaultDiscovery, now: now); Issue.record("Expected keychainDenied") }
        catch {
            let correct = (error as? CredentialFailure).map { scFailure(.failure($0), .keychainDenied) } ?? false
            let safe = scSafe(String(describing: error))
            #expect(correct); #expect(safe)
        }
        #expect(files.count() == 0); #expect(rig.runner.count() == 1)
    }

    // Preserves invariant A8: explicit file source never consults Keychain or inherits its suspension.
    @Test func explicitFileHasNoKeychainProvenanceOrSuspension() {
        let rig = SCReaderRig([scResult(51)]), files = SCFiles(), now = SCClock().wallNow()
        _ = rig.reader().claudeCredential()
        let path = "/synthetic-session-continuity-file"
        files.set(path, scClaude(2))
        let result = CredentialStore(files: files, keychain: rig.reader()).loadDetailed(.claudeFile(path), now: now)
        scExpectLoaded(result.result, token: 2); #expect(!result.viaKeychain && !result.suspended)
        #expect(rig.runner.count() == 1)
    }

    // Exercises new behaviour A2/A8: explicit interactive flag reaches the concrete detailed reader.
    @Test func interactiveStoreLoadClearsSuspensionAndUsesInteractiveTimeout() {
        let rig = SCReaderRig([scResult(51), scResult(data: scClaude(3))]), now = SCClock().wallNow()
        let store = CredentialStore(files: SCFiles(), keychain: rig.reader())
        _ = store.loadDetailed(.claudeDefaultDiscovery, now: now)
        let result = store.loadDetailed(.claudeDefaultDiscovery, now: now, interactive: true)
        scExpectLoaded(result.result, token: 3); #expect(result.viaKeychain && !result.suspended)
        #expect(!rig.suspensions.isSuspended(rig.service)); #expect(rig.runner.interactiveFlags() == [false, true])
    }
}
