import Foundation
import Testing
@testable import LimitaurCore

// All payloads are invented and remain in memory. Assertions capture only
// booleans, policy state, counts and presentation metadata, never requests/tokens.
final class BClock: MonitorClock, @unchecked Sendable {
    static let wall = Date(timeIntervalSince1970: 1_800_000_000)
    static let mono: TimeInterval = 1_000
    private let lock = NSLock()
    private var age: TimeInterval = 0
    func set(_ age: TimeInterval) { lock.withLock { self.age = age } }
    func wallNow() -> Date { lock.withLock { Self.wall.addingTimeInterval(age) } }
    func monotonicNow() -> TimeInterval { lock.withLock { Self.mono + age } }
}
func bDate(_ age: TimeInterval) -> Date { BClock.wall.addingTimeInterval(age) }

// B1 leaves the wire representation open. Use named fields, JSONEncoder's
// default Date strategy, and an Int-keyed dictionary, the direct Codable reading.
// Construct wire documents rather than assuming an initializer for Reduction.
struct BReduction: Codable { let from: TimeInterval, to: TimeInterval; let at: Date }
struct BPolicyDocument: Codable {
    var interval: TimeInterval = 50
    var lastChange: Date? = nil
    var lastReduction: BReduction? = nil
    var blockedUntil: [Int: Date] = [:]
}
func bPolicy(_ interval: TimeInterval = 50, change: TimeInterval? = nil,
             reduction: BReduction? = nil, blocks: [Int: Date] = [:], now: TimeInterval = 0) throws -> PollingPolicy {
    let data = try JSONEncoder().encode(BPolicyDocument(interval: interval,
        lastChange: change.map(bDate), lastReduction: reduction, blockedUntil: blocks))
    return PollingPolicy.decode(data, now: bDate(now))
}
func bEncoding(_ policy: PollingPolicy) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try encoder.encode(policy)
}
func bPrime(_ policy: inout PollingPolicy, count: Int = 4, at age: TimeInterval = 0) {
    for _ in 0..<count { _ = policy.recordClean(now: bDate(age), reductionAllowed: false) }
}
func bReduced() throws -> PollingPolicy {
    var policy = try bPolicy(change: -86_400)
    bPrime(&policy)
    _ = policy.recordClean(now: bDate(0), reductionAllowed: true)
    return policy
}

final class BGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var expired = false
    func wait() {
        if semaphore.wait(timeout: .now() + 4) == .timedOut { lock.withLock { expired = true } }
    }
    func release() { semaphore.signal() }
    func didExpire() -> Bool { lock.withLock { expired } }
}
struct BRead: Sendable { let value: Data?; var gate: BGate? = nil }
final class BFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:], steps: [String: [BRead]] = [:]
    private var reads: [String: Int] = [:], gates: [BGate] = []
    func set(_ path: String, _ value: Data) { lock.withLock { values[path] = value } }
    func enqueue(_ path: String, _ read: BRead) {
        lock.withLock { steps[path, default: []].append(read); if let gate = read.gate { gates.append(gate) } }
    }
    func read(path: String) throws -> Data {
        let step: BRead = lock.withLock {
            reads[path, default: 0] += 1
            if steps[path]?.isEmpty == false { return steps[path]!.removeFirst() }
            return BRead(value: values[path])
        }
        step.gate?.wait()
        guard let value = step.value else { throw CredentialFailure.missing }; return value
    }
    func count(_ path: String) -> Int { lock.withLock { reads[path, default: 0] } }
    func releaseAll() { let all = lock.withLock { gates }; for gate in all { gate.release() } }
}
struct BNoKeychain: KeychainReading {
    func claudeCredential() -> KeychainResult { .notFound }
}
func bToken(_ id: Int = 1, provider: String = "codex") -> Data {
    let token = "invented-continuity-b-memory-only-\(id)-END"
    if provider == "claude" {
        return Data("{\"claudeAiOauth\":{\"accessToken\":\"\(token)\"}}".utf8)
    }
    return Data("{\"tokens\":{\"access_token\":\"\(token)\",\"account_id\":\"shared\"}}".utf8)
}
func bProfile(_ id: String = "a", provider: String = "codex") -> AccountProfile {
    let path = "/invented-continuity-b/" + id
    return AccountProfile(id: id, providerID: ProviderID(provider), label: "Synthetic " + id,
        source: provider == "claude" ? .claudeFile(path) : .codexFile(path))
}
func bPath(_ id: String = "a") -> String { "/invented-continuity-b/" + id }
func bResponse(_ status: Int, retry: String? = nil, body: String = "{}") -> HTTPResponse {
    HTTPResponse(status: status, headers: retry.map { ["retry-after": $0] } ?? [:], body: Data(body.utf8))
}
func bSuccess(_ provider: String = "codex", percent: Int = 25, verified: Bool = false) -> HTTPResponse {
    if provider == "claude" {
        return bResponse(200, body: "{\"limits\":[{\"kind\":\"session\",\"percent\":\(percent)}]}")
    }
    let account = verified ? "\"account_id\":\"shared\"," : ""
    return bResponse(200, body: "{\(account)\"rate_limit\":{\"primary_window\":{\"used_percent\":\(percent)}}}")
}
actor BTransport: HTTPTransport {
    private var calls: [(ProviderID, CheckedContinuation<HTTPResponse, Error>?)] = []
    private var closed = false
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard !closed else { throw TransportFailure.cancelled }
        return try await withCheckedThrowingContinuation { calls.append((request.providerID, $0)) }
    }
    func count() -> Int { calls.count }
    func count(_ provider: String) -> Int { calls.filter { $0.0.rawValue == provider }.count }
    func provider(_ index: Int) -> String { calls[index].0.rawValue }
    func answer(_ index: Int, _ response: HTTPResponse) {
        guard calls.indices.contains(index), let continuation = calls[index].1 else { return }
        calls[index].1 = nil; continuation.resume(returning: response)
    }
    func fail(_ index: Int) {
        guard calls.indices.contains(index), let continuation = calls[index].1 else { return }
        calls[index].1 = nil; continuation.resume(throwing: TransportFailure.network)
    }
    func finish() { closed = true; for index in calls.indices { fail(index) } }
}
func bWait(_ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await predicate()
}
struct BRig: Sendable {
    let clock = BClock(), files = BFiles(), transport = BTransport()
    let monitor: Monitor
    init(reactive: Bool = true) {
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: BNoKeychain()),
                          transport: transport, reactiveRecheck: reactive)
    }
    func start(policies: [String: PollingPolicy]? = ["codex": PollingPolicy()],
               profiles: [AccountProfile] = [bProfile()], tokens: [Int] = [1], verified: Bool = false) async throws {
        for (index, profile) in profiles.enumerated() {
            files.set(bPath(profile.id), bToken(tokens[min(index, tokens.count - 1)], provider: profile.providerID.rawValue))
        }
        if let policies { await monitor.setPolling(policies) }
        await monitor.setProfiles(profiles)
        // Initial load uses the baseline internal (forced) driver, hence zero clean polls.
        try #require(await bWait { await transport.count() >= 1 })
        // Different unverified fingerprints/providers each own one initial request.
        let expected = Set(profiles.enumerated().map { index, profile in
            profile.providerID.rawValue + ":" + String(tokens[min(index, tokens.count - 1)])
        }).count
        try #require(await bWait { await transport.count() == expected })
        for index in 0..<expected {
            await transport.answer(index, bSuccess(await transport.provider(index), verified: verified))
        }
        try #require(await monitor.settle())
    }
    func request(at age: TimeInterval, index: Int, driver: RefreshDriver = .cycle, force: Bool = false) async throws {
        clock.set(age); await monitor.refresh(force: force, driver: driver)
        try #require(await bWait { await transport.count() > index })
    }
    func reply(at age: TimeInterval, index: Int, response: HTTPResponse, force: Bool = false) async throws {
        try await request(at: age, index: index, force: force)
        await transport.answer(index, response); try #require(await monitor.settle())
    }
    func policy(_ provider: String = "codex") async throws -> PollingPolicy {
        try #require((await monitor.display()).polling[provider])
    }
    func close() async { files.releaseAll(); await monitor.stop(); await transport.finish() }
}
// Always release blocked fake reads and continuations, including #require failures.
func bWithRig(_ rig: BRig = BRig(), _ body: (BRig) async throws -> Void) async throws {
    do { try await body(rig); await rig.close() }
    catch { await rig.close(); throw error }
}
