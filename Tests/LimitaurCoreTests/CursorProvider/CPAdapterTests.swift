import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.

private let cpPeriod = CursorOperation.dailySpend(startMs: cpStart, endMs: cpEnd)
private let cpSixtyTwoDays = String(Int64(cpStart)! + 62 * cpDay)

private func cpCall(_ transport: CPTransport, token: String = "invented-cursor-token") async throws -> HTTPResponse {
    try await CursorUsageAdapter().request(credential: cpCredential(token), transport: transport)
}
private func cpInvalidCycle(_ result: Result<HTTPResponse, Error>) async -> (thrown: Bool, requests: Int) {
    let transport = CPTransport(script: [result, cpOK(cpDaily())])
    do { _ = try await cpCall(transport); return (false, await transport.count()) }
    catch { return ((error as? CursorAdapterFailure) == .invalidCycle, await transport.count()) }
}
private func cpObject(_ data: Data) throws -> NSDictionary { try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary) }

@Suite struct CPAdapterTests {
    // R, C4/I4: cycle request first, then the spend request with the parsed period; envelope and second headers returned.
    @Test func requestsInOrderAndReturnsTheEnvelope() async throws {
        let cycle = cpCycle(), daily = cpDaily()
        let transport = CPTransport(script: [cpOK(cycle), .success(cpResponse(200, daily, headers: ["x-second": "yes"]))])
        let response = try await cpCall(transport, token: "invented-bearer-7")
        let requests = await transport.requests()
        #expect(requests.map(\.cursorOperation) == [.currentBillingCycle, cpPeriod])
        #expect(requests.allSatisfy { $0.providerID == "cursor" && $0.bearer == "invented-bearer-7" })
        #expect(response.status == 200 && response.headers == ["x-second": "yes"])
        let envelope = try cpObject(response.body)
        #expect(Set(envelope.allKeys as? [String] ?? []) == ["billingCycle", "dailySpendByCategory"])
        #expect(envelope["billingCycle"] as? NSDictionary == cycle as NSDictionary)
        #expect(envelope["dailySpendByCategory"] as? NSDictionary == daily as NSDictionary)
    }
    // N, I4.3: numeric cycle bounds are sent on as digit strings; zero start and exactly 62 days are accepted.
    @Test func numericBoundsAreForwardedAsDigitStrings() async throws {
        let transport = CPTransport(script: [cpOK(cpCycle(1_700_000_000_000, cpSixtyTwoDays)), cpOK(cpDaily())])
        _ = try await cpCall(transport)
        #expect(await transport.requests().map(\.cursorOperation).last == .dailySpend(startMs: cpStart, endMs: cpSixtyTwoDays))
        let zero = CPTransport(script: [cpOK(cpCycle("0", "1")), cpOK(cpDaily())])
        _ = try await cpCall(zero)
        #expect(await zero.requests().map(\.cursorOperation).last == .dailySpend(startMs: "0", endMs: "1"))
    }
    // R, C4/I4.1: a non-200 first response is returned unchanged and no second request is made.
    @Test(arguments: [(401, [String: String]()), (403, [:]), (429, ["retry-after": "120"]), (500, ["x-a": "b"]), (503, [:])])
    func nonOKFirstResponseIsReturnedUnchanged(_ status: Int, _ headers: [String: String]) async throws {
        let body = Data("first-body-\(status)".utf8)
        let transport = CPTransport(script: [.success(HTTPResponse(status: status, headers: headers, body: body)), cpOK(cpDaily())])
        let response = try await cpCall(transport)
        #expect(response.status == status && response.headers == headers && response.body == body)
        #expect(await transport.count() == 1)
    }
    // N, C4/I4.3: a non-200 second response is returned unchanged after exactly two requests.
    @Test(arguments: [(401, [String: String]()), (429, ["retry-after": "30"]), (500, [:])])
    func nonOKSecondResponseIsReturnedUnchanged(_ status: Int, _ headers: [String: String]) async throws {
        let body = Data("second-body-\(status)".utf8)
        let transport = CPTransport(script: [cpOK(cpCycle()), .success(HTTPResponse(status: status, headers: headers, body: body))])
        let response = try await cpCall(transport)
        #expect(response.status == status && response.headers == headers && response.body == body)
        #expect(await transport.count() == 2)
    }
    // N, C4/I4.2: invalid cycles throw invalidCycle after exactly one request.
    @Test func invalidCyclesThrowAfterOneRequest() async {
        let bodies: [Any] = [
            [String: Any](), ["startDateEpochMillis": cpStart], ["endDateEpochMillis": cpEnd],
            cpCycle(cpEnd, cpStart), cpCycle(cpStart, cpStart), cpCycle(cpStart, String(Int64(cpStart)! + 62 * cpDay + 1)),
            cpCycle("17000x", cpEnd), cpCycle(cpStart, "abc"), cpCycle("", cpEnd), cpCycle(" 1", cpEnd), cpCycle("-1", cpEnd),
            cpCycle("12345678901234567", "99999999999999999"), cpCycle(-1, cpEnd), cpCycle(1.5, cpEnd), cpCycle(true, cpEnd),
            cpCycle(NSNull(), cpEnd), cpCycle([1], cpEnd), [cpCycle()]
        ]
        for body in bodies {
            let outcome = await cpInvalidCycle(.success(cpResponse(200, body)))
            #expect(outcome.thrown && outcome.requests == 1)
        }
        let raw = await cpInvalidCycle(.success(HTTPResponse(status: 200, headers: [:], body: Data("not json".utf8))))
        #expect(raw.thrown && raw.requests == 1)
        let empty = await cpInvalidCycle(.success(HTTPResponse(status: 200, headers: [:], body: Data())))
        #expect(empty.thrown && empty.requests == 1)
    }
    // N, I4.4: a second body that is not a JSON object throws invalidCycle after two requests.
    @Test(arguments: ["[]", "7", "\"x\"", "garbage", ""]) func nonObjectSecondBodyThrows(_ text: String) async {
        let transport = CPTransport(script: [cpOK(cpCycle()), .success(HTTPResponse(status: 200, headers: [:], body: Data(text.utf8)))])
        do { _ = try await cpCall(transport); Issue.record("expected invalidCycle") }
        catch { #expect((error as? CursorAdapterFailure) == .invalidCycle) }
        #expect(await transport.count() == 2)
    }
    // N, C4: a transport error propagates unchanged from either request.
    @Test(arguments: [TransportFailure.network, .deadline, .cancelled, .tooLarge, .redirect])
    func transportErrorsPropagate(_ failure: TransportFailure) async {
        for (script, expected) in [([Result<HTTPResponse, Error>.failure(failure)], 1),
                                   ([cpOK(cpCycle()), .failure(failure)], 2)] {
            let transport = CPTransport(script: script)
            do { _ = try await cpCall(transport); Issue.record("expected \(failure)") }
            catch { #expect((error as? TransportFailure) == failure) }
            #expect(await transport.count() == expected)
        }
    }

    // N, I4 fetch: outcomes map as DirectUsageAdapter maps them; at most two requests and no retries.
    @Test func fetchMapsOutcomes() async {
        func run(_ script: [Result<HTTPResponse, Error>]) async -> (ProviderFetchResult, Int) {
            let transport = CPTransport(script: script + script)
            let result = await CursorUsageAdapter().fetch(credential: cpCredential(), accountID: "acct", accountLabel: "Label",
                                                          transport: transport, now: cpNow)
            return (result, await transport.count())
        }
        let ok = await run([cpOK(cpCycle()), cpOK(cpDaily())])
        if case .success(let snapshot) = ok.0 { #expect(snapshot.providerID == "cursor" && snapshot.metrics.count == 1) } else { Issue.record("expected success") }
        #expect(ok.1 == 2)
        for status in [401, 403] {
            for script in [[Result<HTTPResponse, Error>.success(cpResponse(status))], [cpOK(cpCycle()), .success(cpResponse(status))]] {
                let outcome = await run(script)
                if case .unauthenticated = outcome.0 {} else { Issue.record("expected unauthenticated for \(status)") }
            }
        }
        let throttled = await run([.success(cpResponse(429, headers: ["retry-after": "60"]))])
        if case .throttled(let retry) = throttled.0 { #expect(retry == nil) } else { Issue.record("expected throttled") }
        let unavailable = await run([.success(cpResponse(500))])
        if case .unavailable = unavailable.0 {} else { Issue.record("expected unavailable") }
        let invalid = await run([cpOK(cpCycle(cpEnd, cpStart))])
        if case .failed = invalid.0 {} else { Issue.record("expected failed for invalid cycle") }
        #expect(invalid.1 == 1)
        let broken = await run([.failure(TransportFailure.network)])
        if case .failed = broken.0 {} else { Issue.record("expected failed for transport error") }
        #expect(broken.1 == 1)
        let undecodable = await run([cpOK(cpCycle()), cpOK(cpDaily(rows: [cpRow(cents: -1)]))])
        if case .failed = undecodable.0 {} else { Issue.record("expected failed for undecodable body") }
        #expect(undecodable.1 == 2)
    }

    // R, I4: the default registry resolves cursor to CursorUsageAdapter and keeps Codex and Claude direct.
    @Test func defaultRegistryContainsTheCursorAdapter() {
        let registry = ProviderRegistry()
        #expect(registry.adapter(for: "cursor") is CursorUsageAdapter)
        #expect(registry.adapter(for: "cursor")?.id == "cursor" && CursorUsageAdapter().id == "cursor")
        #expect(registry.adapter(for: "codex") is DirectUsageAdapter && registry.adapter(for: "claude") is DirectUsageAdapter)
        #expect(Set(registry.adapters.keys.map(\.rawValue)) == ["codex", "claude", "cursor"])
    }
    // I, S8: the adapter failure and requests carry no credential text.
    @Test func failureDescriptionsCarryNoToken() async {
        let token = "invented-secret-token-xyz"
        let transport = CPTransport(script: [cpOK(cpCycle(cpEnd, cpStart))])
        do { _ = try await cpCall(transport, token: token) } catch {
            #expect(!String(describing: error).contains(token) && !String(reflecting: error).contains(token))
        }
        for request in await transport.requests() { #expect(!String(describing: request).contains(token)) }
    }
}
