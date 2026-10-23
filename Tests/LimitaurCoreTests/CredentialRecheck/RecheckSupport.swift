import Foundation
import Testing
@testable import LimitaurCore

// All credential and response fixtures in this directory are invented and memory-only.
// Assertions expose counts/booleans, never bearer strings, fingerprints, or source paths.
let crPause = "Session expired or rejected; resumes automatically after the provider app signs in again"
let crDenied = "Keychain access unavailable; choose Connect / Authorize"

final class CRClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall = Date(timeIntervalSince1970: 1_800_000_000)
    private var mono: TimeInterval = 100
    func wallNow() -> Date { lock.lock(); defer { lock.unlock() }; return wall }
    func monotonicNow() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return mono }
    func move(wall seconds: TimeInterval = 0, mono elapsed: TimeInterval = 0) {
        lock.lock(); wall.addTimeInterval(seconds); mono += elapsed; lock.unlock()
    }
}

final class CRGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var timedOut = false
    func wait() {
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            lock.lock(); timedOut = true; lock.unlock()
        }
    }
    func release() { semaphore.signal() }
    func expired() -> Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
}

struct CRRead: Sendable {
    let result: KeychainResult
    let gate: CRGate?
    let afterRead: (@Sendable () -> Void)?
    init(_ result: KeychainResult, gate: CRGate? = nil, afterRead: (@Sendable () -> Void)? = nil) {
        self.result = result; self.gate = gate; self.afterRead = afterRead
    }
}

final class CRKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private var plan: [Int: CRRead] = [:]
    private var fallback: KeychainResult
    private var flags: [Bool] = []
    private var finished: Set<Int> = []
    init(_ result: KeychainResult = .denied) { fallback = result }
    func set(_ result: KeychainResult) { lock.lock(); fallback = result; lock.unlock() }
    func at(_ ordinal: Int, _ read: CRRead) { lock.lock(); plan[ordinal] = read; lock.unlock() }
    func claudeCredential() -> KeychainResult { claudeCredential(interactive: false) }
    func claudeCredential(interactive: Bool) -> KeychainResult {
        lock.lock()
        flags.append(interactive)
        let ordinal = flags.count
        let read = plan[ordinal] ?? CRRead(fallback)
        lock.unlock()
        read.gate?.wait()
        read.afterRead?()
        lock.lock(); finished.insert(ordinal); lock.unlock()
        return read.result
    }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return flags.count }
    func didFinish(_ ordinal: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return finished.contains(ordinal) }
    func interactions() -> [Bool] { lock.lock(); defer { lock.unlock() }; return flags }
}

final class CRFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var reads: [String: Int] = [:]
    private var total = 0
    private var gates: [Int: CRGate] = [:]
    func set(_ path: String, _ data: Data) { lock.lock(); values[path] = data; lock.unlock() }
    func block(_ ordinal: Int, on gate: CRGate) { lock.lock(); gates[ordinal] = gate; lock.unlock() }
    func read(path: String) throws -> Data {
        lock.lock()
        total += 1; reads[path, default: 0] += 1
        let value = values[path], gate = gates[total]
        lock.unlock()
        gate?.wait()
        guard let value else { throw CredentialFailure.missing }
        return value
    }
    func count(_ path: String? = nil) -> Int {
        lock.lock(); defer { lock.unlock() }
        return path.map { reads[$0, default: 0] } ?? total
    }
    func onlyRead(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return !reads.isEmpty && reads.keys.allSatisfy { $0 == path }
    }
}

func crToken(_ id: Int) -> String { "invented-recheck-credential-\(id)" }
func crPath(_ id: Int) -> String { "/synthetic-recheck-source-\(id)" }
func crClaude(_ id: Int, expires: Date? = nil) -> Data {
    var fields: [String: Any] = ["accessToken": crToken(id)]
    if let expires { fields["expiresAt"] = Int64(expires.timeIntervalSince1970 * 1000) }
    return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": fields])
}
func crCodex(_ id: Int, account: String = "selected") -> Data {
    try! JSONSerialization.data(withJSONObject: ["tokens": ["access_token": crToken(id), "account_id": account]])
}
func crProfile(_ id: String = "a", source: CredentialSource = .claudeDefaultDiscovery,
               expected: AccountID? = nil, label: String = "Original") -> AccountProfile {
    let provider: ProviderID
    if case .codexFile = source { provider = "codex" } else { provider = "claude" }
    return AccountProfile(id: id, providerID: provider, label: label, source: source, expectedAccountID: expected)
}
func crResponse(_ status: Int = 200, percent: Int = 25, verified: String? = nil,
                retry: String? = nil, codex: Bool = false) -> HTTPResponse {
    var root: [String: Any] = codex
        ? ["rate_limit": ["primary_window": ["used_percent": percent]]]
        : ["limits": [["kind": "session", "percent": percent]]]
    if let verified { root["account_id"] = verified }
    return HTTPResponse(status: status, headers: retry.map { ["retry-after": $0] } ?? [:],
                        body: try! JSONSerialization.data(withJSONObject: root))
}

actor CRTransport: HTTPTransport {
    private var requests: [HTTPRequest] = []
    private var queued: [HTTPResponse]
    private var held: [Int: CheckedContinuation<HTTPResponse, Error>] = [:]
    private var tokenReplies: [String: [HTTPResponse]] = [:]
    private let deferred: Bool
    init(_ queued: [HTTPResponse] = [], deferred: Bool = false) { self.queued = queued; self.deferred = deferred }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let index = requests.count
        requests.append(request)
        if var replies = tokenReplies[request.bearer], !replies.isEmpty {
            let response = replies.removeFirst(); tokenReplies[request.bearer] = replies; return response
        }
        if !queued.isEmpty { return queued.removeFirst() }
        if deferred {
            return try await withCheckedThrowingContinuation { held[index] = $0 }
        }
        return crResponse(codex: request.providerID == "codex")
    }
    func reply(token id: Int, with responses: [HTTPResponse]) { tokenReplies[crToken(id)] = responses }
    func count() -> Int { requests.count }
    func count(token id: Int) -> Int { requests.filter { $0.bearer == crToken(id) }.count }
    func index(token id: Int, after start: Int = 0) -> Int? {
        requests.indices.dropFirst(start).first { requests[$0].bearer == crToken(id) }
    }
    func answer(_ index: Int, _ response: HTTPResponse) { held.removeValue(forKey: index)?.resume(returning: response) }
    func finish() {
        let pending = held; held.removeAll()
        for continuation in pending.values { continuation.resume(throwing: TransportFailure.cancelled) }
    }
}

func crWait(_ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await predicate()
}
func crRow(_ monitor: Monitor, _ id: String = "a") async -> ProfileDisplay? {
    (await monitor.display()).profiles.first { $0.profile.id == id }
}
func crCount(_ monitor: Monitor, _ key: String) async -> Int {
    (await monitor.statistics())["__eligibility"]?[key] ?? 0
}
func crHasMessage(_ row: ProfileDisplay?, _ message: String) -> Bool {
    row?.message == message || row?.message == message + "; Cached usage stale"
}
func crExpectMessage(_ row: ProfileDisplay?, _ expected: String,
                     sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = crHasMessage(row, expected)
    #expect(matches, sourceLocation: sourceLocation)
}
func crExpectSameMessage(_ lhs: ProfileDisplay?, _ rhs: ProfileDisplay?,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    let unchanged = lhs?.message == rhs?.message
    #expect(unchanged, sourceLocation: sourceLocation)
}
func crCachedPercent(_ row: ProfileDisplay?) -> Double? { row?.snapshot?.metrics.first?.usedPercent }

// Make controlled stale reads observable without exposing their payloads in failures.
func crFlush() async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(10))
}
