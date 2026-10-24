import Foundation
import Testing
@testable import LimitaurCore

// Synthetic payloads stay in memory. Pass only booleans/counts to #expect, never
// credentials, ProcessResult, raw output, requests, errors or read outcomes.
// A1 specifies stored fields but no initializer: use the memberwise initializer
// via @testable, in the field order given by A1 (no extra production API assumed).
func scResult(_ code: Int32? = 0, text: String = "", data: Data? = nil,
              signal: Bool = false, timeout: Bool = false, oversized: Bool = false) -> ProcessResult {
    ProcessResult(exitCode: code, signaled: signal, output: data ?? Data(text.utf8),
                  timedOut: timeout, oversized: oversized)
}

final class SCGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var expired = false
    func wait() {
        if semaphore.wait(timeout: .now() + 2) == .timedOut { lock.withLock { expired = true } }
    }
    func release() { semaphore.signal() }
    func didExpire() -> Bool { lock.withLock { expired } }
}

struct SCCall: Sendable {
    let executable: String, arguments: [String], environment: [String: String]
    let workingDirectory: String?, timeout: TimeInterval, grace: TimeInterval
    let output: OutputMode, registry: ProcessRegistry?
}
struct SCStep: Sendable {
    let result: ProcessResult
    var gate: SCGate? = nil
    var onStart: (@Sendable () -> Void)? = nil
}
final class SCRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [SCStep], calls: [SCCall] = []
    private var active = 0, maximum = 0, completed = 0
    init(_ results: [ProcessResult]) { steps = results.map { SCStep(result: $0) } }
    init(steps: [SCStep]) { self.steps = steps }
    func append(_ result: ProcessResult) { lock.withLock { steps.append(SCStep(result: result)) } }
    func run(executable: String, arguments: [String], environment: [String: String], workingDirectory: String?,
             timeout: TimeInterval, graceAfterTerm: TimeInterval, output: OutputMode, registry: ProcessRegistry?) -> ProcessResult {
        let step: SCStep = lock.withLock {
            calls.append(SCCall(executable: executable, arguments: arguments, environment: environment,
                                workingDirectory: workingDirectory, timeout: timeout, grace: graceAfterTerm,
                                output: output, registry: registry))
            active += 1; maximum = max(maximum, active)
            return steps.isEmpty ? SCStep(result: scResult(1)) : steps.removeFirst()
        }
        step.onStart?(); step.gate?.wait()
        lock.withLock { active -= 1; completed += 1 }
        return step.result
    }
    func count() -> Int { lock.withLock { calls.count } }
    func finished() -> Int { lock.withLock { completed } }
    func maxActive() -> Int { lock.withLock { maximum } }
    func matches(_ service: String, account: String, interactive: Bool, registry: ProcessRegistry) -> Bool {
        lock.withLock {
            calls.count == 1 && calls.allSatisfy {
                $0.executable == "/usr/bin/security" &&
                $0.arguments == ["find-generic-password", "-a", account, "-s", service, "-w"] &&
                $0.environment.isEmpty && $0.workingDirectory == nil &&
                $0.timeout == (interactive ? 600 : 5) && $0.grace == (interactive ? 5 : 1) &&
                $0.output == .capture(limit: 2_097_154) && $0.registry === registry
            }
        }
    }
    func interactiveFlags() -> [Bool] { lock.withLock { calls.map { $0.timeout == 600 } } }
}

struct SCReaderRig: Sendable {
    let service = "limitaur-test-" + UUID().uuidString
    let suspensions = KeychainSuspensions(), registry = ProcessRegistry()
    let runner: SCRunner
    init(_ results: [ProcessResult]) { runner = SCRunner(results) }
    init(steps: [SCStep]) { runner = SCRunner(steps: steps) }
    func reader(account: String = "invented-account") -> SecurityToolKeychainReader {
        SecurityToolKeychainReader(runner: runner, service: service, account: account,
                                   registry: registry, suspensions: suspensions)
    }
}
func scFound(_ result: KeychainResult, _ expected: Data) -> Bool {
    if case .found(let data) = result { return data == expected }; return false
}
func scDenied(_ result: KeychainResult) -> Bool { if case .denied = result { return true }; return false }
func scMissing(_ result: KeychainResult) -> Bool { if case .notFound = result { return true }; return false }
func scHex(_ data: Data, uppercase: Bool = false) -> Data {
    Data(data.map { String(format: uppercase ? "%02X" : "%02x", $0) }.joined().utf8)
}
func scWait(_ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await predicate()
}
func scFlush() async { for _ in 0..<20 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(25)) }

final class SCClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall = Date(timeIntervalSince1970: 1_800_000_000), mono: TimeInterval = 100
    func wallNow() -> Date { lock.withLock { wall } }
    func monotonicNow() -> TimeInterval { lock.withLock { mono } }
    func advance(_ seconds: TimeInterval) { lock.withLock { wall.addTimeInterval(seconds); mono += seconds } }
}
final class SCFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:], paths: [String] = []
    func set(_ path: String, _ data: Data) { lock.withLock { values[path] = data } }
    func read(path: String) throws -> Data {
        let value = lock.withLock { paths.append(path); return values[path] }
        guard let value else { throw CredentialFailure.missing }; return value
    }
    func count() -> Int { lock.withLock { paths.count } }
    func onlyFallback() -> Bool { lock.withLock { paths == [CredentialStore.defaultClaudePath] } }
}
func scToken(_ id: Int) -> String { "invented-session-continuity-canary-\(id)-END" }
func scClaude(_ id: Int, expiry: Date? = nil) -> Data {
    var oauth: [String: Any] = ["accessToken": scToken(id)]
    if let expiry { oauth["expiresAt"] = Int64(expiry.timeIntervalSince1970 * 1000) }
    return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
}
func scProfile(_ id: String = "a", source: CredentialSource = .claudeDefaultDiscovery, enabled: Bool = true) -> AccountProfile {
    AccountProfile(id: id, providerID: "claude", label: "Synthetic account", source: source, enabled: enabled)
}
func scResponse(_ status: Int = 200, retry: String? = nil) -> HTTPResponse {
    HTTPResponse(status: status, headers: retry.map { ["retry-after": $0] } ?? [:],
                 body: Data("{\"limits\":[{\"kind\":\"session\",\"percent\":25}]}".utf8))
}
actor SCTransport: HTTPTransport {
    private var replies: [HTTPResponse], requests: [HTTPRequest] = []
    private var held: [Int: CheckedContinuation<HTTPResponse, Error>] = [:]
    private let deferred: Bool
    init(_ replies: [HTTPResponse] = [], deferred: Bool = false) { self.replies = replies; self.deferred = deferred }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let ordinal = requests.count; requests.append(request)
        if !replies.isEmpty { return replies.removeFirst() }
        if deferred { return try await withCheckedThrowingContinuation { held[ordinal] = $0 } }
        return scResponse()
    }
    func enqueue(_ response: HTTPResponse) { replies.append(response) }
    func count() -> Int { requests.count }
    func count(token: Int) -> Int { requests.filter { $0.bearer == scToken(token) }.count }
    func answer(_ ordinal: Int, _ response: HTTPResponse) { held.removeValue(forKey: ordinal)?.resume(returning: response) }
    func finish() {
        let pending = held; held.removeAll()
        for continuation in pending.values { continuation.resume(throwing: TransportFailure.cancelled) }
    }
}
func scRow(_ monitor: Monitor, _ id: String = "a") async -> ProfileDisplay? {
    (await monitor.display()).profiles.first { $0.profile.id == id }
}
func scCount(_ monitor: Monitor, _ key: String) async -> Int { (await monitor.statistics())["__eligibility"]?[key] ?? 0 }
let scSuspended = "Keychain read did not finish; answer any Keychain dialog, then choose Connect / Authorize"
let scPaused = "Session expired or rejected; resumes automatically after the provider app signs in again"
let scDeniedMessage = "Keychain access unavailable; choose Connect / Authorize"
func scMessage(_ row: ProfileDisplay?, _ expected: String) -> Bool {
    row?.message == expected || row?.message == expected + "; Cached usage stale"
}
func scSafe(_ text: String, tokens: [Int] = [1, 2, 3]) -> Bool {
    tokens.allSatisfy { !text.contains(scToken($0)) }
}
func scFailure(_ result: Result<Credential, CredentialFailure>, _ expected: CredentialFailure) -> Bool {
    if case .failure(let failure) = result { return String(describing: failure) == String(describing: expected) }
    return false
}
func scLoaded(_ result: Result<Credential, CredentialFailure>, token: Int) -> Bool {
    if case .success(let credential) = result { return credential.accessToken == scToken(token) }; return false
}

// Keep arguments outside Testing's expression-capture macros even on regressions.
func scExpectFound(_ result: KeychainResult, _ expected: Data, sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = scFound(result, expected); #expect(matches, sourceLocation: sourceLocation)
}
func scExpectDenied(_ result: KeychainResult, sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = scDenied(result); #expect(matches, sourceLocation: sourceLocation)
}
func scExpectMissing(_ result: KeychainResult, sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = scMissing(result); #expect(matches, sourceLocation: sourceLocation)
}
func scExpectLoaded(_ result: Result<Credential, CredentialFailure>, token: Int,
                    sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = scLoaded(result, token: token); #expect(matches, sourceLocation: sourceLocation)
}
func scExpectFailure(_ result: Result<Credential, CredentialFailure>, _ expected: CredentialFailure,
                     sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = scFailure(result, expected); #expect(matches, sourceLocation: sourceLocation)
}
func scExpectMessage(_ row: ProfileDisplay?, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = scMessage(row, expected); #expect(matches, sourceLocation: sourceLocation)
}
