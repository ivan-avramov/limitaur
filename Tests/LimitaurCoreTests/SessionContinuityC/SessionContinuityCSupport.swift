import Foundation
import Darwin
import Testing
@testable import LimitaurCore

// All credentials are invented, memory-only values. Capture only booleans,
// counters and presentation metadata in assertions, never payloads or environments.
protocol CNRedacted: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}
extension CNRedacted {
    var description: String { "Synthetic test dependency (<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [(label: "value", value: "<redacted>" as Any)]) }
}
final class CNClock: MonitorClock, CNRedacted, @unchecked Sendable {
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private let lock = NSLock()
    private var wall: Double = 0, mono: Double = 0
    func set(_ age: Double, mono: Double? = nil) { lock.withLock { wall = age; self.mono = mono ?? age } }
    func wallNow() -> Date { lock.withLock { Self.epoch.addingTimeInterval(wall) } }
    func monotonicNow() -> Double { lock.withLock { 1_000 + mono } }
}
func cnDate(_ age: Double) -> Date { CNClock.epoch.addingTimeInterval(age) }
func cnToken(_ id: Int) -> String { "invented-continuity-c-memory-only-\(id)-END" }
func cnCredential(_ id: Int = 1, expiry: Double? = 10) -> Data {
    var oauth: [String: Any] = ["accessToken": cnToken(id)]
    if let expiry { oauth["expiresAt"] = Int64(cnDate(expiry).timeIntervalSince1970 * 1_000) }
    return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
}
let cnSource = CredentialSource.claudeDefaultDiscovery.stableID
let cnPaused = "Session expired or rejected; resumes automatically after the provider app signs in again"
let cnDenied = "Keychain access unavailable; choose Connect / Authorize"
let cnSuspended = "Keychain read did not finish; answer any Keychain dialog, then choose Connect / Authorize"
let cnNudging = "Running claude to renew the session"
let cnFailed = "claude exited without renewing the session; run claude to sign in"
let cnMissing = "claude command not found; run claude to sign in"
func cnProfile(_ id: String = "a", source: CredentialSource = .claudeDefaultDiscovery,
               enabled: Bool = true) -> AccountProfile {
    AccountProfile(id: id, providerID: "claude", label: "Synthetic nudge account", source: source, enabled: enabled)
}
func cnFound(_ id: Int = 1, expiry: Double? = 10) -> KeychainReadOutcome {
    KeychainReadOutcome(result: .found(cnCredential(id, expiry: expiry)), reason: .found)
}
final class CNKeychain: KeychainReading, CNRedacted, @unchecked Sendable {
    private let lock = NSLock()
    private var current = cnFound(), reads: [Bool] = []
    func set(_ outcome: KeychainReadOutcome) { lock.withLock { current = outcome } }
    func claudeCredential() -> KeychainResult { claudeCredentialDetailed(interactive: false).result }
    func claudeCredentialDetailed(interactive: Bool) -> KeychainReadOutcome {
        lock.withLock { reads.append(interactive); return current }
    }
    func count() -> Int { lock.withLock { reads.count } }
    func interactions() -> [Bool] { lock.withLock { reads } }
}
final class CNFiles: CredentialFileReading, CNRedacted, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func set(_ path: String, _ data: Data) { lock.withLock { values[path] = data } }
    func read(path: String) throws -> Data {
        guard let data = lock.withLock({ values[path] }) else { throw CredentialFailure.missing }; return data
    }
}
actor CNTransport: HTTPTransport {
    private var calls = 0
    private var status = 200
    func setStatus(_ value: Int) { status = value }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        calls += 1
        return HTTPResponse(status: status, headers: [:],
            body: Data("{\"limits\":[{\"kind\":\"session\",\"percent\":25}]}".utf8))
    }
    func count() -> Int { calls }
}
final class CNBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ value: Bool) { lock.withLock { self.value = value } }
    func get() -> Bool { lock.withLock { value } }
}
final class CNNudger: SessionNudging, CNRedacted, @unchecked Sendable {
    private let lock = NSLock()
    private var held: [CheckedContinuation<NudgeOutcome, Never>] = []
    private var calls = 0, maximum = 0, active = 0, closed = false
    private var observer: (@Sendable () async -> Void)?
    private var waits: [TimeInterval] = []
    func observe(_ body: @escaping @Sendable () async -> Void) { lock.withLock { observer = body } }
    func nudge() async -> NudgeOutcome {
        let hook = lock.withLock { observer }
        await hook?()
        return await withCheckedContinuation { continuation in
            let finishNow = lock.withLock { () -> Bool in
                if closed { return true }
                calls += 1; active += 1; maximum = max(maximum, active)
                held.append(continuation); return false
            }
            if finishNow { continuation.resume(returning: .notFound) }
        }
    }
    func waitForCompletion(upTo: TimeInterval) { lock.withLock { waits.append(upTo) } }
    func count() -> Int { lock.withLock { calls } }
    func peak() -> Int { lock.withLock { maximum } }
    func pending() -> Int { lock.withLock { held.count } }
    func waitCount() -> Int { lock.withLock { waits.count } }
    func complete(_ outcome: NudgeOutcome) {
        let next = lock.withLock { () -> CheckedContinuation<NudgeOutcome, Never>? in
            guard !held.isEmpty else { return nil }; active -= 1; return held.removeFirst()
        }
        next?.resume(returning: outcome)
    }
    func finish() {
        let all = lock.withLock { () -> [CheckedContinuation<NudgeOutcome, Never>] in
            closed = true; let result = held; held.removeAll(); active = 0; return result
        }
        for item in all { item.resume(returning: .notFound) }
    }
}
// Synchronous negative-observation helper; only the test's detached waiter calls it.
func cnSignaled(_ semaphore: DispatchSemaphore, within seconds: Double) -> Bool {
    semaphore.wait(timeout: .now() + seconds) == .success
}
func cnWait(_ body: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline {
        if await body() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await body()
}
func cnRow(_ monitor: Monitor, _ id: String = "a") async -> ProfileDisplay? {
    (await monitor.display()).profiles.first { $0.profile.id == id }
}
func cnCount(_ monitor: Monitor, _ key: String) async -> Int {
    (await monitor.statistics())["__eligibility"]?[key] ?? 0
}
func cnHasMessage(_ row: ProfileDisplay?, _ expected: String) -> Bool {
    // C2 specifies the base message; the baseline display may prefix an alias label and append cache staleness.
    guard var message = row?.message else { return false }
    if message.hasPrefix("Alias of "), let separator = message.range(of: "; ") {
        message = String(message[separator.upperBound...])
    }
    return message == expected || message == expected + "; Cached usage stale"
}
func cnExpectMessage(_ row: ProfileDisplay?, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let matches = cnHasMessage(row, expected); #expect(matches, sourceLocation: sourceLocation)
}
struct CNRig: CNRedacted, Sendable {
    let clock = CNClock(), keychain = CNKeychain(), files = CNFiles(), transport = CNTransport(), nudger = CNNudger()
    let monitor: Monitor
    init(installNudger: Bool = true, reactive: Bool = true) {
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                          transport: transport, reactiveRecheck: reactive, nudger: installNudger ? nudger : nil)
    }
    func start(unbound: Bool = false, enabled: Bool? = true,
               profiles: [AccountProfile] = [cnProfile()]) async throws {
        if unbound { keychain.set(cnFound(expiry: -1)) }
        if let enabled { await monitor.setNudgeEnabled(enabled) }
        await monitor.setProfiles(profiles)
        try #require(await monitor.settle())
    }
    func tick(_ age: Double, mono: Double? = nil, driver: RefreshDriver = .cycle) async throws {
        clock.set(age, mono: mono); await monitor.refresh(driver: driver)
        try #require(await monitor.settle())
    }
    func trigger(unbound: Bool = false) async throws {
        try await start(unbound: unbound)
        try await tick(300)
        try #require(await cnWait { nudger.count() == 1 })
    }
    func complete(_ outcome: NudgeOutcome, expectedMessage: String) async throws {
        nudger.complete(outcome)
        try #require(await cnWait { await cnHasMessage(cnRow(monitor), expectedMessage) })
    }
    func close() async { await monitor.stop(); nudger.finish() }
}
func cnWithRig(_ rig: CNRig = CNRig(), _ body: (CNRig) async throws -> Void) async throws {
    do { try await body(rig); await rig.close() }
    catch { await rig.close(); throw error }
}

// C1 names NudgeFileChecking but omits its requirements. Chosen reading: a
// minimal POSIX-shaped seam, with String paths and the same return conventions:
// access(_:_:), stat(_:), lstat(_:), realpath(_:), mkdir(_:_:), chmod(_:_:).
// stat follows links; lstat does not. The latter three also cover work/tmp
// preparation, so no test needs to touch a real executable or directory.
// This is an explicit interface assumption, not a claimed published API.
struct CNNode: Sendable {
    var mode: mode_t
    var owner: uid_t = geteuid()
    var executable = true
    var target: String? = nil
}
final class CNNudgeFiles: NudgeFileChecking, CNRedacted, @unchecked Sendable {
    private let lock = NSLock()
    private var nodes: [String: CNNode] = [:]
    private var modes: [(String, mode_t)] = []
    private var creations: [(String, mode_t)] = []
    private var deniedChmod = Set<String>(), deniedMkdir = Set<String>()
    func put(_ path: String, _ node: CNNode) { lock.withLock { nodes[path] = node } }
    func candidate(_ path: String = cnCandidate, mode: mode_t = mode_t(S_IFREG) | 0o755,
                   owner: uid_t = geteuid(), executable: Bool = true,
                   parentMode: mode_t = mode_t(S_IFDIR) | 0o755, parentOwner: uid_t = geteuid()) {
        put(path, CNNode(mode: mode, owner: owner, executable: executable))
        put((path as NSString).deletingLastPathComponent, CNNode(mode: parentMode, owner: parentOwner))
    }
    func denyChmod(_ path: String) { lock.withLock { _ = deniedChmod.insert(path) } }
    func denyMkdir(_ path: String) { lock.withLock { _ = deniedMkdir.insert(path) } }
    private func followed(_ path: String) -> CNNode? {
        guard let node = nodes[path] else { return nil }
        return node.target.flatMap { nodes[$0] } ?? (node.target == nil ? node : nil)
    }
    private func status(_ node: CNNode?) -> Darwin.stat? {
        guard let node else { return nil }; var result = Darwin.stat()
        result.st_mode = node.mode; result.st_uid = node.owner; return result
    }
    func access(_ path: String, _ mode: Int32) -> Int32 {
        lock.withLock {
            guard let node = followed(path) else { return -1 }
            return mode & X_OK != 0 && !node.executable ? -1 : 0
        }
    }
    func stat(_ path: String) -> Darwin.stat? { lock.withLock { status(followed(path)) } }
    func lstat(_ path: String) -> Darwin.stat? { lock.withLock { status(nodes[path]) } }
    func realpath(_ path: String) -> String? { lock.withLock { nodes[path].map { $0.target ?? path } } }
    func mkdir(_ path: String, _ mode: mode_t) -> Int32 {
        lock.withLock {
            creations.append((path, mode))
            guard nodes[path] == nil, !deniedMkdir.contains(path) else { return -1 }
            nodes[path] = CNNode(mode: mode_t(S_IFDIR) | mode); return 0
        }
    }
    func chmod(_ path: String, _ mode: mode_t) -> Int32 {
        lock.withLock {
            modes.append((path, mode))
            guard var node = nodes[path], !deniedChmod.contains(path) else { return -1 }
            node.mode = (node.mode & mode_t(S_IFMT)) | mode; nodes[path] = node; return 0
        }
    }
    func privateDirectory(_ path: String) -> Bool {
        lock.withLock { nodes[path].map { $0.mode == (mode_t(S_IFDIR) | 0o700) && $0.target == nil } ?? false }
    }
    func madeWithPrivateMode(_ path: String) -> Bool {
        lock.withLock { creations.contains { $0.0 == path && $0.1 == 0o700 } }
    }
}
let cnCandidate = "/virtual/continuity-c/bin/claude"
let cnWork = "/virtual/continuity-c/work"
let cnHome = "/virtual/continuity-c/home"
let cnUser = "synthetic-nudge-user"
let cnArguments = ["-p", "hi", "--model", "haiku", "--safe-mode", "--no-session-persistence", "--strict-mcp-config", "--tools", ""]
func cnEnvironment(candidate: String = cnCandidate, resolved: String = cnCandidate,
                   home: String = cnHome, user: String = cnUser) -> [String: String] {
    ["HOME": home, "USER": user, "LOGNAME": user,
     "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:" + (candidate as NSString).deletingLastPathComponent + ":" + (resolved as NSString).deletingLastPathComponent,
     "LANG": "en_US.UTF-8", "TMPDIR": cnWork + "/tmp/", "DISABLE_AUTOUPDATER": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"]
}
final class CNRunner: ProcessRunning, CNRedacted, @unchecked Sendable {
    private let condition = NSCondition()
    private let result: ProcessResult
    private let blocked: Bool
    private let onRun: (@Sendable () -> Void)?
    private var released = false, calls = 0, completed = 0, expired = false
    private var executable = "", arguments: [String] = [], environment: [String: String] = [:]
    private var directory: String?, timeout: Double = 0, grace: Double = 0, output: OutputMode = .capture(limit: 0)
    private var registered = false, utility = false
    init(_ result: ProcessResult = ProcessResult(exitCode: 0), blocked: Bool = false, onRun: (@Sendable () -> Void)? = nil) {
        self.result = result; self.blocked = blocked; self.onRun = onRun
    }
    func run(executable: String, arguments: [String], environment: [String: String], workingDirectory: String?,
             timeout: TimeInterval, graceAfterTerm: TimeInterval, output: OutputMode, registry: ProcessRegistry?) -> ProcessResult {
        condition.lock(); defer { condition.unlock() }
        self.executable = executable; self.arguments = arguments; self.environment = environment; directory = workingDirectory
        self.timeout = timeout; grace = graceAfterTerm; self.output = output; registered = registry != nil
        utility = qos_class_self() == QOS_CLASS_UTILITY; calls += 1; onRun?(); condition.broadcast()
        let deadline = Date(timeIntervalSinceNow: 3)
        while blocked && !released { if !condition.wait(until: deadline) { expired = true; break } }
        completed += 1; return result
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
    func count() -> Int { condition.lock(); defer { condition.unlock() }; return calls }
    func finished() -> Int { condition.lock(); defer { condition.unlock() }; return completed }
    func didExpire() -> Bool { condition.lock(); defer { condition.unlock() }; return expired }
    func chose(_ path: String) -> Bool { condition.lock(); defer { condition.unlock() }; return executable == path }
    func argsMatch(_ value: [String]) -> Bool { condition.lock(); defer { condition.unlock() }; return arguments == value }
    func envMatches(_ value: [String: String]) -> Bool { condition.lock(); defer { condition.unlock() }; return environment == value }
    func optionsMatch() -> Bool {
        condition.lock(); defer { condition.unlock() }
        return directory == cnWork && timeout == 60 && grace == 10 && output == .discard && !registered && utility
    }
}
func cnCLI(_ runner: CNRunner, _ files: CNNudgeFiles, candidates: [String] = [cnCandidate],
           home: String = cnHome, user: String = cnUser) -> ClaudeCLINudger {
    ClaudeCLINudger(runner: runner, candidates: candidates, workDirectory: cnWork, home: home, user: user, fileChecks: files)
}
enum CNOutcome: String, CaseIterable, Sendable {
    case success, failure, timeout, launch, missing
    var value: NudgeOutcome {
        switch self {
        case .success: return .ran(exitCode: 0)
        case .failure: return .ran(exitCode: 1)
        case .timeout: return .timedOut
        case .launch: return .launchFailed
        case .missing: return .notFound
        }
    }
    var message: String { self == .success ? cnPaused : (self == .missing ? cnMissing : cnFailed) }
}
