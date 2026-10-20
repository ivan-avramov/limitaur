import Foundation

public enum ProviderFetchResult: Sendable {
    case success(UsageSnapshot)
    case unauthenticated
    case unavailable
    case throttled(retryAt: Date?)
    case failed
}

public protocol ProviderAdapter: Sendable {
    var id: ProviderID { get }
    func request(credential: Credential, transport: any HTTPTransport) async throws -> HTTPResponse
    func fetch(credential: Credential, accountID: AccountID, accountLabel: String,
               transport: any HTTPTransport, now: Date) async -> ProviderFetchResult
}

public struct DirectUsageAdapter: ProviderAdapter {
    public let id: ProviderID
    public init(id: ProviderID) { self.id = id }
    public func request(credential: Credential, transport: any HTTPTransport) async throws -> HTTPResponse {
        try await transport.send(HTTPRequest(providerID: id, bearer: credential.accessToken,
                                             accountID: credential.selectedAccountID))
    }
    public func fetch(credential: Credential, accountID: AccountID, accountLabel: String,
                      transport: any HTTPTransport, now: Date) async -> ProviderFetchResult {
        do {
            let response = try await request(credential: credential, transport: transport)
            switch response.status {
            case 200:
                guard let snapshot = try? UsageDecoder.decode(provider: id, data: response.body, accountID: accountID,
                                                               accountLabel: accountLabel, now: now) else { return .failed }
                return .success(snapshot)
            case 401, 403: return .unauthenticated
            case 429: return .throttled(retryAt: nil)
            default: return .unavailable
            }
        } catch { return .failed }
    }
}

public struct ProviderRegistry: Sendable {
    public let adapters: [ProviderID: any ProviderAdapter]
    public init(_ providers: [any ProviderAdapter] = [DirectUsageAdapter(id: "codex"), DirectUsageAdapter(id: "claude")]) {
        self.adapters = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }
    public func adapter(for id: ProviderID) -> (any ProviderAdapter)? { adapters[id] }
}
