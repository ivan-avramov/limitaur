import Foundation
import Testing
@testable import LimitaurCore

// Shared helpers for the Cursor provider tests. Every token, response and path is invented and memory-only;
// nothing here touches the network, the real Keychain or a real credential file.
let cpNow = Date(timeIntervalSince1970: 1_800_000_000)
let cpStart = "1700000000000", cpEnd = "1702592000000"
let cpDay: Int64 = 86_400_000
let cpPause = "Session expired or rejected; resumes automatically after the provider app signs in again"

func cpB64URL(_ data: Data, padded: Bool = false) -> String {
    var text = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    if !padded { text = text.replacingOccurrences(of: "=", with: "") }
    return text
}
func cpJWT(payload: String, padded: Bool = false) -> String {
    cpB64URL(Data("{\"alg\":\"none\"}".utf8)) + "." + cpB64URL(Data(payload.utf8), padded: padded) + ".c2lnbmF0dXJl"
}
func cpJWT(exp: Int, salt: String = "") -> String { cpJWT(payload: "{\"exp\":\(exp),\"jti\":\"\(salt)\"}") }
func cpFutureJWT(_ salt: String = "") -> String { cpJWT(exp: 1_800_003_600, salt: salt) }

func cpJSON(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
func cpResponse(_ status: Int = 200, _ object: Any? = nil, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(status: status, headers: headers, body: object.map(cpJSON) ?? Data())
}
func cpCycle(_ start: Any = cpStart, _ end: Any = cpEnd) -> [String: Any] {
    ["startDateEpochMillis": start, "endDateEpochMillis": end]
}
/// proto3 JSON: int64 `day` and `totalTokens` as digit strings, int32 `spendCents` as a number.
func cpRow(day: Any = cpStart, cents: Any? = 1200, category: Any = "model-a", tokens: Any = "34000") -> [String: Any] {
    var row: [String: Any] = ["day": day, "category": category, "totalTokens": tokens]
    if let cents { row["spendCents"] = cents }
    return row
}
func cpTracedRows() -> [[String: Any]] {
    [cpRow(day: cpStart, cents: 1200), cpRow(day: "1700086400000", cents: 2900, category: "model-b", tokens: "81000")]
}
func cpDaily(rows: Any? = cpTracedRows(), limit: Any? = 500_000) -> [String: Any] {
    var object: [String: Any] = [:]
    if let rows { object["dailySpend"] = rows }
    if let limit { object["effectiveLimitCents"] = limit }
    return object
}
func cpEnvelope(cycle: Any? = cpCycle(), daily: Any? = cpDaily()) -> Data {
    var object: [String: Any] = [:]
    if let cycle { object["billingCycle"] = cycle }
    if let daily { object["dailySpendByCategory"] = daily }
    return cpJSON(object)
}
func cpDecode(_ data: Data) throws -> UsageSnapshot {
    try UsageDecoder.decode(provider: "cursor", data: data, accountID: "acct", accountLabel: "Label", now: cpNow)
}
func cpDecodeFails(_ data: Data) -> Bool {
    do { _ = try cpDecode(data); return false } catch { return error is DecodeFailure }
}
func cpCredential(_ token: String = "invented-cursor-token") -> Credential {
    Credential(accessToken: token, selectedAccountID: nil, expiresAt: nil)
}

func cpFound(_ token: String) -> KeychainReadOutcome { KeychainReadOutcome(result: .found(Data(token.utf8)), reason: .found) }
func cpFound(bytes: [UInt8]) -> KeychainReadOutcome { KeychainReadOutcome(result: .found(Data(bytes)), reason: .found) }
let cpNotFound = KeychainReadOutcome(result: .notFound, reason: .notFound)
func cpDenied(_ reason: KeychainReadReason = .exit(51), suspendedNow: Bool = false) -> KeychainReadOutcome {
    KeychainReadOutcome(result: .denied, reason: reason, suspendedNow: suspendedNow)
}

/// Replays outcomes in order and repeats the last one; records the `interactive` flag of every read.
final class CPKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [KeychainReadOutcome], flags: [Bool] = []
    init(_ outcomes: KeychainReadOutcome...) { queue = outcomes }
    func set(_ outcome: KeychainReadOutcome) { lock.withLock { queue = [outcome] } }
    func claudeCredential() -> KeychainResult { claudeCredentialDetailed(interactive: false).result }
    func claudeCredentialDetailed(interactive: Bool) -> KeychainReadOutcome {
        lock.withLock { flags.append(interactive); return queue.count > 1 ? queue.removeFirst() : queue[0] }
    }
    func count() -> Int { lock.withLock { flags.count } }
    func interactions() -> [Bool] { lock.withLock { flags } }
}
final class CPFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock(); private var reads = 0
    func read(path: String) throws -> Data { lock.withLock { reads += 1 }; throw CredentialFailure.missing }
    func count() -> Int { lock.withLock { reads } }
}
func cpClaudeData(token: String, expiresAt: Date) -> Data {
    cpJSON(["claudeAiOauth": ["accessToken": token, "expiresAt": Int64(expiresAt.timeIntervalSince1970 * 1000)]])
}

/// Records every request; answers from a handler given the request and its zero-based index.
actor CPTransport: HTTPTransport {
    private var seen: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest, Int) -> Result<HTTPResponse, Error>
    init(_ handler: @escaping @Sendable (HTTPRequest, Int) -> Result<HTTPResponse, Error>) { self.handler = handler }
    /// Answers the n-th request with the n-th item; further requests fail with `.network`.
    init(script: [Result<HTTPResponse, Error>]) {
        handler = { _, index in index < script.count ? script[index] : .failure(TransportFailure.network) }
    }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let index = seen.count
        seen.append(request)
        return try handler(request, index).get()
    }
    func requests() -> [HTTPRequest] { seen }
    func count() -> Int { seen.count }
}
func cpOK(_ object: Any) -> Result<HTTPResponse, Error> { .success(cpResponse(200, object)) }

final class CPClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock(); private var wall = cpNow, mono: TimeInterval = 100
    func wallNow() -> Date { lock.withLock { wall } }
    func monotonicNow() -> TimeInterval { lock.withLock { mono } }
    func move(wall seconds: TimeInterval = 0, mono elapsed: TimeInterval = 0) {
        lock.withLock { wall.addTimeInterval(seconds); mono += elapsed }
    }
}
final class CPNudger: SessionNudging, @unchecked Sendable {
    private let lock = NSLock(); private var calls = 0
    func nudge() async -> NudgeOutcome { lock.withLock { calls += 1 }; return .ran(exitCode: 0) }
    func waitForCompletion(upTo: TimeInterval) {}
    func count() -> Int { lock.withLock { calls } }
}

/// Healthy answers for every provider: a 30-day cycle around `cpNow`, one row of `cents`, limit 500000 cents.
func cpMonitorAnswers(cents: Int = 4100) -> @Sendable (HTTPRequest, Int) -> Result<HTTPResponse, Error> {
    let start = Int64(cpNow.timeIntervalSince1970 * 1000) - 10 * cpDay, end = start + 30 * cpDay
    return { request, _ in
        guard request.providerID == "cursor", let operation = request.cursorOperation else {
            return cpOK(["limits": [["kind": "session", "percent": 25]]])
        }
        switch operation {
        case .currentBillingCycle: return cpOK(["startDateEpochMillis": String(start), "endDateEpochMillis": String(end)])
        case .dailySpend:
            return cpOK(["dailySpend": [["day": String(start), "spendCents": cents]], "effectiveLimitCents": 500_000])
        }
    }
}
let cpProfile = AccountProfile(id: "cu", providerID: "cursor", label: "Cursor", source: .cursorDefaultDiscovery)
func cpDisplayRow(_ monitor: Monitor, _ id: String = "cu") async -> ProfileDisplay? {
    (await monitor.display()).profiles.first { $0.profile.id == id }
}
func cpStat(_ monitor: Monitor, _ key: String) async -> Int { (await monitor.statistics())["__eligibility"]?[key] ?? 0 }
func cpEventually(_ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    let end = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < end { if await predicate() { return true }; try? await Task.sleep(for: .milliseconds(5)) }
    return await predicate()
}
