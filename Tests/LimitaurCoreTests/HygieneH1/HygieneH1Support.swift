import Foundation
import Testing
@testable import LimitaurCore

// Duplicated/adapted from ThrottleFreshness, SessionContinuityB and CredentialRecheck.
// Payloads are invented, memory-only; no real credential source is read.
final class H1Clock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock(); private var age = 0.0
    func set(_ value: Double) { lock.withLock { age = value } }
    func wallNow() -> Date { lock.withLock { Date(timeIntervalSince1970: 1_800_000_000 + age) } }
    func monotonicNow() -> Double { lock.withLock { 1_000 + age } }
}
func h1Credential(_ expiry: Int = 10_000) -> Data {
    Data("{\"claudeAiOauth\":{\"accessToken\":\"invented-h1\",\"expiresAt\":\((1_800_000_000 + expiry) * 1000)},\"tokens\":{\"access_token\":\"invented-h1\",\"account_id\":\"shared\"}}".utf8)
}
final class H1Files: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: Data] = ["/h1/a": h1Credential()]
    private var gate: DispatchSemaphore?; private var reads = 0
    func set(_ path: String, _ data: Data?) { lock.withLock { values[path] = data } }
    func block(_ gate: DispatchSemaphore?) { lock.withLock { self.gate = gate } }
    func count() -> Int { lock.withLock { reads } }
    func read(path: String) throws -> Data {
        let (data, gate) = lock.withLock { reads += 1; return (values[path], self.gate) }
        if let gate, gate.wait(timeout: .now() + 5) != .success { throw CredentialFailure.unreadable }
        guard let data else { throw CredentialFailure.missing }; return data
    }
    func release() { lock.withLock { gate?.signal(); gate = nil } }
}
struct H1Keychain: KeychainReading { func claudeCredential() -> KeychainResult { .found(h1Credential()) } }
func h1Profile(_ id: String = "a") -> AccountProfile {
    AccountProfile(id: id, providerID: "claude", label: id, source: .claudeFile("/h1/" + id))
}
func h1Response(_ status: Int = 200, retry: String? = nil) -> HTTPResponse {
    HTTPResponse(status: status, headers: retry.map { ["retry-after": $0] } ?? [:],
        body: Data(#"{"limits":[{"kind":"session","percent":25}],"rate_limit":{"primary_window":{"used_percent":25}}}"#.utf8))
}
actor H1Transport: HTTPTransport {
    private var pending: [CheckedContinuation<HTTPResponse, Error>?] = []; private var closed = false
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if closed { throw TransportFailure.cancelled }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func count() -> Int { pending.count }
    func answer(_ index: Int, _ response: HTTPResponse) { let c = pending[index]; pending[index] = nil; c?.resume(returning: response) }
    func finish() { closed = true; for c in pending { c?.resume(throwing: TransportFailure.cancelled) }; pending = [] }
}
func h1Wait(_ predicate: () async -> Bool) async -> Bool {
    let end = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < end { if await predicate() { return true }; try? await Task.sleep(for: .milliseconds(2)) }
    return await predicate()
}
struct H1Rig {
    let clock = H1Clock(), files = H1Files(), transport = H1Transport(); let monitor: Monitor
    init(reactive: Bool = false) {
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: H1Keychain()), transport: transport, reactiveRecheck: reactive)
    }
    func answer(_ index: Int, _ status: Int = 200, retry: String? = nil) async throws {
        try #require(await h1Wait { await transport.count() > index }); await transport.answer(index, h1Response(status, retry: retry))
    }
    func start(_ profiles: [AccountProfile] = [h1Profile()]) async throws {
        await monitor.setProfiles(profiles); try await answer(0); try #require(await monitor.settle())
        #expect((await monitor.display()).selected.count == 1)
    }
    func retained(_ profiles: [AccountProfile] = [h1Profile()]) async throws {
        try await start(profiles); clock.set(30); await monitor.refresh(); try await answer(1, 429, retry: "55")
        try #require(await monitor.settle()); #expect((await monitor.display()).profiles.first?.freshnessDeadline == 1_133.5)
    }
    func display(_ age: Double) async -> MonitorDisplay { clock.set(age); return await monitor.display() }
    func close() async { await monitor.stop(); files.release(); await transport.finish() }
}
func h1WithRig(reactive: Bool = false, _ body: (H1Rig) async throws -> Void) async throws {
    let rig = H1Rig(reactive: reactive)
    do { try await body(rig); await rig.close() } catch { await rig.close(); throw error }
}
