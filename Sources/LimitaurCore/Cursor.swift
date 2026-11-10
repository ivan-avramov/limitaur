import Foundation
import CoreFoundation

public enum CursorOperation: Sendable, Equatable { case currentBillingCycle; case dailySpend(startMs: String, endMs: String) }
public enum CursorAdapterFailure: Error, Sendable, Equatable { case invalidCycle }

private func digits(_ value: String) -> Bool { (1...16).contains(value.utf8.count) && value.utf8.allSatisfy { (0x30...0x39).contains($0) } }
private func jsonObject(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
private func nonBoolean(_ value: Any?) -> NSNumber? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n
}
/// A non-negative integral number no larger than `maximum`.
private func integral(_ value: Any?, maximum: UInt64) -> UInt64? {
    guard let n = nonBoolean(value), let v = UInt64(n.stringValue), v <= maximum else { return nil }
    return v
}
/// Epoch milliseconds as a 1…16-digit string or an integral non-negative number of at most 16 digits.
private func millis(_ value: Any?) -> UInt64? {
    if let s = value as? String { return digits(s) ? UInt64(s) : nil }
    return nonBoolean(value).flatMap { digits($0.stringValue) ? UInt64($0.stringValue) : nil }
}
/// The billing period, start < end and at most 62 days long.
private func cursorPeriod(_ root: [String: Any]) -> (start: UInt64, end: UInt64)? {
    guard let start = millis(root["startDateEpochMillis"]), let end = millis(root["endDateEpochMillis"]),
          start < end, end - start <= 62 * 86_400_000 else { return nil }
    return (start, end)
}

extension CredentialStore {
    /// The cursor-agent access token: printable ASCII, with an optional JWT `exp` in Unix seconds.
    static func cursorCredential(_ data: Data, now: Date) throws -> Credential {
        guard (1...8192).contains(data.count), data.allSatisfy({ (0x21...0x7E).contains($0) }) else { throw CredentialFailure.malformed }
        let token = String(decoding: data, as: UTF8.self)
        var expiry: Date?
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 3 {
            var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while payload.count % 4 != 0 { payload += "=" }
            if let decoded = Data(base64Encoded: payload), let claims = jsonObject(decoded),
               let seconds = integral(claims["exp"], maximum: 8_640_000_000_000) {
                expiry = Date(timeIntervalSince1970: TimeInterval(seconds))
            }
        }
        if let expiry, expiry <= now { throw CredentialFailure.expired }
        return Credential(accessToken: token, selectedAccountID: nil, expiresAt: expiry)
    }
}

extension RequestPolicy {
    /// The fixed URL and JSON body of one Cursor operation; anything else sends nothing.
    static func cursorEndpoint(_ operation: CursorOperation?) throws -> (URL, Data) {
        let base = "https://api2.cursor.sh/aiserver.v1.DashboardService/"
        switch operation {
        case .currentBillingCycle:
            return (URL(string: base + "GetCurrentBillingCycle")!, try JSONSerialization.data(withJSONObject: [String: String]()))
        case .dailySpend(let start, let end):
            guard digits(start), digits(end) else { throw TransportFailure.unsupportedProvider }
            return (URL(string: base + "GetDailySpendByCategory")!,
                    try JSONSerialization.data(withJSONObject: ["periodStartMs": start, "periodEndMs": end], options: [.sortedKeys]))
        case nil: throw TransportFailure.unsupportedProvider
        }
    }
}

public struct CursorUsageAdapter: ProviderAdapter {
    public let id: ProviderID = "cursor"
    public init() {}
    /// Two fixed requests, cycle then spend, combined into one envelope for `UsageDecoder`.
    public func request(credential: Credential, transport: any HTTPTransport) async throws -> HTTPResponse {
        func send(_ operation: CursorOperation) async throws -> HTTPResponse {
            try await transport.send(HTTPRequest(providerID: id, bearer: credential.accessToken,
                                                 accountID: credential.selectedAccountID, cursorOperation: operation))
        }
        let cycle = try await send(.currentBillingCycle)
        guard cycle.status == 200 else { return cycle }
        guard let cycleBody = jsonObject(cycle.body), let period = cursorPeriod(cycleBody) else { throw CursorAdapterFailure.invalidCycle }
        let spend = try await send(.dailySpend(startMs: String(period.start), endMs: String(period.end)))
        guard spend.status == 200 else { return spend }
        guard let spendBody = jsonObject(spend.body) else { throw CursorAdapterFailure.invalidCycle }
        let body = try JSONSerialization.data(withJSONObject: ["billingCycle": cycleBody, "dailySpendByCategory": spendBody])
        return HTTPResponse(status: 200, headers: spend.headers, body: body)
    }
    public func fetch(credential: Credential, accountID: AccountID, accountLabel: String,
                      transport: any HTTPTransport, now: Date) async -> ProviderFetchResult {
        await mappedFetch(credential: credential, accountID: accountID, accountLabel: accountLabel, transport: transport, now: now)
    }
}

extension UsageDecoder {
    static func cursor(_ root: [String: Any], accountID: AccountID, accountLabel: String, now: Date) throws -> UsageSnapshot {
        guard let cycle = root["billingCycle"] as? [String: Any], let period = cursorPeriod(cycle),
              let spend = root["dailySpendByCategory"] as? [String: Any] else { throw DecodeFailure.invalidEnvelope }
        var rows: [Any] = []
        if let value = spend["dailySpend"] {
            guard let list = value as? [Any], list.count <= 4096 else { throw DecodeFailure.invalidEnvelope }
            rows = list
        }
        var cents: UInt64 = 0
        for item in rows {
            guard let row = item as? [String: Any], let day = millis(row["day"]), period.start <= day, day < period.end
            else { throw DecodeFailure.invalidEnvelope }
            if let value = row["spendCents"] {
                guard let amount = integral(value, maximum: UInt64(Int32.max)) else { throw DecodeFailure.invalidEnvelope }
                cents += amount
            }
        }
        var metrics: [UsageMetric] = [], warnings: [String] = []
        var amounts = [InformationalAmount(label: "Spent this cycle", amount: Decimal(cents) / 100, currency: "USD")]
        // Without a positive limit, an absent dailySpend means spend is unknown, not zero.
        let unknownSpend = spend["dailySpend"] == nil
        if let value = spend["effectiveLimitCents"] {
            guard let limit = integral(value, maximum: UInt64(Int64.max)) else { throw DecodeFailure.invalidEnvelope }
            if limit == 0 {
                warnings.append("Spend limit is zero")
                if unknownSpend { amounts = [] }
            } else {
                let reset = Date(timeIntervalSince1970: TimeInterval(period.end) / 1000)
                metrics.append(UsageMetric(id: "spend", label: "Monthly spend",
                                           usedPercent: Double(cents) * 100 / Double(limit), resetsAt: reset))
                amounts.append(InformationalAmount(label: "Spend limit", amount: Decimal(limit) / 100, currency: "USD"))
            }
        } else {
            warnings.append("Spend limit unavailable")
            if unknownSpend { amounts = [] }
        }
        return UsageSnapshot(providerID: "cursor", accountID: accountID, accountLabel: accountLabel, fetchedAt: now,
                             metrics: metrics, informationalAmounts: amounts, partial: !warnings.isEmpty, warnings: warnings)
    }
}
