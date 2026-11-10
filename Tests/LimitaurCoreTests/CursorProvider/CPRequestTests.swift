import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline throws unsupportedProvider for cursor),
// I = preserves an invariant, N = exercises new behaviour.

private let cpCycleURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentBillingCycle"
private let cpSpendURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetDailySpendByCategory"
private let cpToken = "invented-cursor-bearer-1"

private func cpHeaders(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) })
}
private func cpBuild(_ operation: CursorOperation?, bearer: String = cpToken, account: AccountID? = nil) throws -> URLRequest {
    try RequestPolicy.makeRequest(HTTPRequest(providerID: "cursor", bearer: bearer, accountID: account, cursorOperation: operation))
}
private func cpBodyObject(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
private func cpThrowsUnsupported(_ operation: CursorOperation?) -> Bool {
    do { _ = try cpBuild(operation); return false } catch { return (error as? TransportFailure) == .unsupportedProvider }
}
private let cpFourHeaders = ["authorization": "Bearer " + cpToken, "content-type": "application/json",
                             "accept": "application/json", "user-agent": "Limitaur/1"]

@Suite struct CPRequestTests {
    // R, C3/I3: billing-cycle request has exact method, URL, four headers and the empty-object body.
    @Test func billingCycleRequestIsExact() throws {
        let request = try cpBuild(.currentBillingCycle, account: "ignored-account")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == cpCycleURL)
        #expect(cpHeaders(request) == cpFourHeaders)
        #expect(request.httpBody == Data("{}".utf8))
        #expect(request.timeoutInterval == 15 && request.cachePolicy == .reloadIgnoringLocalCacheData)
    }
    // R, C3/I3: daily-spend request carries the period as JSON strings and nothing else (no team or user ID).
    @Test func dailySpendRequestIsExact() throws {
        let request = try cpBuild(.dailySpend(startMs: cpStart, endMs: cpEnd))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == cpSpendURL)
        #expect(cpHeaders(request) == cpFourHeaders)
        let body = try cpBodyObject(request)
        #expect(Set(body.keys) == ["periodStartMs", "periodEndMs"])
        #expect(body["periodStartMs"] as? String == cpStart && body["periodEndMs"] as? String == cpEnd)
    }
    // N, I3 boundary: 1...16 ASCII digits are accepted for each end independently, including zeros.
    @Test(arguments: ["0", "7", "0000000000000001", "9999999999999999", "1700000000000"])
    func acceptedPeriodStrings(_ value: String) throws {
        for operation in [CursorOperation.dailySpend(startMs: value, endMs: "1"), .dailySpend(startMs: "1", endMs: value)] {
            let body = try cpBodyObject(try cpBuild(operation))
            #expect(Set(body.values.compactMap { $0 as? String }).contains(value))
        }
    }
    // N, C3/I3: no operation, or a non-digit, empty, over-long or non-ASCII period, throws unsupportedProvider.
    @Test(arguments: ["", "12345678901234567", "-1", "+1", "1.5", " 1", "1 ", "1e3", "12a4", "１２３", "١٢٣", "1\n", "0x10"])
    func rejectedPeriodStrings(_ value: String) {
        #expect(cpThrowsUnsupported(.dailySpend(startMs: value, endMs: "1")))
        #expect(cpThrowsUnsupported(.dailySpend(startMs: "1", endMs: value)))
    }
    @Test func cursorWithoutOperationThrows() { #expect(cpThrowsUnsupported(nil)) }

    // I, C3/C1: Codex and Claude stay GET with no body, no Content-Type, even when an operation is attached.
    @Test(arguments: [nil, CursorOperation.currentBillingCycle, .dailySpend(startMs: "1", endMs: "2")] as [CursorOperation?])
    func codexAndClaudeAreUnchanged(_ operation: CursorOperation?) throws {
        let codex = try RequestPolicy.makeRequest(HTTPRequest(providerID: "codex", bearer: cpToken, accountID: "acct", cursorOperation: operation))
        #expect(codex.httpMethod == "GET" && codex.httpBody == nil && codex.httpBodyStream == nil)
        #expect(codex.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(cpHeaders(codex) == ["authorization": "Bearer " + cpToken, "accept": "application/json",
                                     "user-agent": "Limitaur/1", "chatgpt-account-id": "acct"])
        let claude = try RequestPolicy.makeRequest(HTTPRequest(providerID: "claude", bearer: cpToken, accountID: nil, cursorOperation: operation))
        #expect(claude.httpMethod == "GET" && claude.httpBody == nil && claude.httpBodyStream == nil)
        #expect(claude.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(cpHeaders(claude) == ["authorization": "Bearer " + cpToken, "accept": "application/json",
                                      "user-agent": "Limitaur/1", "anthropic-beta": "oauth-2025-04-20"])
    }
    // I, I3: the new initialiser parameter defaults to nil, and other providers never gain a URL.
    @Test func defaultOperationIsNilAndOtherProvidersStayUnsupported() {
        #expect(HTTPRequest(providerID: "codex", bearer: "b", accountID: nil).cursorOperation == nil)
        let providers: [ProviderID] = ["gemini", "Cursor", "cursor ", ""]
        for provider in providers {
            for operation in [nil, CursorOperation.currentBillingCycle] as [CursorOperation?] {
                let request = HTTPRequest(providerID: provider, bearer: "b", accountID: nil, cursorOperation: operation)
                #expect(throws: TransportFailure.unsupportedProvider) { try RequestPolicy.makeRequest(request) }
            }
        }
    }
    // I, threat: only the two fixed URLs are ever produced, whatever the bearer or account contain.
    @Test func hostileBearerAndAccountCannotChangeTheUrl() throws {
        let hostile = "https://evil.example/path?x=1"
        for operation in [CursorOperation.currentBillingCycle, .dailySpend(startMs: "1", endMs: "2")] {
            let request = try cpBuild(operation, bearer: hostile, account: AccountID(hostile))
            #expect([cpCycleURL, cpSpendURL].contains(request.url?.absoluteString ?? ""))
            #expect(cpHeaders(request)["authorization"] == "Bearer " + hostile)
        }
    }
    // I, C3: redirects are still rejected by policy.
    @Test func policyStillRejectsRedirects() throws {
        let url = try #require(URL(string: cpCycleURL))
        let redirect = try #require(HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://example.invalid/"]))
        #expect(!RequestPolicy.allowsRedirect(redirect, to: URLRequest(url: try #require(URL(string: "https://example.invalid/")))))
    }
}

// MARK: wire behaviour through NativeHTTPTransport with a local URLProtocol fixture (no network)

private final class CPWire: @unchecked Sendable {
    struct Seen { var method: String?, url: String?, headers: [String: String], body: Data? }
    enum Mode { case ok, redirect(Int), oversized }
    private let lock = NSLock(); private var mode = Mode.ok, seen: [Seen] = []
    func reset(_ mode: Mode) { lock.withLock { self.mode = mode; seen = [] } }
    func record(_ value: Seen) { lock.withLock { seen.append(value) } }
    func current() -> Mode { lock.withLock { mode } }
    func requests() -> [Seen] { lock.withLock { seen } }
}
private final class CPProtocol: URLProtocol {
    static let wire = CPWire()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            body = data
        }
        Self.wire.record(.init(method: request.httpMethod, url: request.url?.absoluteString,
                               headers: cpHeaders(request), body: body))
        let url = request.url!
        switch Self.wire.current() {
        case .ok:
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
        case .redirect(let status):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                                  headerFields: ["Location": "https://example.invalid/"])!, cacheStoragePolicy: .notAllowed)
        case .oversized:
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 600_000))
            client?.urlProtocol(self, didLoad: Data(repeating: 2, count: 500_000))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct CPWireTests {
    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await NativeHTTPTransport(protocolClasses: [CPProtocol.self]).send(request)
    }
    // R, C3: both Cursor requests leave the transport as POST with the exact URL, headers and body.
    @Test func cursorRequestsReachTheWireAsSpecified() async throws {
        CPProtocol.wire.reset(.ok)
        let first = try await send(HTTPRequest(providerID: "cursor", bearer: cpToken, accountID: nil, cursorOperation: .currentBillingCycle))
        let second = try await send(HTTPRequest(providerID: "cursor", bearer: cpToken, accountID: nil, cursorOperation: .dailySpend(startMs: "5", endMs: "9")))
        #expect(first.status == 200 && second.status == 200)
        let seen = CPProtocol.wire.requests()
        #expect(seen.map(\.method) == ["POST", "POST"] && seen.map(\.url) == [cpCycleURL, cpSpendURL])
        for item in seen { for (key, value) in cpFourHeaders { #expect(item.headers[key] == value) } }
        #expect(seen[0].body == Data("{}".utf8))
        let spendBody = try #require(seen[1].body)
        let parsed = try #require(JSONSerialization.jsonObject(with: spendBody) as? [String: String])
        #expect(parsed == ["periodStartMs": "5", "periodEndMs": "9"])
    }
    // I, C3: Codex and Claude reach the wire as body-less GETs with no Content-Type.
    @Test(arguments: ["codex", "claude"]) func otherProvidersHaveNoBodyOrContentTypeOnTheWire(_ provider: String) async throws {
        CPProtocol.wire.reset(.ok)
        _ = try await send(HTTPRequest(providerID: ProviderID(provider), bearer: cpToken, accountID: "acct", cursorOperation: .currentBillingCycle))
        let item = try #require(CPProtocol.wire.requests().first)
        #expect(item.method == "GET" && (item.body ?? Data()).isEmpty && item.headers["content-type"] == nil)
        #expect(item.url?.contains("cursor") == false)
    }
    // I, C3: redirects of every POST-relevant kind are rejected and nothing follows them.
    @Test(arguments: [301, 302, 303, 307, 308]) func cursorRedirectsAreRejected(_ status: Int) async throws {
        CPProtocol.wire.reset(.redirect(status))
        await #expect(throws: TransportFailure.redirect) {
            _ = try await send(HTTPRequest(providerID: "cursor", bearer: cpToken, accountID: nil, cursorOperation: .currentBillingCycle))
        }
        #expect(CPProtocol.wire.requests().count == 1)
    }
    // I, I3: the 1 MiB streaming bound applies to a Cursor response.
    @Test func cursorResponsesAreBounded() async {
        CPProtocol.wire.reset(.oversized)
        await #expect(throws: TransportFailure.tooLarge) {
            _ = try await send(HTTPRequest(providerID: "cursor", bearer: cpToken, accountID: nil, cursorOperation: .currentBillingCycle))
        }
    }
    // I, C3: an unsupported Cursor request sends nothing at all.
    @Test func unsupportedCursorRequestSendsNothing() async {
        CPProtocol.wire.reset(.ok)
        await #expect(throws: TransportFailure.unsupportedProvider) {
            _ = try await send(HTTPRequest(providerID: "cursor", bearer: cpToken, accountID: nil))
        }
        await #expect(throws: TransportFailure.unsupportedProvider) {
            _ = try await send(HTTPRequest(providerID: "cursor", bearer: cpToken, accountID: nil, cursorOperation: .dailySpend(startMs: "x", endMs: "1")))
        }
        #expect(CPProtocol.wire.requests().isEmpty)
    }
}
