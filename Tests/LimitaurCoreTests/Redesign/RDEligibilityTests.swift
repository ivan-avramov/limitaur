import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (S5/P25), I = preserves an invariant, N = new behaviour.

private final class RDClock: MonitorClock, @unchecked Sendable {
    func wallNow() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
    func monotonicNow() -> TimeInterval { 100 }
}
private struct RDFiles: CredentialFileReading {
    let sources: [String: Data]
    func read(path: String) throws -> Data {
        guard let result = sources[path] else { throw CredentialFailure.missing }
        return result
    }
}
private struct RDKeychain: KeychainReading {
    let result: KeychainResult
    func claudeCredential() -> KeychainResult { result }
}
private actor RDTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = request.providerID == "codex" ? #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#
            : #"{"limits":[{"kind":"session","percent":25}]}"#
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
    }
}

private let rdCodex = AccountProfile(id: "codex-default", providerID: "codex", label: "Default",
                                     source: .codexFile(CredentialStore.defaultCodexPath))
private let rdClaude = AccountProfile(id: "claude-default", providerID: "claude", label: "Default",
                                      source: .claudeDefaultDiscovery)
private func rdThird(enabled: Bool) -> AccountProfile {
    AccountProfile(id: "codex-other", providerID: "codex", label: "Account 2", source: .codexFile("/rd/other"), enabled: enabled)
}
private func rdMonitor() -> Monitor {
    let codex = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let other = Data(#"{"tokens":{"access_token":"invented-2","account_id":"second"}}"#.utf8)
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented"}}"#.utf8)
    return Monitor(clock: RDClock(), credentials: CredentialStore(
        files: RDFiles(sources: [CredentialStore.defaultCodexPath: codex, "/rd/other": other]),
        keychain: RDKeychain(result: .found(claude))), transport: RDTransport())
}
private func rdEligible(_ monitor: Monitor) async -> Int? { (await monitor.statistics())["__eligibility"]?["eligible"] }

@Suite struct RDEligibilityTests {
    // I, C5: the two enabled healthy defaults alone stay eligible.
    @Test func twoEnabledDefaultsAreEligible() async {
        let monitor = rdMonitor()
        await monitor.setProfiles([rdCodex, rdClaude]); #expect(await monitor.settle())
        #expect(await rdEligible(monitor) == 1)
        await monitor.stop()
    }
    // R, C5, S5: a third profile that is disabled no longer makes default-workload eligibility false.
    @Test func disabledThirdProfileKeepsEligibility() async {
        let monitor = rdMonitor()
        await monitor.setProfiles([rdCodex, rdClaude, rdThird(enabled: false)]); #expect(await monitor.settle())
        #expect(await rdEligible(monitor) == 1)
        await monitor.stop()
    }
    // R, C5, S5: the same holds for a disabled Cursor profile (Settings keeps it when a section is switched off).
    @Test func disabledCursorProfileKeepsEligibility() async {
        let monitor = rdMonitor()
        let cursor = AccountProfile(id: "cursor-default", providerID: "cursor", label: "Default",
                                    source: .cursorDefaultDiscovery, enabled: false)
        await monitor.setProfiles([rdCodex, rdClaude, cursor]); #expect(await monitor.settle())
        #expect(await rdEligible(monitor) == 1)
        await monitor.stop()
    }
    // I, C5: a third profile that is enabled still makes eligibility false.
    @Test func enabledThirdProfileStillBreaksEligibility() async {
        let monitor = rdMonitor()
        await monitor.setProfiles([rdCodex, rdClaude, rdThird(enabled: true)]); #expect(await monitor.settle())
        #expect(await rdEligible(monitor) == 0)
        await monitor.stop()
    }
    // N, C5: switching the third profile on and off moves eligibility 1 -> 0 -> 1 and counts one violation.
    @Test func togglingThirdProfileTracksEligibility() async {
        let monitor = rdMonitor()
        await monitor.setProfiles([rdCodex, rdClaude, rdThird(enabled: false)]); #expect(await monitor.settle())
        #expect(await rdEligible(monitor) == 1)
        await monitor.setProfiles([rdCodex, rdClaude, rdThird(enabled: true)]); #expect(await monitor.settle())
        let broken = await monitor.statistics()["__eligibility"]
        #expect(broken?["eligible"] == 0 && broken?["violations"] == 1)
        await monitor.setProfiles([rdCodex, rdClaude, rdThird(enabled: false)]); #expect(await monitor.settle())
        #expect(await rdEligible(monitor) == 1)
        await monitor.stop()
    }
    // I, C5: a disabled default profile is not eligible, even with a disabled third profile present.
    @Test func disabledDefaultStaysIneligible() async {
        let monitor = rdMonitor()
        var claude = rdClaude
        claude.enabled = false
        await monitor.setProfiles([rdCodex, claude, rdThird(enabled: false)]); #expect(await monitor.settle())
        #expect(await rdEligible(monitor) == 0)
        await monitor.stop()
    }
}
