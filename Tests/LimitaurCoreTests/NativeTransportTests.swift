import Foundation
import Testing
@testable import LimitaurCore

private final class ProtocolControl: @unchecked Sendable {
    enum Mode { case small, oversized, declaredOversized, unauthorized, forbidden, throttled, pending, redirect }
    private let lock = NSLock()
    private var mode: Mode = .small
    private var starts = 0
    func set(_ value: Mode) { lock.lock(); mode = value; starts = 0; lock.unlock() }
    func current() -> Mode { lock.lock(); defer { lock.unlock() }; return mode }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return starts }
    func started() { lock.lock(); starts += 1; lock.unlock() }
}

private final class FixtureProtocol: URLProtocol {
    static let control = ProtocolControl()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.control.started()
        switch Self.control.current() {
        case .small:
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .oversized:
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 600_000))
            client?.urlProtocol(self, didLoad: Data(repeating: 2, count: 500_000))
            client?.urlProtocolDidFinishLoading(self)
        case .declaredOversized:
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Length": "1048577"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .unauthorized, .forbidden, .throttled:
            let status = Self.control.current() == .unauthorized ? 401 : Self.control.current() == .forbidden ? 403 : 429
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Retry-After": "120"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .pending: break
        case .redirect:
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": "https://example.invalid/"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@Test func productionDelegateOffline() async throws {
    let request = HTTPRequest(providerID: "codex", bearer: "synthetic", accountID: "synthetic")
    let defaultTransport = NativeHTTPTransport(protocolClasses: [FixtureProtocol.self])
    #expect(defaultTransport.policyConfiguration.timeoutIntervalForRequest == 15)
    #expect(defaultTransport.policyConfiguration.timeoutIntervalForResource == 15)
    let transport = NativeHTTPTransport(protocolClasses: [FixtureProtocol.self], resourceDeadline: 0.1)
    let policy = transport.policyConfiguration
    #expect(policy.httpCookieStorage == nil)
    #expect(policy.urlCache == nil)
    #expect(policy.urlCredentialStorage == nil)
    #expect(policy.httpShouldSetCookies == false)
    #expect(policy.timeoutIntervalForRequest == 15)
    #expect(policy.timeoutIntervalForResource == 0.1)
    let built = try RequestPolicy.makeRequest(request)
    #expect(Set((built.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) ==
            Set(["authorization", "accept", "user-agent", "chatgpt-account-id"]))
    FixtureProtocol.control.set(.small)
    let small = try await transport.send(request)
    #expect(small.status == 200)
    #expect(small.body == Data("{}".utf8))
    FixtureProtocol.control.set(.oversized)
    do {
        _ = try await transport.send(request)
        Issue.record("Expected streaming size rejection")
    } catch {
        #expect(error is TransportFailure)
    }
    FixtureProtocol.control.set(.declaredOversized)
    do {
        _ = try await transport.send(request)
        Issue.record("Expected declared size rejection")
    } catch { #expect(error is TransportFailure) }
    for (mode, status) in [(ProtocolControl.Mode.unauthorized, 401), (.forbidden, 403), (.throttled, 429)] {
        FixtureProtocol.control.set(mode)
        let response = try await transport.send(request)
        #expect(response.status == status)
        #expect(response.headers["retry-after"] == "120")
    }
    FixtureProtocol.control.set(.pending)
    do {
        _ = try await transport.send(request)
        Issue.record("Expected resource deadline")
    } catch {
        #expect(error is TransportFailure)
    }
    FixtureProtocol.control.set(.pending)
    let task = Task { try await transport.send(request) }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch {
        #expect(error is TransportFailure)
    }
    FixtureProtocol.control.set(.redirect)
    do {
        _ = try await transport.send(request)
        Issue.record("Expected redirect rejection")
    } catch {
        #expect(FixtureProtocol.control.count() == 1)
        #expect(error as? TransportFailure == .redirect)
    }
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let redirectTask = session.dataTask(with: built)
    let redirect = HTTPURLResponse(url: built.url!, statusCode: 302, httpVersion: nil,
                                   headerFields: ["Location": "https://example.invalid/"])!
    var redirectDecision: URLRequest? = built
    NativeDelegate.shared.urlSession(session, task: redirectTask, willPerformHTTPRedirection: redirect,
                                     newRequest: URLRequest(url: URL(string: "https://example.invalid/")!)) {
        redirectDecision = $0
    }
    #expect(redirectDecision == nil)
}
