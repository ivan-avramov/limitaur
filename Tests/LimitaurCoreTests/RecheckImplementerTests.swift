import Foundation
import Testing
@testable import LimitaurCore

private final class RClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall = Date(timeIntervalSince1970: 1_800_000_000)
    private var mono: TimeInterval = 100
    func wallNow() -> Date { lock.lock(); defer { lock.unlock() }; return wall }
    func monotonicNow() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return mono }
    func move(wall seconds: TimeInterval = 0, monotonic elapsed: TimeInterval = 0) {
        lock.lock(); wall.addTimeInterval(seconds); mono += elapsed; lock.unlock()
    }
}

/// Keychain whose item can be replaced; records the interactive flag of every read.
private final class RKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private var result: KeychainResult
    private var flags: [Bool] = []
    init(_ result: KeychainResult) { self.result = result }
    func claudeCredential() -> KeychainResult { claudeCredential(interactive: false) }
    func claudeCredential(interactive: Bool) -> KeychainResult {
        lock.lock(); defer { lock.unlock() }
        flags.append(interactive)
        return result
    }
    func set(_ value: KeychainResult) { lock.lock(); result = value; lock.unlock() }
    func interactiveFlags() -> [Bool] { lock.lock(); defer { lock.unlock() }; return flags }
}

private func claudeItem(_ token: String, expiresAtSeconds: Int) -> KeychainResult {
    .found(Data("{\"claudeAiOauth\":{\"accessToken\":\"\(token)\",\"expiresAt\":\(expiresAtSeconds * 1000)}}".utf8))
}

private actor RTransport: HTTPTransport {
    private var bearers: [String] = []
    private let status: Int
    init(status: Int = 200) { self.status = status }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        bearers.append(request.bearer)
        return HTTPResponse(status: status, headers: [:],
                            body: Data(#"{"limits":[{"kind":"session","percent":30}]}"#.utf8))
    }
    func seen() -> [String] { bearers }
}

private final class RFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data
    private var reads = 0
    private var gate: DispatchSemaphore?
    init(_ data: Data) { self.data = data }
    func read(path: String) throws -> Data {
        lock.lock(); reads += 1; let blocker = gate; let value = data; lock.unlock()
        _ = blocker?.wait(timeout: .now() + 10)
        return value
    }
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func block() { lock.lock(); gate = DispatchSemaphore(value: 0); lock.unlock() }
    func release(_ count: Int) { lock.lock(); let blocker = gate; lock.unlock(); for _ in 0..<count { blocker?.signal() } }
    func readCount() -> Int { lock.lock(); defer { lock.unlock() }; return reads }
}

private func codexFile(_ token: String) -> Data {
    Data("{\"tokens\":{\"access_token\":\"\(token)\",\"account_id\":\"acct\"}}".utf8)
}

private let claude = AccountProfile(id: "c", providerID: "claude", label: "Claude", source: .claudeDefaultDiscovery)
private let codex = AccountProfile(id: "x", providerID: "codex", label: "Codex", source: .codexFile("/rx"))

private func stat(_ monitor: Monitor, _ name: String) async -> Int {
    await monitor.statistics()["__eligibility"]?[name] ?? 0
}
private func message(_ monitor: Monitor, _ id: String) async -> String? {
    await monitor.display().profiles.first { $0.profile.id == id }?.message?
        .replacingOccurrences(of: "; Cached usage stale", with: "")
}
private func waitFor(_ predicate: @escaping () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await predicate()
}

private let paused = "Session expired or rejected; resumes automatically after the provider app signs in again"
private let denied = "Keychain access unavailable; choose Connect / Authorize"

@Test func recheckIsSilentThenResumesOnADifferentToken() async {
    let clock = RClock()
    let keychain = RKeychain(claudeItem("invented-one", expiresAtSeconds: 1_800_000_100))
    let transport = RTransport()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: RFiles(Data()), keychain: keychain),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([claude])
    #expect(await monitor.settle())
    #expect(await transport.seen() == ["invented-one"])

    // Expired and inside the interval: paused, no read.
    clock.move(wall: 200, monotonic: 10)
    await monitor.refresh()
    #expect(await message(monitor, "c") == paused)
    #expect(keychain.interactiveFlags().count == 1)

    // Due: same expired token. Nothing changes, no request, no failure counted.
    clock.move(monotonic: 60)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(keychain.interactiveFlags() == [false, false])
    #expect(await stat(monitor, "credentialRechecks") == 1)
    #expect(await stat(monitor, "credentialFailures") == 0)
    #expect(await message(monitor, "c") == paused)
    #expect(await transport.seen() == ["invented-one"])

    // Denied switches the message once; a later non-denied result switches it back; wake never sets it.
    keychain.set(.denied)
    clock.move(monotonic: 60)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await message(monitor, "c") == denied)
    keychain.set(.notFound)
    clock.move(monotonic: 60)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await message(monitor, "c") == paused)
    keychain.set(.denied)
    clock.move(monotonic: 60)
    await monitor.sleep()
    await monitor.wake()
    #expect(await monitor.settle())
    #expect(await message(monitor, "c") == paused)
    #expect(await stat(monitor, "credentialRechecks") == 4)

    // A different unexpired token resumes with exactly one request.
    keychain.set(claudeItem("invented-two", expiresAtSeconds: 1_800_003_600))
    clock.move(monotonic: 60)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialResumes") == 1)
    #expect(await transport.seen() == ["invented-one", "invented-two"])
    #expect(await monitor.isAttached("c"))
    #expect(!keychain.interactiveFlags().contains(true))
    clock.move(monotonic: 20)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await transport.seen().count == 2)
}

@Test func recheckCadenceAndDrivers() async {
    let clock = RClock()
    let keychain = RKeychain(claudeItem("invented-one", expiresAtSeconds: 1_800_000_100))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: RFiles(Data()), keychain: keychain),
                          transport: RTransport(), recheckInterval: 0)  // invalid: behaves as 300
    await monitor.setProfiles([claude])
    #expect(await monitor.settle())
    clock.move(wall: 200, monotonic: 100)
    await monitor.refresh()
    clock.move(monotonic: 190)
    await monitor.refresh()
    await monitor.dropdownOpened()
    #expect(await stat(monitor, "credentialRechecks") == 0)
    // A wall jump alone does nothing; internal never re-checks.
    clock.move(wall: 100_000)
    await monitor.refresh(force: true, driver: .internal)
    await monitor.refresh()
    #expect(await stat(monitor, "credentialRechecks") == 0)
    // Manual ignores the interval.
    await monitor.manualRefresh()
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialRechecks") == 1)
    // Nothing is issued while asleep; wake issues one when due.
    await monitor.sleep()
    clock.move(monotonic: 1000)
    await monitor.refresh()
    #expect(await stat(monitor, "credentialRechecks") == 1)
    await monitor.wake()
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialRechecks") == 2)
    #expect(!keychain.interactiveFlags().contains(true))
    // Due again at the interval for the dropdown.
    clock.move(monotonic: 300)
    await monitor.dropdownOpened()
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialRechecks") == 3)
}

@Test func pauseCauseDecidesWhetherTheSameTokenLifts() async {
    let clock = RClock()
    let files = RFiles(codexFile("invented-a"))
    let transport = RTransport(status: 401)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codex])
    #expect(await monitor.settle())
    #expect(!(await monitor.isAttached("x")))
    #expect(await message(monitor, "x") == paused)
    // 401 pause: the same token, by re-check or manual refresh, stays paused and is not resent.
    clock.move(monotonic: 60)
    await monitor.refresh()
    #expect(await monitor.settle())
    await monitor.manualRefresh()
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialRechecks") == 2)
    #expect(!(await monitor.isAttached("x")))
    #expect(await transport.seen() == ["invented-a"])
    // A new token resumes (and is rejected again by this transport, once).
    files.set(codexFile("invented-b"))
    await monitor.manualRefresh()
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialResumes") == 1)
    #expect(await transport.seen() == ["invented-a", "invented-b"])
}

@Test func failedLoadPauseLiftsOnTheSameUnexpiredToken() async {
    let clock = RClock()
    let files = RFiles(codexFile("invented-a"))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: RTransport(), recheckInterval: 60)
    await monitor.setProfiles([codex])
    #expect(await monitor.settle())
    #expect(await monitor.isAttached("x"))
    files.set(Data("not json".utf8))
    await monitor.reconnect("x")
    #expect(await monitor.settle())
    #expect(!(await monitor.isAttached("x")))
    files.set(codexFile("invented-a"))
    clock.move(monotonic: 60)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await monitor.isAttached("x"))
    #expect(await stat(monitor, "credentialResumes") == 0)
}

@Test func connectCancelsAnInFlightRecheckAndItsResultWins() async {
    let clock = RClock()
    let files = RFiles(codexFile("invented-a"))
    let transport = RTransport(status: 401)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codex])
    #expect(await monitor.settle())
    files.set(codexFile("invented-b"))
    files.block()
    await monitor.manualRefresh()                        // re-check starts and blocks in the read
    #expect(await waitFor { files.readCount() == 2 })
    await monitor.reconnect("x")                         // cancels it; the interactive load starts
    #expect(await waitFor { files.readCount() == 3 })
    files.release(2)
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialRechecks") == 1)
    #expect(await stat(monitor, "credentialResumes") == 0)
    #expect(await transport.seen() == ["invented-a", "invented-b"])
}

private func codexFile(_ token: String, account: String) -> Data {
    Data("{\"tokens\":{\"access_token\":\"\(token)\",\"account_id\":\"\(account)\"}}".utf8)
}

@Test func rejectedTokenStaysRejectedWhenOnlyTheSelectedAccountChanges() async {
    let clock = RClock()
    let files = RFiles(codexFile("invented-a", account: "one"))
    let transport = RTransport(status: 401)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codex])
    #expect(await monitor.settle())
    files.set(codexFile("invented-a", account: "two"))
    await monitor.manualRefresh()
    #expect(await monitor.settle())
    #expect(!(await monitor.isAttached("x")))
    #expect(await stat(monitor, "credentialResumes") == 0)
    #expect(await transport.seen() == ["invented-a"])
}

@Test func sameTokenWithRenewedExpiryLiftsAnExpiryPauseAndKeepsTheNewExpiry() async {
    let clock = RClock()
    let keychain = RKeychain(claudeItem("invented-one", expiresAtSeconds: 1_800_000_100))
    let transport = RTransport()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: RFiles(Data()), keychain: keychain),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([claude])
    #expect(await monitor.settle())
    clock.move(wall: 200, monotonic: 200)
    await monitor.refresh()
    #expect(await message(monitor, "c") == paused)
    keychain.set(claudeItem("invented-one", expiresAtSeconds: 1_800_100_000))
    clock.move(monotonic: 60)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await monitor.isAttached("c"))
    clock.move(monotonic: 31)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await monitor.isAttached("c"))
    #expect(await stat(monitor, "credentialResumes") == 0)
}

@Test func oneProfileFailingLocallyDoesNotStarveAnotherOnTheSameSource() async {
    let clock = RClock()
    let good = Data(#"{"claudeAiOauth":{"accessToken":"invented-one","expiresAt":1900000000000}}"#.utf8)
    let files = RFiles(Data("not json".utf8))
    let a = AccountProfile(id: "a", providerID: "claude", label: "A", source: .claudeFile("/p"),
                           expectedAccountID: AccountID("never"))
    let b = AccountProfile(id: "b", providerID: "claude", label: "B", source: .claudeFile("/p"))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: RTransport(), recheckInterval: 60)
    await monitor.setProfiles([a, b])
    #expect(await monitor.settle())
    files.set(good)
    for _ in 0..<2 {
        clock.move(monotonic: 61)
        await monitor.refresh()
        #expect(await monitor.settle())
    }
    #expect(await monitor.isAttached("b"))
    #expect(!(await monitor.isAttached("a")))
}

// MARK: r5/r6 rules

private enum Step: Sendable { case status(Int, retryAfter: String? = nil), fail }
private struct Unreachable: Error {}

/// Scripted transport: per-bearer response queue (default 200), optional hold of every response.
private actor GTransport: HTTPTransport {
    private var bearers: [String] = []
    private var scripts: [String: [Step]] = [:]
    private var holding = false
    private var holdOnly: Set<String>?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let verified: String?
    init(verified: String? = nil) { self.verified = verified }
    func script(_ bearer: String, _ steps: [Step]) { scripts[bearer] = steps }
    func hold(only bearers: Set<String>? = nil) { holding = true; holdOnly = bearers }
    func releaseFirst() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }
    func release() {
        holding = false
        let pending = waiting; waiting = []
        for continuation in pending { continuation.resume() }
    }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        bearers.append(request.bearer)
        var step = Step.status(200)
        if var queue = scripts[request.bearer], !queue.isEmpty { step = queue.removeFirst(); scripts[request.bearer] = queue }
        if holding, holdOnly?.contains(request.bearer) ?? true { await withCheckedContinuation { waiting.append($0) } }
        guard case .status(let status, let retryAfter) = step else { throw Unreachable() }
        var root: [String: Any] = request.providerID == "codex"
            ? ["rate_limit": ["primary_window": ["used_percent": 30]]]
            : ["limits": [["kind": "session", "percent": 30]]]
        if let verified { root["account_id"] = verified }
        return HTTPResponse(status: status, headers: retryAfter.map { ["retry-after": $0] } ?? [:],
                            body: try! JSONSerialization.data(withJSONObject: root))
    }
    func seen() -> [String] { bearers }
}

private final class PathFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func set(_ path: String, _ data: Data) { lock.lock(); values[path] = data; lock.unlock() }
    func read(path: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return values[path] ?? Data()
    }
}

private func claudeData(_ token: String, expiresAtSeconds: Int = 1_900_000_000) -> Data {
    Data("{\"claudeAiOauth\":{\"accessToken\":\"\(token)\",\"expiresAt\":\(expiresAtSeconds * 1000)}}".utf8)
}

private func anyAttached(_ monitor: Monitor, _ ids: [String]) async -> Bool {
    for id in ids where await monitor.isAttached(id) { return true }
    return false
}
private func allAttached(_ monitor: Monitor, _ ids: [String]) async -> Bool {
    for id in ids where !(await monitor.isAttached(id)) { return false }
    return true
}
private func attached(_ monitor: Monitor, _ id: String) async -> Bool { await monitor.isAttached(id) }

@Test func http401StaysStickyThroughAFailedConnect() async {
    let files = RFiles(codexFile("tok-a"))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codex])
    #expect(await monitor.settle())
    #expect(!(await attached(monitor, "x")))
    files.set(Data("not json".utf8))
    await monitor.reconnect("x")
    #expect(await monitor.settle())
    files.set(codexFile("tok-a"))
    for _ in 0..<2 { await monitor.manualRefresh(); #expect(await monitor.settle()) }
    #expect(!(await attached(monitor, "x")))
    #expect(await stat(monitor, "credentialResumes") == 0)
    #expect(await transport.seen() == ["tok-a"])
}

@Test func aliasPausedForAFailedConnectIsMarkedByASharedRejection() async {
    let clock = RClock()
    let files = RFiles(codexFile("tok-a"))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    await transport.hold()
    let x = AccountProfile(id: "x", providerID: "codex", label: "X", source: .codexFile("/rx"))
    let y = AccountProfile(id: "y", providerID: "codex", label: "Y", source: .codexFile("/rx"))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([x, y])
    #expect(await waitFor { let sent = await transport.seen().count; return await allAttached(monitor, ["x", "y"]) && sent == 1 })
    files.set(Data("not json".utf8))
    await monitor.reconnect("y")
    #expect(await waitFor { await stat(monitor, "credentialFailures") == 1 })
    files.set(codexFile("tok-a"))
    await transport.release()
    #expect(await monitor.settle())
    #expect(!(await anyAttached(monitor, ["x", "y"])))
    for _ in 0..<3 {
        clock.move(monotonic: 1)
        await monitor.manualRefresh()
        #expect(await monitor.settle())
    }
    #expect(!(await anyAttached(monitor, ["x", "y"])))
    #expect(await stat(monitor, "credentialResumes") == 0)
    #expect(await transport.seen() == ["tok-a"])
}

@Test func providerChangeDuringAPendingLoadDiscardsTheRead() async {
    let files = RFiles(codexFile("tok-codex"))
    let transport = GTransport()
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    files.block()
    await monitor.setProfiles([codex])
    #expect(await waitFor { files.readCount() == 1 })
    files.set(claudeData("tok-claude"))
    let asClaude = AccountProfile(id: "x", providerID: "claude", label: "X", source: .claudeFile("/rc"))
    await monitor.setProfiles([asClaude])
    #expect(await waitFor { files.readCount() == 2 })
    files.release(2)
    #expect(await monitor.settle())
    #expect(await monitor.isAttached("x"))
    #expect(await transport.seen() == ["tok-claude"])
}

@Test func setProfilesLoadSuppressesARejectedPairUntilTheTokenChanges() async {
    let files = RFiles(codexFile("tok-a", account: "want"))
    let transport = GTransport(verified: "other")
    let expected = AccountProfile(id: "x", providerID: "codex", label: "Codex", source: .codexFile("/rx"),
                                  expectedAccountID: AccountID("want"))
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([expected])
    #expect(await monitor.settle())
    #expect(await transport.seen() == ["tok-a"])
    var renamed = expected
    renamed.label = "Renamed"
    await monitor.setProfiles([renamed])
    #expect(await monitor.settle())
    await monitor.setProfiles([expected])
    #expect(await monitor.settle())
    #expect(await transport.seen() == ["tok-a"])
    #expect(await message(monitor, "x") == "Configured account does not match session")
    files.set(codexFile("tok-b", account: "want"))
    await monitor.setProfiles([renamed])
    #expect(await monitor.settle())
    #expect(await transport.seen() == ["tok-a", "tok-b"])
}

@Test func creationCarriesTheRetryDateWithTheThrottle() async {
    let clock = RClock()
    let keychain = RKeychain(claudeItem("tok-1", expiresAtSeconds: 1_800_000_100))
    let transport = GTransport()
    await transport.script("tok-1", [.status(429, retryAfter: "600")])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: RFiles(Data()), keychain: keychain),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([claude])
    #expect(await monitor.settle())
    #expect(await monitor.throttleDeadline(for: "c") == 700)
    keychain.set(claudeItem("tok-2", expiresAtSeconds: 1_900_000_000))
    clock.move(wall: 200, monotonic: 61)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect(await stat(monitor, "credentialResumes") == 1)
    #expect(await monitor.throttleDeadline(for: "c") == 700)
    #expect(await message(monitor, "c")?.hasPrefix("Retry after") == true)
    #expect(await transport.seen() == ["tok-1"])
}

@Test func capacityRefusalMovesTheMessageBackToThePauseWording() async {
    let clock = RClock()
    let files = PathFiles()
    let keychain = RKeychain(claudeItem("tok-main", expiresAtSeconds: 1_800_000_001))
    let transport = GTransport()
    var profiles = [claude]
    for index in 0..<255 {
        files.set("/f\(index)", claudeData("tok-f\(index)"))
        profiles.append(AccountProfile(id: "f\(index)", providerID: "claude", label: "F", source: .claudeFile("/f\(index)")))
    }
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                          transport: transport, recheckInterval: 30)
    await monitor.setProfiles(profiles)
    #expect(await monitor.settle())
    await transport.script("tok-main", [.status(429, retryAfter: "600")])
    clock.move(monotonic: 30)
    await monitor.refresh(driver: .internal)
    #expect(await monitor.settle())
    clock.move(wall: 5)
    await monitor.refresh(driver: .internal)
    #expect(await message(monitor, "c") == paused)
    keychain.set(.denied)
    await monitor.manualRefresh()
    #expect(await monitor.settle())
    #expect(await message(monitor, "c") == denied)
    keychain.set(claudeItem("tok-new", expiresAtSeconds: 1_900_000_000))
    await monitor.manualRefresh()
    #expect(await monitor.settle())
    #expect(await message(monitor, "c") == paused)
    #expect(await stat(monitor, "credentialResumes") == 0)
    #expect(!(await transport.seen().contains("tok-new")))
    await monitor.stop()
}

/// A response completing while a Connect holds the only binding paused still sets the entity-level effect.
private func connectHeldDuringRequest(_ step: Step) async -> (throttle: TimeInterval?, requests: Int, attached: Bool) {
    let files = RFiles(codexFile("tok-a"))
    let transport = GTransport()
    await transport.script("tok-a", [step])
    await transport.hold()
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codex])
    _ = await waitFor { await transport.seen().count == 1 }
    files.block()
    await monitor.reconnect("x")
    _ = await waitFor { files.readCount() == 2 }
    await transport.release()
    _ = await waitFor { (await monitor.throttleDeadline(for: "x") ?? 0) > 100 }
    files.release(1)
    _ = await monitor.settle()
    return (await monitor.throttleDeadline(for: "x"), await transport.seen().count, await monitor.isAttached("x"))
}

@Test func throttleSetDuringAConnectPauseSurvivesTheSameTokenLift() async {
    let result = await connectHeldDuringRequest(.status(429, retryAfter: "600"))
    #expect(result.throttle == 700)
    #expect(result.requests == 1)
    #expect(result.attached)
}

@Test func backoffAppliedDuringAConnectPauseSurvivesTheSameTokenLift() async {
    let result = await connectHeldDuringRequest(.fail)
    #expect(result.throttle == 130)
    #expect(result.requests == 1)
    #expect(result.attached)
}

@Test func rejectionAfterAConnectKeptTheSameTokenStillMarksIt() async {
    let files = RFiles(codexFile("tok-a"))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    await transport.hold()
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codex])
    #expect(await waitFor { await transport.seen().count == 1 })
    await monitor.reconnect("x")
    #expect(await waitFor { let read = files.readCount() == 2; return await message(monitor, "x") == nil && read })
    await transport.release()
    #expect(await monitor.settle())
    #expect(!(await attached(monitor, "x")))
    for _ in 0..<2 { await monitor.manualRefresh(); #expect(await monitor.settle()) }
    #expect(!(await attached(monitor, "x")))
    #expect(await stat(monitor, "credentialResumes") == 0)
    #expect(await transport.seen() == ["tok-a"])
}

@Test func connectReadingAWrongAccountAfterARejectionKeepsTheRejection() async {
    let files = RFiles(codexFile("tok-a", account: "want"))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    let expected = AccountProfile(id: "x", providerID: "codex", label: "Codex", source: .codexFile("/rx"),
                                  expectedAccountID: AccountID("want"))
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([expected])
    #expect(await monitor.settle())
    #expect(!(await attached(monitor, "x")))
    files.set(codexFile("tok-a", account: "other"))
    await monitor.reconnect("x")
    #expect(await monitor.settle())
    files.set(codexFile("tok-a", account: "want"))
    for _ in 0..<2 { await monitor.manualRefresh(); #expect(await monitor.settle()) }
    #expect(!(await attached(monitor, "x")))
    #expect(await stat(monitor, "credentialResumes") == 0)
    #expect(await transport.seen() == ["tok-a"])
}

@Test func secondAliasDoesNotResendATokenTheFirstAliasHadRejected() async {
    let clock = RClock()
    let files = RFiles(codexFile("tok-a"))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    await transport.script("tok-b", [.status(401)])
    await transport.hold()
    let x = AccountProfile(id: "x", providerID: "codex", label: "X", source: .codexFile("/rx"))
    let y = AccountProfile(id: "y", providerID: "codex", label: "Y", source: .codexFile("/rx"))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([x, y])
    #expect(await waitFor { let sent = await transport.seen().count; return await allAttached(monitor, ["x", "y"]) && sent == 1 })
    await transport.release()
    #expect(await monitor.settle())
    files.set(codexFile("tok-b"))
    for _ in 0..<3 {
        clock.move(monotonic: 1)
        await monitor.manualRefresh()
        #expect(await monitor.settle())
    }
    #expect(await transport.seen() == ["tok-a", "tok-b"])
    #expect(await stat(monitor, "credentialResumes") == 1)
    #expect(!(await anyAttached(monitor, ["x", "y"])))
}

@Test func anAlternateThatExpiredBeforeTheRejectionCompletesIsNeverDispatched() async {
    let clock = RClock()
    let files = PathFiles()
    files.set("/px", claudeData("tok-a"))
    files.set("/py", claudeData("tok-b", expiresAtSeconds: 1_800_000_100))
    let transport = GTransport(verified: "shared")
    let x = AccountProfile(id: "x", providerID: "claude", label: "X", source: .claudeFile("/px"))
    let y = AccountProfile(id: "y", providerID: "claude", label: "Y", source: .claudeFile("/py"))
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([x, y])
    #expect(await monitor.settle())
    let before = await transport.seen().count
    await transport.script("tok-a", [.status(401)])
    await transport.hold()
    clock.move(monotonic: 31)
    await monitor.refresh()
    #expect(await waitFor { await transport.seen().count == before + 1 })
    #expect(await transport.seen().last == "tok-a")
    clock.move(wall: 200)
    await transport.release()
    #expect(await monitor.settle())
    #expect(await transport.seen().count == before + 1)
    #expect(!(await attached(monitor, "y")))
}

// MARK: r7 rules

private func codexProfile(_ id: String, _ path: String, expected: String? = nil) -> AccountProfile {
    AccountProfile(id: id, providerID: "codex", label: id, source: .codexFile(path), expectedAccountID: expected.map { AccountID($0) })
}

@Test func mismatchAfterAConnectKeepsTheOtherAliasRejection() async {
    let files = RFiles(codexFile("tok-a", account: "one"))
    let transport = GTransport(verified: "other")
    await transport.script("tok-a", [.status(401), .status(200)])
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await transport.hold()
    await monitor.setProfiles([codexProfile("x", "/rx"), codexProfile("y", "/rx")])
    #expect(await waitFor { let sent = await transport.seen().count; return await allAttached(monitor, ["x", "y"]) && sent == 1 })
    await transport.release()
    #expect(await monitor.settle())
    #expect(!(await anyAttached(monitor, ["x", "y"])))
    await monitor.reconnect("x")
    #expect(await monitor.settle())
    #expect(await transport.seen() == ["tok-a", "tok-a"])
    files.set(codexFile("tok-a", account: "two"))
    for _ in 0..<2 { await monitor.manualRefresh(); #expect(await monitor.settle()) }
    #expect(!(await anyAttached(monitor, ["x", "y"])))
    #expect(await transport.seen() == ["tok-a", "tok-a"])
}

private func heldRequestSurvivesRecreation(_ step: Step) async {
    let files = RFiles(codexFile("tok-a"))
    let transport = GTransport()
    await transport.script("tok-a", [step])
    await transport.hold()
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codex])
    #expect(await waitFor { await transport.seen().count == 1 })
    var off = codex
    off.enabled = false
    await monitor.setProfiles([off])
    await monitor.setProfiles([codex])
    #expect(await waitFor { await transport.seen().count == 2 })
    await transport.releaseFirst()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(await transport.seen().count == 2)
    let state = await monitor.presentationActionState(for: "x")
    #expect(state?.hasInFlightRequest == true)
    #expect(state?.authPaused == false)
    #expect(state?.hasCachedSnapshot == false)
    #expect(state?.throttleUntil == 0)
    await transport.release()
    #expect(await monitor.settle())
    #expect(await monitor.isAttached("x"))
    await monitor.stop()
}

@Test func heldFailureIsDiscardedAfterTheProfileIsRecreated() async { await heldRequestSurvivesRecreation(.fail) }
@Test func held401IsDiscardedAfterTheProfileIsRecreated() async { await heldRequestSurvivesRecreation(.status(401)) }
@Test func held200IsDiscardedAfterTheProfileIsRecreated() async { await heldRequestSurvivesRecreation(.status(200)) }

private func noSubscriberCompletionLeavesTheOtherEntityAlone(_ step: Step, moved: TimeInterval) async {
    let clock = RClock()
    let files = PathFiles()
    files.set("/rx", codexFile("tok-a", account: "a"))
    files.set("/ry", codexFile("tok-b", account: "b"))
    let transport = GTransport()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codexProfile("x", "/rx"), codexProfile("y", "/ry")])
    #expect(await monitor.settle())
    await transport.script("tok-a", [step])
    await transport.hold(only: ["tok-a"])
    clock.move(monotonic: 31)
    await monitor.refresh()
    #expect(await waitFor { await transport.seen().count == 4 })
    clock.move(monotonic: moved)
    await monitor.reconnect("x")   // new binding generation: the held completion has no eligible subscriber
    await transport.release()
    #expect(await monitor.settle())
    #expect(await transport.seen().filter { $0 == "tok-b" }.count == 2)
    await monitor.stop()
}

@Test func noSubscriberCompletionSkipsAnEntityThatSucceededWithinTenSeconds() async {
    await noSubscriberCompletionLeavesTheOtherEntityAlone(.status(200), moved: 5)
    await noSubscriberCompletionLeavesTheOtherEntityAlone(.status(401), moved: 5)
    await noSubscriberCompletionLeavesTheOtherEntityAlone(.fail, moved: 5)
}

@Test func noSubscriberCompletionSkipsAnEntityInsideTheThirtySecondCadence() async {
    await noSubscriberCompletionLeavesTheOtherEntityAlone(.status(200), moved: 15)
    await noSubscriberCompletionLeavesTheOtherEntityAlone(.status(401), moved: 15)
    await noSubscriberCompletionLeavesTheOtherEntityAlone(.fail, moved: 15)
}

@Test func wrongAccountConnectKeepsTheRejectionAgainstAnotherProfile() async {
    let files = PathFiles()
    files.set("/rx", codexFile("tok-a", account: "want"))
    files.set("/ry", Data("not json".utf8))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await monitor.setProfiles([codexProfile("x", "/rx", expected: "want"), codexProfile("y", "/ry")])
    #expect(await monitor.settle())
    files.set("/rx", codexFile("tok-a", account: "other"))
    await monitor.reconnect("x")
    #expect(await monitor.settle())
    files.set("/ry", codexFile("tok-a", account: "want"))
    for _ in 0..<2 { await monitor.manualRefresh(); #expect(await monitor.settle()) }
    #expect(!(await attached(monitor, "y")))
    #expect(await transport.seen() == ["tok-a"])
}

@Test func capacityRefusedConnectKeepsTheRejectionAgainstAnotherProfile() async {
    let files = PathFiles()
    files.set("/px", claudeData("tok-a"))
    files.set("/py", Data("not json".utf8))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    var fillers: [AccountProfile] = []
    for index in 0..<255 {
        files.set("/f\(index)", claudeData("tok-f\(index)"))
        fillers.append(AccountProfile(id: "f\(index)", providerID: "claude", label: "F", source: .claudeFile("/f\(index)")))
    }
    func profile(_ id: String, _ path: String) -> AccountProfile {
        AccountProfile(id: id, providerID: "claude", label: id, source: .claudeFile(path))
    }
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await transport.hold(only: ["tok-a"])
    await monitor.setProfiles(fillers + [profile("x", "/px"), profile("x2", "/px"), profile("y", "/py")])
    #expect(await waitFor { let sent = await transport.seen().filter { $0 == "tok-a" }.count; return await allAttached(monitor, ["x", "x2"]) && sent == 1 })
    await transport.release()
    #expect(await monitor.settle())
    #expect(!(await anyAttached(monitor, ["x", "x2"])))
    files.set("/px", claudeData("tok-new"))
    await monitor.reconnect("x")   // the shared entity is not freed and the table is full: refused
    #expect(await monitor.settle())
    #expect(await message(monitor, "x") == "Account capacity reached; retry after throttles expire")
    files.set("/px", claudeData("tok-a"))
    await monitor.setProfiles(fillers + [profile("x", "/px"), profile("y", "/py")])
    #expect(await monitor.settle())
    files.set("/py", claudeData("tok-a"))
    for _ in 0..<2 { await monitor.manualRefresh(); #expect(await monitor.settle()) }
    #expect(!(await attached(monitor, "y")))
    #expect(await transport.seen().filter { $0 == "tok-a" }.count == 1)
    #expect(!(await transport.seen().contains("tok-new")))
    await monitor.stop()
}

@Test func rejectionMarksEveryBindingHoldingTheTokenWhateverItsSource() async {
    let files = PathFiles()
    files.set("/rx", codexFile("tok-a", account: "a"))
    files.set("/ry", codexFile("tok-a", account: "a"))
    let transport = GTransport()
    await transport.script("tok-a", [.status(401)])
    let monitor = Monitor(clock: RClock(), credentials: CredentialStore(files: files, keychain: RKeychain(.notFound)),
                          transport: transport, recheckInterval: 60)
    await transport.hold()
    await monitor.setProfiles([codexProfile("x", "/rx"), codexProfile("y", "/ry")])
    #expect(await waitFor { let sent = await transport.seen().count; return await allAttached(monitor, ["x", "y"]) && sent == 1 })
    await transport.release()
    #expect(await monitor.settle())
    #expect(!(await anyAttached(monitor, ["x", "y"])))
    for _ in 0..<2 { await monitor.manualRefresh(); #expect(await monitor.settle()) }
    #expect(!(await anyAttached(monitor, ["x", "y"])))
    #expect(await transport.seen() == ["tok-a"])
}
