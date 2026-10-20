import Foundation

public struct HTTPRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let providerID: ProviderID
    public let bearer: String
    public let accountID: AccountID?
    public init(providerID: ProviderID, bearer: String, accountID: AccountID?) {
        self.providerID = providerID; self.bearer = bearer; self.accountID = accountID
    }
    public var description: String { "HTTPRequest(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: [(label: "value", value: "<redacted>" as Any)], displayStyle: .struct)
    }
}
public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status; self.headers = headers; self.body = body
    }
}
public enum TransportFailure: Error, Sendable, Equatable { case unsupportedProvider, tooLarge, redirect, deadline, cancelled, network }
public protocol HTTPTransport: Sendable { func send(_ request: HTTPRequest) async throws -> HTTPResponse }

public struct BoundedAccumulator: Sendable {
    public static let maximum = 1_048_576
    public private(set) var data = Data()
    public init() {}
    public mutating func append(_ chunk: Data) throws {
        guard chunk.count <= Self.maximum - data.count else { throw TransportFailure.tooLarge }
        data.append(chunk)
    }
}

public enum RequestPolicy {
    public static func url(for provider: ProviderID) throws -> URL {
        switch provider.rawValue {
        case "codex": return URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        case "claude": return URL(string: "https://api.anthropic.com/api/oauth/usage")!
        default: throw TransportFailure.unsupportedProvider
        }
    }
    public static func allowsRedirect(_ response: HTTPURLResponse, to request: URLRequest) -> Bool { false }
    public static func makeRequest(_ input: HTTPRequest) throws -> URLRequest {
        var request = URLRequest(url: try url(for: input.providerID), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer " + input.bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Limitaur/1", forHTTPHeaderField: "User-Agent")
        if input.providerID.rawValue == "codex", let account = input.accountID {
            request.setValue(account.rawValue, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        if input.providerID.rawValue == "claude" {
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
        return request
    }
}

public final class NativeHTTPTransport: NSObject, HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let resourceDeadline: TimeInterval
    var policyConfiguration: URLSessionConfiguration { session.configuration }
    private let lock = NSLock()
    private var states: [Int: State] = [:]
    private struct State {
        var continuation: CheckedContinuation<HTTPResponse, Error>
        var deadlineTask: Task<Void, Never>?
        var response: HTTPURLResponse?
        var body = BoundedAccumulator()
        var failure: Error?
    }
    public init(protocolClasses: [AnyClass]? = nil, resourceDeadline: TimeInterval = 15) {
        let deadline = max(0.001, resourceDeadline)
        self.resourceDeadline = deadline
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = deadline
        if let protocolClasses { config.protocolClasses = protocolClasses }
        self.session = URLSession(configuration: config, delegate: NativeDelegate.shared, delegateQueue: nil)
        super.init()
        NativeDelegate.shared.register(self, session: session)
    }
    deinit { session.invalidateAndCancel(); NativeDelegate.shared.unregister(session: session) }
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = try RequestPolicy.makeRequest(request)
        let holder = TaskHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest)
                let deadline = resourceDeadline
                let watchdog = Task.detached { [weak self, weak task] in
                    try? await Task.sleep(for: .seconds(deadline))
                    guard !Task.isCancelled, let self, let task else { return }
                    self.expire(task)
                }
                lock.lock(); states[task.taskIdentifier] = State(continuation: continuation, deadlineTask: watchdog); lock.unlock()
                holder.install(task)
                task.resume()
            }
        } onCancel: { holder.cancel() }
    }
    fileprivate func response(_ task: URLSessionTask, _ response: URLResponse, completion: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        guard let http = response as? HTTPURLResponse, var state = states[task.taskIdentifier] else {
            lock.unlock()
            completion(.cancel); return
        }
        if (300..<400).contains(http.statusCode) {
            state.failure = TransportFailure.redirect
            states[task.taskIdentifier] = state
            lock.unlock()
            completion(.cancel); return
        }
        if let length = http.value(forHTTPHeaderField: "Content-Length"), let n = Int(length), n > BoundedAccumulator.maximum {
            state.failure = TransportFailure.tooLarge
            states[task.taskIdentifier] = state
            lock.unlock()
            completion(.cancel); return
        }
        state.response = http; states[task.taskIdentifier] = state
        lock.unlock()
        completion(.allow)
    }
    fileprivate func data(_ task: URLSessionTask, _ data: Data) {
        lock.lock()
        guard var state = states[task.taskIdentifier] else { lock.unlock(); return }
        var shouldCancel = false
        do { try state.body.append(data) } catch { state.failure = error; shouldCancel = true }
        states[task.taskIdentifier] = state
        lock.unlock()
        if shouldCancel { task.cancel() }
    }
    fileprivate func complete(_ task: URLSessionTask, error: Error?) {
        lock.lock(); let state = states.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let state else { return }
        state.deadlineTask?.cancel()
        if let failure = state.failure { state.continuation.resume(throwing: failure); return }
        if let error {
            let code = (error as NSError).code
            state.continuation.resume(throwing: code == NSURLErrorCancelled ? TransportFailure.cancelled :
                                      code == NSURLErrorTimedOut ? TransportFailure.deadline : TransportFailure.network)
            return
        }
        guard let response = state.response else { state.continuation.resume(throwing: TransportFailure.network); return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String, let value = item.value as? String { result[key.lowercased()] = value }
        }
        state.continuation.resume(returning: HTTPResponse(status: response.statusCode, headers: headers, body: state.body.data))
    }
    private func expire(_ task: URLSessionTask) {
        lock.lock(); let state = states.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let state else { return }
        state.continuation.resume(throwing: TransportFailure.deadline)
        task.cancel()
    }
}

private final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func install(_ value: URLSessionTask) {
        lock.lock(); task = value; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { value.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let current = task; lock.unlock()
        current?.cancel()
    }
}

private final class WeakOwner {
    weak var value: NativeHTTPTransport?
    init(_ value: NativeHTTPTransport) { self.value = value }
}

final class NativeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = NativeDelegate()
    private let lock = NSLock()
    private var owners: [ObjectIdentifier: WeakOwner] = [:]
    func register(_ owner: NativeHTTPTransport, session: URLSession) {
        lock.lock(); owners[ObjectIdentifier(session)] = WeakOwner(owner); lock.unlock()
    }
    func unregister(session: URLSession) { lock.lock(); owners.removeValue(forKey: ObjectIdentifier(session)); lock.unlock() }
    private func owner(_ session: URLSession) -> NativeHTTPTransport? {
        lock.lock(); defer { lock.unlock() }; return owners[ObjectIdentifier(session)]?.value
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        owner(session)?.response(dataTask, response, completion: completionHandler)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        owner(session)?.data(dataTask, data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        owner(session)?.complete(task, error: error)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(RequestPolicy.allowsRedirect(response, to: request) ? request : nil)
    }
}
