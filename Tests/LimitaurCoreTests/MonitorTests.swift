import Foundation
import Testing
import Darwin
@testable import LimitaurCore

private final class FakeClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall: Date
    private var mono: TimeInterval
    init(wall: Date = Date(timeIntervalSince1970: 1_800_000_000), mono: TimeInterval = 100) {
        self.wall = wall; self.mono = mono
    }
    func wallNow() -> Date { lock.lock(); defer { lock.unlock() }; return wall }
    func monotonicNow() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return mono }
    func move(wall seconds: TimeInterval = 0, monotonic elapsed: TimeInterval = 0) {
        lock.lock(); wall.addTimeInterval(seconds); mono += elapsed; lock.unlock()
    }
}

private struct FakeFiles: CredentialFileReading {
    let sources: [String: Data]
    func read(path: String) throws -> Data {
        guard let result = sources[path] else { throw CredentialFailure.missing }
        return result
    }
}
private final class RotatingFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    init(_ values: [String: Data]) { self.values = values }
    func read(path: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = values[path] else { throw CredentialFailure.missing }
        return data
    }
    func set(_ path: String, _ data: Data) { lock.lock(); values[path] = data; lock.unlock() }
}
private struct FakeKeychain: KeychainReading {
    let result: KeychainResult
    func claudeCredential() -> KeychainResult { result }
}
private actor FakeTransport: HTTPTransport {
    var answers: [HTTPResponse]
    var calls = 0
    init(_ answers: [HTTPResponse]) { self.answers = answers }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        calls += 1
        guard !answers.isEmpty else { throw TransportFailure.network }
        return answers.removeFirst()
    }
    func count() -> Int { calls }
}

private actor PerProviderTransport: HTTPTransport {
    private var counts: [ProviderID: Int] = [:]
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        counts[request.providerID, default: 0] += 1
        if request.providerID == "codex" { return response(401) }
        return response(200, #"{"limits":[{"kind":"session","percent":30}]}"#)
    }
    func count(_ provider: ProviderID) -> Int { counts[provider, default: 0] }
}

private actor HealthyTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.providerID == "codex" {
            return response(200, #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#)
        }
        return response(200, #"{"limits":[{"kind":"session","percent":25}]}"#)
    }
}

private actor FailoverTransport: HTTPTransport {
    private var calls: [String: Int] = [:]
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        calls[request.bearer, default: 0] += 1
        if request.bearer == "invented-a" && calls[request.bearer] == 2 { return response(401) }
        return response(200, #"{"account_id":"shared","rate_limit":{"primary_window":{"used_percent":55}}}"#)
    }
    func count(_ token: String) -> Int { calls[token, default: 0] }
}

private actor DeferredTransport: HTTPTransport {
    private var pending: [(String, CheckedContinuation<HTTPResponse, Error>?)] = []
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending.append((request.bearer, continuation))
        }
    }
    func requestBearers() -> [String] { pending.map(\.0) }
    func waitForRequests(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while pending.count < count && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return pending.count >= count
    }
    func answer(_ index: Int, with response: HTTPResponse) {
        guard pending.indices.contains(index), let continuation = pending[index].1 else { return }
        pending[index].1 = nil
        continuation.resume(returning: response)
    }
    func fail(_ index: Int) {
        guard pending.indices.contains(index), let continuation = pending[index].1 else { return }
        pending[index].1 = nil
        continuation.resume(throwing: TransportFailure.network)
    }
    func finishOutstanding() {
        for index in pending.indices { fail(index) }
    }
}

private actor CancellationTransport: HTTPTransport {
    private var continuation: CheckedContinuation<HTTPResponse, Error>?
    private var started = false
    private var cancelled = false
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { next in
                if Task.isCancelled { next.resume(throwing: TransportFailure.cancelled); return }
                continuation = next
                started = true
            }
        } onCancel: {
            Task { await self.cancelPending() }
        }
    }
    private func cancelPending() {
        cancelled = true
        continuation?.resume(throwing: TransportFailure.cancelled)
        continuation = nil
    }
    func didStart() -> Bool { started }
    func wasCancelled() -> Bool { cancelled }
}

private func waitUntil(_ predicate: @escaping () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await predicate()
}

private final class BlockingKeychain: KeychainReading, @unchecked Sendable {
    private let releaseGate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var started = false
    func claudeCredential() -> KeychainResult {
        lock.lock(); started = true; lock.unlock()
        _ = releaseGate.wait(timeout: .now() + 10)
        return .denied
    }
    func didStart() -> Bool { lock.lock(); defer { lock.unlock() }; return started }
    func release() { releaseGate.signal() }
}

private final class GatedFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var started = 0
    private var active = 0
    private var maximum = 0
    func read(path: String) throws -> Data {
        lock.lock()
        started += 1
        active += 1
        maximum = max(maximum, active)
        lock.unlock()
        defer { lock.lock(); active -= 1; lock.unlock() }
        guard gate.wait(timeout: .now() + 10) == .success else { throw CredentialFailure.unreadable }
        let id = path.replacingOccurrences(of: "/source-", with: "")
        return Data("{\"tokens\":{\"access_token\":\"invented-\(id)\",\"account_id\":\"account-\(id)\"}}".utf8)
    }
    func counts() -> (started: Int, active: Int, maximum: Int) {
        lock.lock(); defer { lock.unlock() }
        return (started, active, maximum)
    }
    func release(_ count: Int) { for _ in 0..<count { gate.signal() } }
}

private final class SleepFiles: CredentialFileReading, @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reads = 0
    func read(path: String) throws -> Data {
        lock.lock(); reads += 1; let ordinal = reads; lock.unlock()
        if ordinal == 1 { _ = gate.wait(timeout: .now() + 10) }
        let token = ordinal == 1 ? "before" : "after"
        return Data("{\"tokens\":{\"access_token\":\"invented-\(token)\",\"account_id\":\"selected\"}}".utf8)
    }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return reads }
    func release() { gate.signal() }
}

private func response(_ status: Int, _ body: String = "{}", retry: String? = nil) -> HTTPResponse {
    HTTPResponse(status: status, headers: retry.map { ["retry-after": $0] } ?? [:], body: Data(body.utf8))
}

private func waitForDisplay(_ monitor: Monitor, where predicate: @Sendable (MonitorDisplay) -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if predicate(await monitor.display()) { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return predicate(await monitor.display())
}

@Test func accountThrottleAndStaleDisplay() async {
    let clock = FakeClock()
    let codex = Data(#"{"tokens":{"access_token":"synthetic","account_id":"selected"}}"#.utf8)
    let store = CredentialStore(files: FakeFiles(sources: ["/synthetic": codex]), keychain: FakeKeychain(result: .notFound))
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":88,"reset_at":1800000100}}}"#),
                                   response(429, retry: "3600")])
    let monitor = Monitor(clock: clock, credentials: store, transport: transport)
    let profile = AccountProfile(id: "a", providerID: "codex", label: "A", source: .codexFile("/synthetic"))
    await monitor.setProfiles([profile]); await monitor.settle()
    #expect((await monitor.display()).selected.count == 1)
    clock.move(monotonic: 30)
    await monitor.refresh(); await monitor.settle()
    #expect(await transport.count() == 2)
    clock.move(monotonic: 60)
    await monitor.refresh(force: true); await monitor.settle()
    #expect(await transport.count() == 2)
    #expect((await monitor.display()).selected.isEmpty)
    #expect((await monitor.display()).profiles.first?.snapshot != nil)
}

@Test func nominalPollBoundaryMakesProgressAtThirtySeconds() async {
    let clock = FakeClock()
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport(Array(repeating: response(200, #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#), count: 2))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))])
    #expect(await monitor.settle())
    clock.move(monotonic: 29)
    await monitor.refresh(); #expect(await monitor.settle())
    #expect(await transport.count() == 1)
    clock.move(monotonic: 1)
    await monitor.refresh(); #expect(await monitor.settle())
    #expect(await transport.count() == 2)
}

@Test func aliasesAndSourceDetach() async {
    let clock = FakeClock()
    let token = Data(#"{"tokens":{"access_token":"synthetic","account_id":"selected"}}"#.utf8)
    let store = CredentialStore(files: FakeFiles(sources: ["/synthetic": token]), keychain: FakeKeychain(result: .notFound))
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#)])
    let monitor = Monitor(clock: clock, credentials: store, transport: transport)
    let a = AccountProfile(id: "a", providerID: "codex", label: "A", source: .codexFile("/synthetic"))
    let b = AccountProfile(id: "b", providerID: "codex", label: "B", source: .codexFile("/synthetic"))
    await monitor.setProfiles([a, b]); await monitor.settle()
    #expect(await transport.count() == 1)
    #expect((await monitor.display()).selected.count == 1)
    await monitor.setProfiles([b])
    #expect((await monitor.display()).profiles.count == 1)
    #expect((await monitor.display()).selected.count == 1)
}

@Test func duplicateProfileIDsKeepFirstConfiguration() async {
    let firstToken = Data(#"{"tokens":{"access_token":"first-synthetic","account_id":"one"}}"#.utf8)
    let secondToken = Data(#"{"tokens":{"access_token":"second-synthetic","account_id":"two"}}"#.utf8)
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":25}}}"#)])
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/one": firstToken,
                                                                                              "/two": secondToken]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let first = AccountProfile(id: "duplicate", providerID: "codex", label: "First", source: .codexFile("/one"))
    let second = AccountProfile(id: "duplicate", providerID: "codex", label: "Second", source: .codexFile("/two"))
    #expect(normalizedProfiles([first, second]) == [first])
    await monitor.setProfiles([first, second])
    #expect(await monitor.settle())
    #expect(await transport.count() == 1)
    let display = await monitor.display()
    #expect(display.profiles.map(\.profile.label) == ["First"])
    #expect(display.selected.first?.accountID == "one")
}

@Test func sameTokenDifferentSelectedAccountsStaySeparate() async {
    let first = Data(#"{"tokens":{"access_token":"same-synthetic-token","account_id":"one"}}"#.utf8)
    let second = Data(#"{"tokens":{"access_token":"same-synthetic-token","account_id":"two"}}"#.utf8)
    let store = CredentialStore(files: FakeFiles(sources: ["/one": first, "/two": second]),
                                keychain: FakeKeychain(result: .notFound))
    let transport = FakeTransport([response(200, #"{"rate_limit":null}"#), response(200, #"{"rate_limit":null}"#)])
    let monitor = Monitor(clock: FakeClock(), credentials: store, transport: transport)
    let a = AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))
    let b = AccountProfile(id: "two", providerID: "codex", label: "Two", source: .codexFile("/two"))
    await monitor.setProfiles([a, b]); await monitor.settle()
    #expect(await transport.count() == 2)
    #expect((await monitor.display()).profiles.count == 2)
}

@Test func expectedAccountMismatchSendsNoRequest() async {
    let token = Data(#"{"tokens":{"access_token":"synthetic","account_id":"selected"}}"#.utf8)
    let store = CredentialStore(files: FakeFiles(sources: ["/one": token]), keychain: FakeKeychain(result: .notFound))
    let transport = FakeTransport([])
    let monitor = Monitor(clock: FakeClock(), credentials: store, transport: transport)
    let profile = AccountProfile(id: "mismatch", providerID: "codex", label: "Mismatch", source: .codexFile("/one"),
                                 expectedAccountID: "another")
    await monitor.setProfiles([profile])
    await monitor.settle()
    #expect(await transport.count() == 0)
    #expect((await monitor.display()).profiles.first?.health == .unauthenticated)
}

@Test func reconnectMismatchDropsPreviouslyRankedBinding() async {
    let valid = Data(#"{"tokens":{"access_token":"invented-valid","account_id":"selected"}}"#.utf8)
    let wrong = Data(#"{"tokens":{"access_token":"invented-wrong","account_id":"other"}}"#.utf8)
    let files = RotatingFiles(["/selected": valid])
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":93}}}"#)])
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: files,
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let profile = AccountProfile(id: "selected", providerID: "codex", label: "Selected",
                                 source: .codexFile("/selected"), expectedAccountID: "selected")
    await monitor.setProfiles([profile]); #expect(await monitor.settle())
    #expect((await monitor.display()).selected.first?.metric.usedPercent == 93)
    files.set("/selected", wrong)
    await monitor.reconnect("selected"); #expect(await monitor.settle())
    let display = await monitor.display()
    #expect(await transport.count() == 1)
    #expect(display.profiles.count == 1)
    #expect(display.profiles[0].health == .unauthenticated)
    #expect(display.profiles[0].snapshot == nil)
    #expect(display.selected.isEmpty)
}

@Test func sleepInvalidatesPendingCredentialResultAndWakeRevalidates() async {
    let files = SleepFiles()
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":51}}}"#)])
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: files,
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let profile = AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))
    await monitor.setProfiles([profile])
    guard await waitUntil({ files.count() == 1 }) else {
        Issue.record("Initial credential load did not start")
        files.release(); await monitor.stop(); return
    }
    await monitor.sleep()
    files.release()
    await monitor.wake()
    #expect(await monitor.settle())
    #expect(files.count() == 2)
    #expect(await transport.count() == 1)
    #expect((await monitor.display()).selected.first?.metric.usedPercent == 51)
}

@Test func defaultEligibilityIsStickyAcrossRecoveredSourceAndSleepChanges() async {
    let codex = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented"}}"#.utf8)
    let files = FakeFiles(sources: [CredentialStore.defaultCodexPath: codex, "/other": codex])
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: files,
                         keychain: FakeKeychain(result: .found(claude))), transport: HealthyTransport())
    let defaultCodex = AccountProfile(id: "codex-default", providerID: "codex", label: "Default",
                                      source: .codexFile(CredentialStore.defaultCodexPath))
    let defaultClaude = AccountProfile(id: "claude-default", providerID: "claude", label: "Default",
                                       source: .claudeDefaultDiscovery)
    await monitor.setProfiles([defaultCodex, defaultClaude]); #expect(await monitor.settle())
    let baseline = await monitor.statistics()
    #expect(baseline["__eligibility"]?["processID"] == Int(getpid()))
    #expect(baseline["__eligibility"]?["eligible"] == 1)
    var changed = defaultCodex
    changed.source = .codexFile("/other")
    await monitor.setProfiles([changed, defaultClaude]); #expect(await monitor.settle())
    #expect((await monitor.statistics())["__eligibility"]?["eligible"] == 0)
    await monitor.setProfiles([defaultCodex, defaultClaude]); #expect(await monitor.settle())
    let restored = await monitor.statistics()
    #expect(restored["__eligibility"]?["eligible"] == 1)
    #expect((restored["__eligibility"]?["violations"] ?? 0) > (baseline["__eligibility"]?["violations"] ?? 0))
    #expect((restored["__eligibility"]?["sourceChanges"] ?? 0) > (baseline["__eligibility"]?["sourceChanges"] ?? 0))
    await monitor.sleep(); await monitor.wake(); #expect(await monitor.settle())
    #expect((await monitor.statistics())["__eligibility"]?["sleepEvents"] == 1)
}

@Test func knownExpiryInvalidatesStatisticsBeforeNextNetworkPoll() async {
    let clock = FakeClock()
    let codex = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented","expiresAt":1800000006000}}"#.utf8)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(
        files: FakeFiles(sources: [CredentialStore.defaultCodexPath: codex]),
        keychain: FakeKeychain(result: .found(claude))), transport: HealthyTransport())
    let profiles = [
        AccountProfile(id: "codex-default", providerID: "codex", label: "Default",
                       source: .codexFile(CredentialStore.defaultCodexPath)),
        AccountProfile(id: "claude-default", providerID: "claude", label: "Default",
                       source: .claudeDefaultDiscovery)
    ]
    await monitor.setProfiles(profiles); #expect(await monitor.settle())
    let before = await monitor.statistics()
    #expect(before["__eligibility"]?["eligible"] == 1)
    #expect(before["__eligibility"]?["validUntilContinuousNanoseconds"] == 106_000_000_000)
    #expect(before["__eligibility"]?["validUntilWallMilliseconds"] == 1_800_000_006_000)
    #expect((await monitor.display()).nextDisplayDeadline == 106)
    clock.move(wall: 6, monotonic: 6)
    let after = await monitor.statistics()
    #expect(after["__eligibility"]?["eligible"] == 0)
    #expect(after["__eligibility"]?["violations"] == 1)
    #expect(after["codex"]?["success"] == 1)
    #expect(after["claude"]?["success"] == 1)
    #expect((await monitor.display()).nextDisplayDeadline == 190)
}

@Test func cachedUsageAgeInvalidatesStatisticsWithoutRefresh() async {
    let clock = FakeClock()
    let codex = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented"}}"#.utf8)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(
        files: FakeFiles(sources: [CredentialStore.defaultCodexPath: codex]),
        keychain: FakeKeychain(result: .found(claude))), transport: HealthyTransport())
    await monitor.setProfiles([
        AccountProfile(id: "codex-default", providerID: "codex", label: "Default",
                       source: .codexFile(CredentialStore.defaultCodexPath)),
        AccountProfile(id: "claude-default", providerID: "claude", label: "Default",
                       source: .claudeDefaultDiscovery)
    ])
    #expect(await monitor.settle())
    #expect((await monitor.statistics())["__eligibility"]?["validUntilContinuousNanoseconds"] == 190_000_000_000)
    clock.move(monotonic: 90)
    let stale = await monitor.statistics()
    #expect(stale["__eligibility"]?["eligible"] == 0)
    #expect(stale["__eligibility"]?["violations"] == 1)
    #expect(stale["codex"]?["success"] == 1)
    #expect(stale["claude"]?["success"] == 1)
}

@Test func wakeDoesNotClearUnrelatedAuthPause() async {
    let codex = Data(#"{"tokens":{"access_token":"invented-c","account_id":"selected"}}"#.utf8)
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented-a"}}"#.utf8)
    let transport = PerProviderTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/c": codex, "/a": claude]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "c", providerID: "codex", label: "C", source: .codexFile("/c")),
                               AccountProfile(id: "a", providerID: "claude", label: "A", source: .claudeFile("/a"))])
    #expect(await monitor.settle())
    #expect((await monitor.display()).profiles.first(where: { $0.profile.id == "c" })?.health == .unauthenticated)
    await monitor.sleep(); await monitor.wake(); #expect(await monitor.settle())
    #expect(await transport.count("codex") == 1)
    #expect((await monitor.display()).profiles.first(where: { $0.profile.id == "c" })?.health == .unauthenticated)
}

@Test func authPauseRequiresExplicitReconnect() async {
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(401), response(200, #"{"rate_limit":{"primary_window":{"used_percent":70}}}"#)])
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let profile = AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))
    await monitor.setProfiles([profile]); await monitor.settle()
    #expect((await monitor.display()).profiles.first?.health == .unauthenticated)
    await monitor.manualRefresh(); await monitor.settle()
    #expect(await transport.count() == 1)
    await monitor.reconnect("one"); await monitor.settle()
    #expect(await transport.count() == 2)
    #expect((await monitor.display()).selected.first?.metric.usedPercent == 70)
}

@Test func knownExpiryStopsLaterRequests() async {
    let clock = FakeClock()
    let token = Data(#"{"claudeAiOauth":{"accessToken":"invented","expiresAt":1800000001000}}"#.utf8)
    let transport = FakeTransport([response(200, #"{"limits":[{"kind":"session","percent":20}]}"#)])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/claude": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let profile = AccountProfile(id: "claude", providerID: "claude", label: "Claude", source: .claudeFile("/claude"))
    await monitor.setProfiles([profile]); await monitor.settle()
    #expect(await transport.count() == 1)
    clock.move(wall: 2, monotonic: 31)
    await monitor.refresh(force: true); await monitor.settle()
    #expect(await transport.count() == 1)
    #expect((await monitor.display()).profiles.first?.health == .unauthenticated)
}

@Test func detachedThrottleRetainedThenPurged() async {
    let clock = FakeClock()
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(429, retry: "120"), response(200, #"{"rate_limit":null}"#)])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let profile = AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))
    await monitor.setProfiles([profile]); await monitor.settle()
    await monitor.setProfiles([])
    #expect(await monitor.retainedEntityCount() == 1)
    await monitor.setProfiles([profile]); await monitor.settle()
    #expect(await transport.count() == 1)
    await monitor.setProfiles([])
    clock.move(monotonic: 120)
    await monitor.refresh(force: true)
    #expect(await monitor.retainedEntityCount() == 0)
}

@Test func detachedCapacityNeverDropsUnexpiredThrottle() async {
    let clock = FakeClock()
    var sources: [String: Data] = [:]
    for index in 0...256 {
        sources["/source-\(index)"] = Data("{\"tokens\":{\"access_token\":\"invented-\(index)\",\"account_id\":\"account-\(index)\"}}".utf8)
    }
    let transport = FakeTransport(Array(repeating: response(429, retry: "3600"), count: 257))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: sources),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    for index in 0...256 {
        let profile = AccountProfile(id: "single", providerID: "codex", label: "Single",
                                     source: .codexFile("/source-\(index)"))
        await monitor.setProfiles([profile]); await monitor.settle()
    }
    #expect(await monitor.retainedEntityCount() == 256)
    #expect(await transport.count() == 256)
    #expect((await monitor.display()).profiles.first?.health == .unavailable)
    clock.move(monotonic: 3600)
    await monitor.refresh(force: true)
    #expect(await monitor.retainedEntityCount() == 0)
}

@Test func providerFailureDoesNotBlockOtherProvider() async {
    let codex = Data(#"{"tokens":{"access_token":"invented-c","account_id":"selected"}}"#.utf8)
    let claude = Data(#"{"claudeAiOauth":{"accessToken":"invented-a"}}"#.utf8)
    let transport = PerProviderTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/c": codex, "/a": claude]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "c", providerID: "codex", label: "C", source: .codexFile("/c")),
                               AccountProfile(id: "a", providerID: "claude", label: "A", source: .claudeFile("/a"))])
    await monitor.settle()
    #expect(await transport.count("codex") == 1)
    #expect(await transport.count("claude") == 1)
    #expect((await monitor.display()).selected.first?.providerID == "claude")
}

@Test func pendingKeychainCannotBlockCodexProfile() async {
    let keychain = BlockingKeychain()
    let codex = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#)])
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/codex": codex]),
                         keychain: keychain), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "claude", providerID: "claude", label: "Claude", source: .claudeDefaultDiscovery),
                               AccountProfile(id: "codex", providerID: "codex", label: "Codex", source: .codexFile("/codex"))])
    guard await waitUntil({ keychain.didStart() }) else {
        Issue.record("Claude lookup did not start")
        keychain.release()
        await monitor.stop(); return
    }
    guard await waitForDisplay(monitor, where: { $0.selected.count == 1 }) else {
        Issue.record("Codex did not publish while Claude lookup was pending")
        keychain.release()
        await monitor.stop(); return
    }
    #expect(await transport.count() == 1)
    #expect((await monitor.display()).selected.first?.providerID == "codex")
    keychain.release()
    await monitor.settle()
}

@Test func burstCredentialLookupsAreBoundedAndMakeProgress() async {
    let files = GatedFiles()
    let transport = PerProviderTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: files,
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let profiles = (0..<10).map { index in
        AccountProfile(id: "profile-\(index)", providerID: "codex", label: "Synthetic \(index)",
                       source: .codexFile("/source-\(index)"))
    }
    await monitor.setProfiles(profiles)
    guard await waitUntil({ files.counts().started == 8 }) else {
        Issue.record("Eight lookup slots did not fill")
        files.release(10)
        await monitor.stop(); return
    }
    #expect(files.counts().maximum == 8)
    files.release(1)
    guard await waitUntil({ files.counts().started == 9 }) else {
        Issue.record("Queued lookup did not take the released slot")
        files.release(9)
        await monitor.stop(); return
    }
    #expect(files.counts().maximum == 8)
    files.release(9)
    #expect(await monitor.settle())
    #expect(files.counts().started == 10)
    #expect(files.counts().maximum == 8)
    #expect(await transport.count("codex") == 10)
    #expect((await monitor.display()).profiles.count == 10)
}

@Test func mergedAccountFailsOverOnceAndIsolatesRejectedCredential() async {
    let clock = FakeClock()
    let a = Data(#"{"tokens":{"access_token":"invented-a","account_id":"shared"}}"#.utf8)
    let b = Data(#"{"tokens":{"access_token":"invented-b","account_id":"shared"}}"#.utf8)
    let transport = FailoverTransport()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/a": a, "/b": b]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let first = AccountProfile(id: "first", providerID: "codex", label: "First", source: .codexFile("/a"))
    let second = AccountProfile(id: "second", providerID: "codex", label: "Second", source: .codexFile("/b"))
    await monitor.setProfiles([first]); await monitor.settle()
    await monitor.setProfiles([first, second]); await monitor.settle()
    #expect(await monitor.retainedEntityCount() == 1)
    clock.move(monotonic: 30)
    await monitor.refresh(); await monitor.settle(); await monitor.settle()
    #expect(await transport.count("invented-a") == 2)
    #expect(await transport.count("invented-b") == 2)
    let rows = await monitor.display()
    #expect(rows.profiles.first(where: { $0.profile.id == "first" })?.health == .unauthenticated)
    #expect(rows.selected.first?.metric.usedPercent == 55)
    clock.move(monotonic: 30)
    await monitor.refresh(); await monitor.settle()
    #expect(await transport.count("invented-a") == 2)
}

@Test func exponentialBackoffAndManualEquality() async {
    let clock = FakeClock()
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(500), response(500), response(500), response(200, #"{"rate_limit":null}"#)])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let profile = AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))
    await monitor.setProfiles([profile]); await monitor.settle()
    for (before, at, count) in [(29.0, 1.0, 2), (59, 1, 3), (119, 1, 4)] {
        clock.move(monotonic: before)
        await monitor.manualRefresh(); await monitor.settle()
        #expect(await transport.count() == count - 1)
        clock.move(monotonic: at)
        await monitor.manualRefresh(); await monitor.settle()
        #expect(await transport.count() == count)
    }
}

@Test func retryAfterDeltaAndInvalidValue() async {
    let clock = FakeClock()
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(429, retry: "120"), response(429, retry: "invalid"),
                                   response(200, #"{"rate_limit":null}"#)])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))])
    await monitor.settle()
    clock.move(monotonic: 119)
    await monitor.wake(); await monitor.manualRefresh(); await monitor.settle()
    #expect(await transport.count() == 1)
    clock.move(monotonic: 1)
    await monitor.manualRefresh(); await monitor.settle()
    #expect(await transport.count() == 2)
    clock.move(monotonic: 59)
    await monitor.manualRefresh(); await monitor.settle()
    #expect(await transport.count() == 2)
    clock.move(monotonic: 1)
    await monitor.manualRefresh(); await monitor.settle()
    #expect(await transport.count() == 3)
}

@Test func resetUsesWallClockWhileFreshnessUsesMonotonic() async {
    let clock = FakeClock()
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":88,"reset_at":1800000010}}}"#)])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))])
    await monitor.settle()
    #expect((await monitor.display()).selected.count == 1)
    clock.move(wall: 10)
    await monitor.clockChanged()
    #expect((await monitor.display()).selected.isEmpty)
    #expect((await monitor.display()).nextDisplayDeadline == 190)
    await monitor.clockChanged()
    #expect((await monitor.display()).nextDisplayDeadline == 190)
    clock.move(wall: -11)
    await monitor.clockChanged()
    #expect((await monitor.display()).selected.isEmpty)
    #expect((await monitor.display()).nextDisplayDeadline == 190)
    clock.move(monotonic: 90)
    await monitor.clockChanged()
    #expect((await monitor.display()).selected.isEmpty)
    #expect((await monitor.display()).nextDisplayDeadline == nil)
}

@Test func schemaFailureKeepsCacheUntilFreshnessBoundary() async {
    let clock = FakeClock()
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":88}}}"#),
                                   response(200, #"{"unexpected":"shape"}"#)])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))])
    await monitor.settle()
    clock.move(monotonic: 30)
    await monitor.refresh(); await monitor.settle()
    #expect((await monitor.display()).profiles.first?.health == .failed)
    #expect((await monitor.display()).selected.first?.metric.usedPercent == 88)
    clock.move(monotonic: 60)
    await monitor.clockChanged()
    #expect((await monitor.display()).selected.isEmpty)
    #expect((await monitor.display()).profiles.first?.snapshot?.metrics.first?.usedPercent == 88)
}

@Test func cachedErrorHealthSurvivesFreshnessEqualityWithoutFetching() async {
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let success = response(200, #"{"rate_limit":{"primary_window":{"used_percent":88}}}"#)
    for (failure, expected) in [(response(500), Health.unavailable),
                                (response(429, retry: "3600"), .throttled),
                                (response(200, #"{"unexpected":"shape"}"#), .failed)] {
        let clock = FakeClock()
        let transport = FakeTransport([success, failure])
        let monitor = Monitor(clock: clock,
                              credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                                                           keychain: FakeKeychain(result: .notFound)),
                              transport: transport)
        await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One",
                                                  source: .codexFile("/one"))])
        #expect(await monitor.settle())
        clock.move(monotonic: 30)
        await monitor.refresh()
        #expect(await monitor.settle())
        #expect((await monitor.display()).profiles.first?.health == expected)
        #expect((await monitor.display()).selected.first?.metric.usedPercent == 88)
        let throttle = await monitor.throttleDeadline(for: "one")
        clock.move(monotonic: 60)
        await monitor.clockChanged()
        let stale = await monitor.display()
        #expect(stale.selected.isEmpty)
        #expect(stale.profiles.first?.health == expected)
        #expect(stale.profiles.first?.snapshot?.metrics.first?.usedPercent == 88)
        #expect(stale.profiles.first?.message?.contains("Cached usage stale") == true)
        #expect(await monitor.throttleDeadline(for: "one") == throttle)
        #expect(await transport.count() == 2)
        await monitor.stop()
    }
}

@Test func shortRetryAfterShowsEnforcedThirtyAndSixtySecondBackoff() async {
    let clock = FakeClock(wall: Date(timeIntervalSince1970: 1_800_000_040))
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(429, retry: "10"), response(429, retry: "10")])
    let monitor = Monitor(clock: clock,
                          credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                                                       keychain: FakeKeychain(result: .notFound)),
                          transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One",
                                              source: .codexFile("/one"))])
    #expect(await monitor.settle())
    #expect(await monitor.throttleDeadline(for: "one") == 130)
    let firstDate = clock.wallNow().addingTimeInterval(30)
    #expect((await monitor.display()).profiles.first?.message == "Retry after " +
            DateFormatter.localizedString(from: firstDate, dateStyle: .short, timeStyle: .short))
    clock.move(wall: 30, monotonic: 30)
    await monitor.manualRefresh()
    #expect(await monitor.settle())
    #expect(await monitor.throttleDeadline(for: "one") == 190)
    let secondDate = clock.wallNow().addingTimeInterval(60)
    #expect((await monitor.display()).profiles.first?.message == "Retry after " +
            DateFormatter.localizedString(from: secondDate, dateStyle: .short, timeStyle: .short))
    clock.move(monotonic: 59)
    await monitor.manualRefresh()
    #expect(await transport.count() == 2)
    await monitor.stop()
}

@Test func lateResultAfterSourceSwitchCannotPublishOldUsage() async {
    let old = Data(#"{"tokens":{"access_token":"old-synthetic","account_id":"old"}}"#.utf8)
    let new = Data(#"{"tokens":{"access_token":"new-synthetic","account_id":"new"}}"#.utf8)
    let store = CredentialStore(files: FakeFiles(sources: ["/old": old, "/new": new]),
                                keychain: FakeKeychain(result: .notFound))
    let transport = DeferredTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: store, transport: transport)
    let before = AccountProfile(id: "stable", providerID: "codex", label: "Account", source: .codexFile("/old"))
    let after = AccountProfile(id: "stable", providerID: "codex", label: "Account", source: .codexFile("/new"))
    await monitor.setProfiles([before])
    guard await transport.waitForRequests(1) else {
        Issue.record("Old request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await monitor.setProfiles([after])
    guard await transport.waitForRequests(2) else {
        Issue.record("Replacement request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await transport.answer(0, with: response(200, #"{"rate_limit":{"primary_window":{"used_percent":99}}}"#))
    await transport.answer(1, with: response(200, #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#))
    await monitor.settle()
    #expect((await monitor.display()).selected.map(\.metric.usedPercent) == [20])
    #expect((await monitor.display()).profiles.first?.profile.id == "stable")
}

@Test func lateErrorAfterDisableCannotChangeNewBinding() async {
    let old = Data(#"{"tokens":{"access_token":"invented-old","account_id":"old"}}"#.utf8)
    let new = Data(#"{"tokens":{"access_token":"invented-new","account_id":"new"}}"#.utf8)
    let transport = DeferredTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/old": old, "/new": new]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let before = AccountProfile(id: "stable", providerID: "codex", label: "Old", source: .codexFile("/old"))
    let after = AccountProfile(id: "stable", providerID: "codex", label: "New", source: .codexFile("/new"))
    await monitor.setProfiles([before])
    guard await transport.waitForRequests(1) else {
        Issue.record("Old request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await monitor.setProfiles([])
    await monitor.setProfiles([after])
    guard await transport.waitForRequests(2) else {
        Issue.record("Replacement request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await transport.fail(0)
    await transport.answer(1, with: response(200, #"{"rate_limit":{"primary_window":{"used_percent":41}}}"#))
    await monitor.settle()
    #expect((await monitor.display()).selected.first?.metric.usedPercent == 41)
    #expect((await monitor.display()).profiles.first?.health == .healthy)
}

@Test func changingAliasLabelPreservesInflightFetch() async {
    let token = Data(#"{"tokens":{"access_token":"synthetic","account_id":"selected"}}"#.utf8)
    let store = CredentialStore(files: FakeFiles(sources: ["/one": token]), keychain: FakeKeychain(result: .notFound))
    let transport = DeferredTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: store, transport: transport)
    let before = AccountProfile(id: "stable", providerID: "codex", label: "Before", source: .codexFile("/one"))
    let after = AccountProfile(id: "stable", providerID: "codex", label: "After", source: .codexFile("/one"))
    await monitor.setProfiles([before])
    guard await transport.waitForRequests(1) else {
        Issue.record("Request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await monitor.setProfiles([after])
    await transport.answer(0, with: response(200, #"{"rate_limit":{"primary_window":{"used_percent":70}}}"#))
    await monitor.settle()
    #expect((await monitor.display()).selected.first?.accountLabel == "After")
}

@Test func tokenRotationKeepsUnaffectedAliasCache() async {
    let original = Data(#"{"tokens":{"access_token":"invented-old","account_id":"selected"}}"#.utf8)
    let replacement = Data(#"{"tokens":{"access_token":"invented-new","account_id":"selected"}}"#.utf8)
    let files = RotatingFiles(["/a": original, "/b": original])
    let transport = FakeTransport([response(200, #"{"rate_limit":{"primary_window":{"used_percent":62}}}"#),
                                   response(200, #"{"rate_limit":{"primary_window":{"used_percent":74}}}"#)])
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: files,
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let a = AccountProfile(id: "a", providerID: "codex", label: "A", source: .codexFile("/a"))
    let b = AccountProfile(id: "b", providerID: "codex", label: "B", source: .codexFile("/b"))
    await monitor.setProfiles([a, b]); await monitor.settle()
    #expect(await transport.count() == 1)
    files.set("/a", replacement)
    await monitor.reconnect("a"); await monitor.settle()
    #expect(await transport.count() == 2)
    let rows = await monitor.display()
    #expect(rows.profiles.first(where: { $0.profile.id == "b" })?.snapshot?.metrics.first?.usedPercent == 62)
    #expect(rows.profiles.first(where: { $0.profile.id == "a" })?.snapshot?.metrics.first?.usedPercent == 74)
}

@Test func detachingOneAliasKeepsSharedInflightRequest() async {
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = DeferredTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/same": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let a = AccountProfile(id: "a", providerID: "codex", label: "A", source: .codexFile("/same"))
    let b = AccountProfile(id: "b", providerID: "codex", label: "B", source: .codexFile("/same"))
    await monitor.setProfiles([a])
    guard await transport.waitForRequests(1) else {
        Issue.record("Shared request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await monitor.setProfiles([a, b])
    guard await waitUntil({ await monitor.isAttached("b") }) else {
        Issue.record("Second alias did not attach to the in-flight entity")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await monitor.setProfiles([b])
    await transport.answer(0, with: response(200, #"{"rate_limit":{"primary_window":{"used_percent":64}}}"#))
    await monitor.settle()
    #expect((await monitor.display()).selected.first?.accountLabel == "B")
    #expect((await monitor.display()).profiles.count == 1)
}

@Test func lastSubscriberDetachmentCancelsSharedRequest() async {
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = CancellationTransport()
    let monitor = Monitor(clock: FakeClock(), credentials: CredentialStore(files: FakeFiles(sources: ["/same": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let a = AccountProfile(id: "a", providerID: "codex", label: "A", source: .codexFile("/same"))
    let b = AccountProfile(id: "b", providerID: "codex", label: "B", source: .codexFile("/same"))
    await monitor.setProfiles([a])
    #expect(await waitUntil { await transport.didStart() })
    await monitor.setProfiles([a, b])
    guard await waitUntil({ await monitor.isAttached("b") }) else {
        Issue.record("Second alias did not attach before first alias detached")
        await monitor.stop(); return
    }
    await monitor.setProfiles([b])
    #expect(!(await transport.wasCancelled()))
    await monitor.setProfiles([])
    #expect(await waitUntil { await transport.wasCancelled() })
    #expect(await monitor.settle())
}

@Test func verifiedMergeRetainsMaximumThrottle() async {
    let clock = FakeClock()
    let aToken = Data(#"{"tokens":{"access_token":"invented-a","account_id":"shared"}}"#.utf8)
    let bToken = Data(#"{"tokens":{"access_token":"invented-b","account_id":"shared"}}"#.utf8)
    let transport = DeferredTransport()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/a": aToken, "/b": bToken]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    let a = AccountProfile(id: "a", providerID: "codex", label: "A", source: .codexFile("/a"))
    let b = AccountProfile(id: "b", providerID: "codex", label: "B", source: .codexFile("/b"))
    let verified = #"{"account_id":"shared","rate_limit":{"primary_window":{"used_percent":40}}}"#
    await monitor.setProfiles([a])
    guard await transport.waitForRequests(1) else {
        Issue.record("Initial verified request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await transport.answer(0, with: response(200, verified))
    #expect(await monitor.settle())
    clock.move(monotonic: 30)
    await monitor.refresh()
    guard await transport.waitForRequests(2) else {
        Issue.record("Throttle request did not start")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await transport.answer(1, with: response(429, retry: "120"))
    #expect(await monitor.settle())
    await monitor.setProfiles([a, b])
    #expect(await waitForDisplay(monitor) { $0.profiles.count == 2 })
    #expect(await monitor.settle())
    #expect((await transport.requestBearers()).count == 2)
    clock.move(monotonic: 120)
    await monitor.refresh(force: true)
    guard await transport.waitForRequests(4) else {
        Issue.record("Both account requests did not start at the deadline")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    let bearers = await transport.requestBearers()
    guard let aIndex = bearers.indices.dropFirst(2).first(where: { bearers[$0] == "invented-a" }),
          let bIndex = bearers.indices.dropFirst(2).first(where: { bearers[$0] == "invented-b" }) else {
        Issue.record("Expected both bound credentials to request at the deadline")
        await monitor.stop(); await transport.finishOutstanding()
        return
    }
    await transport.answer(aIndex, with: response(429, retry: "600"))
    guard await waitUntil({ await monitor.throttleDeadline(for: "a") == 850 }) else {
        Issue.record("Second throttle deadline was not established")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    let throttledRow = (await monitor.display()).profiles.first(where: { $0.profile.id == "a" })
    #expect(throttledRow?.health == .throttled)
    #expect(throttledRow?.message?.contains("Retry after") == true)
    #expect(throttledRow?.message?.contains("Cached usage stale") == true)
    await transport.answer(bIndex, with: response(200, verified))
    #expect(await monitor.settle())
    #expect(await monitor.retainedEntityCount() == 1)
    #expect(await monitor.throttleDeadline(for: "a") == 850)
    clock.move(monotonic: 599)
    await monitor.manualRefresh()
    #expect((await transport.requestBearers()).count == 4)
    clock.move(monotonic: 1)
    await monitor.manualRefresh()
    guard await transport.waitForRequests(5) else {
        Issue.record("Merged account did not retry at the retained deadline")
        await monitor.stop(); await transport.finishOutstanding(); return
    }
    await monitor.setProfiles([])
    await transport.answer(4, with: response(200, verified))
    #expect(await monitor.settle())
}

@Test func credentialExpiryAndFallback() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let valid = Data(#"{"claudeAiOauth":{"accessToken":"synthetic","expiresAt":1800000001000}}"#.utf8)
    let expired = Data(#"{"claudeAiOauth":{"accessToken":"synthetic","expiresAt":1799999999000}}"#.utf8)
    let files = FakeFiles(sources: ["/valid": valid, CredentialStore.defaultClaudePath: expired])
    let keychain = FakeKeychain(result: .found(valid))
    let store = CredentialStore(files: files, keychain: keychain)
    #expect(try store.load(.claudeDefaultDiscovery, now: now).expiresAt == now.addingTimeInterval(1))
    #expect(throws: CredentialFailure.self) { try store.load(.claudeFile(CredentialStore.defaultClaudePath), now: now) }
    let fallback = CredentialStore(files: files, keychain: FakeKeychain(result: .notFound))
    #expect(throws: CredentialFailure.self) { try fallback.load(.claudeDefaultDiscovery, now: now) }
    let denied = CredentialStore(files: files, keychain: FakeKeychain(result: .denied))
    #expect(throws: CredentialFailure.self) { try denied.load(.claudeDefaultDiscovery, now: now) }
    let malformed = Data(#"{"claudeAiOauth":{"accessToken":"synthetic","expiresAt":true}}"#.utf8)
    let malformedStore = CredentialStore(files: FakeFiles(sources: ["/bad": malformed]), keychain: FakeKeychain(result: .notFound))
    #expect(throws: CredentialFailure.self) { try malformedStore.load(.claudeFile("/bad"), now: now) }
}

@Test func retryAfterDateSurvivesWallClockJump() async {
    let clock = FakeClock()
    let date = clock.wallNow().addingTimeInterval(120)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    let token = Data(#"{"tokens":{"access_token":"synthetic","account_id":"selected"}}"#.utf8)
    let store = CredentialStore(files: FakeFiles(sources: ["/one": token]), keychain: FakeKeychain(result: .notFound))
    let transport = FakeTransport([response(429, retry: formatter.string(from: date)),
                                   response(200, #"{"rate_limit":null}"#)])
    let monitor = Monitor(clock: clock, credentials: store, transport: transport)
    let profile = AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))
    await monitor.setProfiles([profile]); await monitor.settle()
    clock.move(wall: 3600)
    await monitor.clockChanged()
    await monitor.refresh(force: true); await monitor.settle()
    #expect(await transport.count() == 1)
    clock.move(monotonic: 120)
    await monitor.refresh(force: true); await monitor.settle()
    #expect(await transport.count() == 2)
}

@Test func retryAfterDateSurvivesBackwardWallJump() async {
    let clock = FakeClock()
    let date = clock.wallNow().addingTimeInterval(120)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    let token = Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    let transport = FakeTransport([response(429, retry: formatter.string(from: date)), response(200, #"{"rate_limit":null}"#)])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: FakeFiles(sources: ["/one": token]),
                         keychain: FakeKeychain(result: .notFound)), transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/one"))])
    await monitor.settle()
    clock.move(wall: -3600, monotonic: 119)
    await monitor.clockChanged()
    await monitor.manualRefresh(); await monitor.settle()
    #expect(await transport.count() == 1)
    clock.move(monotonic: 1)
    await monitor.manualRefresh(); await monitor.settle()
    #expect(await transport.count() == 2)
}
