import Foundation
import Testing
@testable import LimitaurCore

private final class CountingKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private var result: KeychainResult
    init(_ result: KeychainResult) { self.result = result }
    func claudeCredential() -> KeychainResult { lock.lock(); defer { lock.unlock() }; reads += 1; return result }
    func set(_ value: KeychainResult) { lock.lock(); result = value; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
}
private struct FixedClock: MonitorClock {
    func wallNow() -> Date { now }
    func monotonicNow() -> TimeInterval { 100 }
}
private struct NoFiles: CredentialFileReading {
    func read(path: String) throws -> Data { throw CredentialFailure.missing }
}
private actor ScriptedTransport: HTTPTransport {
    var answers: [HTTPResponse]
    var sent: [HTTPRequest] = []
    init(_ answers: [HTTPResponse]) { self.answers = answers }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sent.append(request)
        guard !answers.isEmpty else { throw TransportFailure.network }
        return answers.removeFirst()
    }
    func operations() -> [CursorOperation?] { sent.map(\.cursorOperation) }
}
private func ok(_ body: String, headers: [String: String] = [:]) -> HTTPResponse { HTTPResponse(status: 200, headers: headers, body: Data(body.utf8)) }
private func jwt(exp: String) -> String {
    let payload = Data(#"{"exp":\#(exp)}"#.utf8).base64EncodedString()
        .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return "eyJhbGciOiJub25lIn0." + payload + ".c2ln"
}
private let now = Date(timeIntervalSince1970: 1_700_100_000)
private let cycle = #"{"startDateEpochMillis":"1700000000000","endDateEpochMillis":"1702592000000"}"#
private let spend = #"{"dailySpend":[{"day":"1700000000000","category":"model-a","spendCents":1200,"totalTokens":"34000"},{"day":"1700086400000","category":"model-b","spendCents":2900,"totalTokens":"81000"}],"categories":["model-a","model-b"],"effectiveLimitCents":500000}"#
private func load(_ token: String) -> Result<Credential, CredentialFailure> {
    CredentialStore(files: NoFiles(), keychain: CountingKeychain(.notFound), cursorKeychain: CountingKeychain(.found(Data(token.utf8))))
        .loadDetailed(.cursorDefaultDiscovery, now: now).result
}
private func failure(_ result: Result<Credential, CredentialFailure>) -> CredentialFailure? {
    if case .failure(let error) = result { return error }; return nil
}
private func envelope(_ spendBody: String, cycleBody: String = cycle) -> Data {
    Data(#"{"billingCycle":\#(cycleBody),"dailySpendByCategory":\#(spendBody)}"#.utf8)
}
private func decode(_ spendBody: String) throws -> UsageSnapshot {
    try UsageDecoder.decode(provider: "cursor", data: envelope(spendBody), now: now)
}

@Test func cursorCredentialReadsJWTExpiryAndRejectsBadTokens() throws {
    let token = jwt(exp: "1800000000")
    let credential = try load(token).get()
    #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(credential.selectedAccountID == nil && credential.accessToken == token)
    #expect(try load("opaque-token").get().expiresAt == nil)
    #expect(try load(jwt(exp: "1.5")).get().expiresAt == nil)
    #expect(try load(jwt(exp: "true")).get().expiresAt == nil)
    #expect(failure(load(jwt(exp: "1600000000"))) == .expired)
    #expect(failure(load("has space")) == .malformed)
    #expect(failure(load(String(repeating: "a", count: 8193))) == .malformed)
    #expect(try load(String(repeating: "a", count: 8192)).get().expiresAt == nil)
    #expect(!String(describing: credential).contains(token))
    #expect(!String(describing: HTTPRequest(providerID: "cursor", bearer: token, accountID: nil)).contains(token))
}

@Test func cursorCredentialKeychainIsolationAndOutcomes() {
    let claude = CountingKeychain(.found(Data("x".utf8))), cursor = CountingKeychain(.notFound)
    let store = CredentialStore(files: NoFiles(), keychain: claude, cursorKeychain: cursor)
    let missing = store.loadDetailed(.cursorDefaultDiscovery, now: now)
    #expect(failure(missing.result) == .missing && claude.count == 0 && cursor.count == 1)
    _ = store.loadDetailed(.claudeDefaultDiscovery, now: now)
    #expect(claude.count == 1 && cursor.count == 1)
    cursor.set(.denied)
    #expect(failure(store.loadDetailed(.cursorDefaultDiscovery, now: now).result) == .keychainDenied)
    cursor.set(.found(Data("token".utf8)))
    #expect(store.loadDetailed(.cursorDefaultDiscovery, now: now).viaKeychain)
    #expect(CredentialSource.cursorDefaultDiscovery.stableID == "cursor:default")
}

@Test func cursorRequestsAreFixedPostsAndOthersUnchanged() throws {
    let cycleRequest = try RequestPolicy.makeRequest(HTTPRequest(providerID: "cursor", bearer: "t", accountID: nil,
                                                                 cursorOperation: .currentBillingCycle))
    #expect(cycleRequest.httpMethod == "POST")
    #expect(cycleRequest.url?.absoluteString == "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentBillingCycle")
    #expect(cycleRequest.httpBody == Data("{}".utf8))
    #expect(cycleRequest.allHTTPHeaderFields == ["Authorization": "Bearer t", "Content-Type": "application/json",
                                                 "Accept": "application/json", "User-Agent": "Limitaur/1"])
    let spendRequest = try RequestPolicy.makeRequest(HTTPRequest(providerID: "cursor", bearer: "t", accountID: nil,
                                                                 cursorOperation: .dailySpend(startMs: "1", endMs: "2")))
    #expect(spendRequest.url?.absoluteString == "https://api2.cursor.sh/aiserver.v1.DashboardService/GetDailySpendByCategory")
    let body = try JSONSerialization.jsonObject(with: spendRequest.httpBody ?? Data()) as? [String: String]
    #expect(body == ["periodStartMs": "1", "periodEndMs": "2"])
    for operation: CursorOperation? in [nil, .dailySpend(startMs: "", endMs: "2"), .dailySpend(startMs: "1x", endMs: "2"),
                                        .dailySpend(startMs: "1", endMs: String(repeating: "9", count: 17))] {
        #expect(throws: TransportFailure.unsupportedProvider) {
            try RequestPolicy.makeRequest(HTTPRequest(providerID: "cursor", bearer: "t", accountID: nil, cursorOperation: operation))
        }
    }
    for provider: ProviderID in ["codex", "claude"] {
        let request = try RequestPolicy.makeRequest(HTTPRequest(providerID: provider, bearer: "t", accountID: "a"))
        #expect(request.httpMethod == "GET" && request.httpBody == nil && request.value(forHTTPHeaderField: "Content-Type") == nil)
    }
}

@Test func cursorAdapterSendsCycleThenSpendAndCombines() async throws {
    let transport = ScriptedTransport([ok(cycle), ok(spend, headers: ["x": "y"])])
    let response = try await CursorUsageAdapter().request(credential: Credential(accessToken: "t", selectedAccountID: nil, expiresAt: nil),
                                                          transport: transport)
    #expect(await transport.operations() == [.currentBillingCycle, .dailySpend(startMs: "1700000000000", endMs: "1702592000000")])
    #expect(response.status == 200 && response.headers == ["x": "y"])
    let snapshot = try UsageDecoder.decode(provider: "cursor", data: response.body, now: now)
    #expect(snapshot.metrics.count == 1)
    #expect(ProviderRegistry().adapter(for: "cursor") is CursorUsageAdapter)
}

@Test func cursorAdapterReturnsNonSuccessAndRejectsBadCycles() async throws {
    let credential = Credential(accessToken: "t", selectedAccountID: nil, expiresAt: nil)
    for status in [401, 429, 500] {
        let transport = ScriptedTransport([HTTPResponse(status: status, headers: ["retry-after": "5"], body: Data("e".utf8))])
        let response = try await CursorUsageAdapter().request(credential: credential, transport: transport)
        #expect(response.status == status && response.headers == ["retry-after": "5"] && response.body == Data("e".utf8))
        #expect(await transport.operations().count == 1)
    }
    let second = ScriptedTransport([ok(cycle), HTTPResponse(status: 503, headers: [:], body: Data())])
    #expect(try await CursorUsageAdapter().request(credential: credential, transport: second).status == 503)
    for bad in ["{}", #"{"startDateEpochMillis":"2","endDateEpochMillis":"1"}"#,
                #"{"startDateEpochMillis":"0","endDateEpochMillis":"5356800001"}"#,
                #"{"startDateEpochMillis":"1a","endDateEpochMillis":"2"}"#] {
        let transport = ScriptedTransport([ok(bad), ok(spend)])
        await #expect(throws: CursorAdapterFailure.invalidCycle) {
            try await CursorUsageAdapter().request(credential: credential, transport: transport)
        }
        #expect(await transport.operations().count == 1)
    }
    await #expect(throws: TransportFailure.network) {
        try await CursorUsageAdapter().request(credential: credential, transport: ScriptedTransport([]))
    }
}

@Test func cursorDecoderTracedExampleAndLimits() throws {
    let snapshot = try decode(spend)
    let metric = try #require(snapshot.metrics.first)
    #expect(abs((metric.usedPercent ?? 0) - 0.82) < 1e-9 && windowCode(for: metric) == "$")
    #expect(metric.resetsAt == Date(timeIntervalSince1970: 1_702_592_000) && !snapshot.partial)
    #expect(snapshot.informationalAmounts == [InformationalAmount(label: "Spent this cycle", amount: 41, currency: "USD"),
                                              InformationalAmount(label: "Spend limit", amount: 5000, currency: "USD")])
    let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!encoded.contains("model-a") && !encoded.contains("34000"))
    #expect(try decode(#"{"effectiveLimitCents":500000}"#).metrics.first?.usedPercent == 0)
    #expect(try decode(#"{"dailySpend":[{"day":"1700000000000","spendCents":410000}],"effectiveLimitCents":500000}"#).metrics.first?.usedPercent == 82)
    #expect(try decode(#"{"dailySpend":[{"day":1700000000000,"spendCents":600000}],"effectiveLimitCents":500000}"#).metrics.first?.usedPercent == 120)
    let known = #""dailySpend":[{"day":"1700000000000","spendCents":1200}]"#
    for (body, warning, labels) in [("{}", "Spend limit unavailable", [String]()),
                                    (#"{"effectiveLimitCents":0}"#, "Spend limit is zero", []),
                                    (#"{"dailySpend":[]}"#, "Spend limit unavailable", ["Spent this cycle"]),
                                    ("{\(known)}", "Spend limit unavailable", ["Spent this cycle"]),
                                    ("{\(known),\"effectiveLimitCents\":0}", "Spend limit is zero", ["Spent this cycle"])] {
        let partial = try decode(body)
        #expect(partial.metrics.isEmpty && partial.partial && partial.warnings == [warning])
        #expect(partial.informationalAmounts.map(\.label) == labels)
    }
    #expect(try decode("{\(known)}").informationalAmounts.first?.amount == 12)
}

@Test func cursorDecoderRejectsInvalidRowsAndSections() {
    let row = { (fields: String) in #"{"dailySpend":[{\#(fields)}],"effectiveLimitCents":500000}"# }
    let many = "[" + Array(repeating: #"{"day":"1700000000000"}"#, count: 4097).joined(separator: ",") + "]"
    for body in [row(#""day":"1702592000000","spendCents":1"#), row(#""day":"1","spendCents":1"#),
                 row(#""day":"1700000000000","spendCents":-1"#), row(#""day":"1700000000000","spendCents":1.5"#),
                 row(#""day":"1700000000000","spendCents":true"#), row(#""day":"1700000000000","spendCents":2147483648"#),
                 row(#""spendCents":1"#), #"{"dailySpend":\#(many),"effectiveLimitCents":1}"#,
                 #"{"dailySpend":{},"effectiveLimitCents":1}"#, #"{"effectiveLimitCents":"5"}"#, "[]"] {
        #expect(throws: DecodeFailure.invalidEnvelope) { try decode(body) }
    }
    #expect(throws: DecodeFailure.invalidEnvelope) {
        try UsageDecoder.decode(provider: "cursor", data: envelope(spend, cycleBody: "[]"), now: now)
    }
}

@Test func cursorProfileRanksPausesOn401AndAliases() async {
    let keychain = CountingKeychain(.found(Data("cursor-token".utf8)))
    let store = CredentialStore(files: NoFiles(), keychain: CountingKeychain(.notFound), cursorKeychain: keychain)
    let transport = ScriptedTransport([ok(cycle), ok(spend)])
    let monitor = Monitor(clock: FixedClock(), credentials: store, transport: transport)
    let profiles = ["a", "b"].map { AccountProfile(id: $0, providerID: "cursor", label: $0, source: .cursorDefaultDiscovery) }
    await monitor.setProfiles(profiles); await monitor.settle()
    let display = await monitor.display()
    #expect(display.selected.count == 1 && display.selected.first?.providerID == "cursor")
    #expect(await transport.operations().count == 2)
    let unauthorized = ScriptedTransport([HTTPResponse(status: 401, headers: [:], body: Data())])
    let paused = Monitor(clock: FixedClock(), credentials: store, transport: unauthorized)
    await paused.setProfiles([profiles[0]]); await paused.settle()
    #expect((await paused.display()).profiles.first?.health == .unauthenticated)
}
