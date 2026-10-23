import Foundation
import Testing
import LimitaurCore

// All credentials and responses in this directory are invented, local fixtures.
final class TFClock: MonitorClock, @unchecked Sendable {
    static let origin: TimeInterval = 1_000
    static let wallOrigin = Date(timeIntervalSince1970: 1_800_000_000)
    private let lock = NSLock()
    private var age: TimeInterval = 0
    private var wallOffset: TimeInterval = 0
    func wallNow() -> Date {
        lock.lock(); defer { lock.unlock() }
        return Self.wallOrigin.addingTimeInterval(age + wallOffset)
    }
    func monotonicNow() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }; return Self.origin + age
    }
    func set(_ age: TimeInterval, wallOffset: TimeInterval = 0) {
        lock.lock(); self.age = age; self.wallOffset = wallOffset; lock.unlock()
    }
}

struct TFFiles: CredentialFileReading {
    let sources: [String: Data]
    func read(path: String) throws -> Data {
        guard let data = sources[path] else { throw CredentialFailure.missing }
        return data
    }
}

struct TFKeychain: KeychainReading {
    let result: KeychainResult
    func claudeCredential() -> KeychainResult { result }
}

actor TFTransport: HTTPTransport {
    private var pending: [(ProviderID, CheckedContinuation<HTTPResponse, Error>?)] = []
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending.append((request.providerID, continuation))
        }
    }
    func count() -> Int { pending.count }
    func provider(at index: Int) -> ProviderID? {
        pending.indices.contains(index) ? pending[index].0 : nil
    }
    func wait(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while pending.count < count && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return pending.count >= count
    }
    func answer(_ index: Int, _ response: HTTPResponse) {
        guard pending.indices.contains(index), let continuation = pending[index].1 else { return }
        pending[index].1 = nil
        continuation.resume(returning: response)
    }
    func fail(_ index: Int) {
        guard pending.indices.contains(index), let continuation = pending[index].1 else { return }
        pending[index].1 = nil
        continuation.resume(throwing: TransportFailure.network)
    }
    func finish() { for index in pending.indices { fail(index) } }
}

func tfResponse(_ status: Int, retry: String? = nil, body: String = "{}") -> HTTPResponse {
    HTTPResponse(status: status, headers: retry.map { ["retry-after": $0] } ?? [:], body: Data(body.utf8))
}

func tfSuccess(_ percent: Int = 88, resetAge: Int? = nil, verified: Bool = false) -> HTTPResponse {
    let reset = resetAge.map { ",\"reset_at\":\(1_800_000_000 + $0)" } ?? ""
    let account = verified ? "\"account_id\":\"shared\"," : ""
    return tfResponse(200, body: "{\(account)\"rate_limit\":{\"primary_window\":{\"used_percent\":\(percent)\(reset)}}}")
}

func tfToken(_ suffix: String = "one") -> Data {
    Data("{\"tokens\":{\"access_token\":\"synthetic-\(suffix)\",\"account_id\":\"shared\"}}".utf8)
}

func tfProfile(_ id: String = "one", path: String = "/tf/one") -> AccountProfile {
    AccountProfile(id: id, providerID: "codex", label: id, source: .codexFile(path))
}

func tfHTTPDate(_ age: TimeInterval) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.string(from: TFClock.wallOrigin.addingTimeInterval(age))
}

struct TFRig: Sendable {
    let clock = TFClock()
    let transport = TFTransport()
    let monitor: Monitor
    init(sources: [String: Data] = ["/tf/one": tfToken()], keychain: KeychainResult = .notFound) {
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: TFFiles(sources: sources),
                          keychain: TFKeychain(result: keychain)), transport: transport)
    }
    func start(_ profiles: [AccountProfile] = [tfProfile()], response: HTTPResponse = tfSuccess()) async throws {
        await monitor.setProfiles(profiles)
        try #require(await transport.wait(1), "Initial request must start")
        await transport.answer(0, response)
        try #require(await monitor.settle(), "Initial success must settle")
        #expect(!(await monitor.display()).selected.isEmpty)
    }
    func reply(at age: TimeInterval, index: Int = 1, _ response: HTTPResponse?) async throws {
        clock.set(age)
        await monitor.refresh()
        try #require(await transport.wait(index + 1), "Scheduled request must start")
        if let response { await transport.answer(index, response) }
        else { await transport.fail(index) }
        try #require(await monitor.settle(), "Response must settle")
    }
    func retained(retry: String = "55", at age: TimeInterval = 45,
                  response: HTTPResponse = tfSuccess()) async throws {
        try await start(response: response)
        try await reply(at: age, tfResponse(429, retry: retry))
    }
    func display(at age: TimeInterval) async -> MonitorDisplay {
        clock.set(age); return await monitor.display()
    }
    func project(_ display: MonitorDisplay, at age: TimeInterval,
                 observations: inout [Int: SnapshotExpirations]) -> PresentationState {
        projectDisplay(display, count: 3, wallNow: TFClock.wallOrigin.addingTimeInterval(age),
                       monotonicNow: TFClock.origin + age, observations: &observations)
    }
    func close() async { await monitor.stop(); await transport.finish() }
}
