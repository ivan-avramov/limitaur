import Foundation
import Testing
import Darwin
import Security
@testable import LimitaurCore

@Test func thresholds() {
    for (value, expected) in [(0.0, Severity.normal), (80, .normal), (80.01, .warning),
                              (95, .warning), (95.01, .critical), (100, .critical), (125, .critical)] {
        #expect(severity(value) == expected)
    }
    #expect(severity(-1) == .unknown)
    #expect(severity(Double.nan) == .unknown)
    #expect(ringFill(125) == 1)
    #expect(ringFill(-1) == nil)
}

@Test func cadenceRemainsWithinNominalWindow() {
    #expect(nominalPollInterval == 45)
    #expect(pollInterval(jitter: -4) == 45)
    #expect(pollInterval(jitter: 0) == 45)
    #expect(pollInterval(jitter: 1.5) == 46.5)
    #expect(pollInterval(jitter: 100) == 46.5)
    #expect(pollInterval(jitter: .nan) == 45)
    var elapsed = 0.0
    var refreshes = 0
    while elapsed + pollInterval(jitter: 1.5) <= 600 {
        elapsed += pollInterval(jitter: 1.5)
        refreshes += 1
    }
    #expect(refreshes >= 12)
}

@Test func rankingAndExpiry() {
    let now = Date(timeIntervalSince1970: 1_000)
    let a = UsageSnapshot(providerID: "codex", accountID: "one", accountLabel: "One", fetchedAt: now,
                          metrics: [UsageMetric(id: "a", label: "A", usedPercent: 90), UsageMetric(id: "a", label: "A", usedPercent: 90),
                                    UsageMetric(id: "expired", label: "Expired", usedPercent: 99, resetsAt: now)])
    let b = UsageSnapshot(providerID: "claude", accountID: "two", accountLabel: "Two", fetchedAt: now,
                          metrics: [UsageMetric(id: "b", label: "B", usedPercent: 90), UsageMetric(id: "c", label: "C", usedPercent: 60)])
    #expect(rankMetrics([a, b], wallNow: now).map(\.metric.id) == ["b", "a", "c"])
    #expect(rankMetrics([a], wallNow: now.addingTimeInterval(90)).isEmpty)
}

@Test func fixtureContracts() throws {
    let codex = #"{"rate_limit":{"primary_window":{"used_percent":85,"limit_window_seconds":18000,"reset_at":2000}},"additional_rate_limits":null,"credits":{"balance":"2.5","unlimited":false},"rate_limit_reset_credits":{"available_count":3,"applicable_available_count":1}}"#
    let a = try UsageDecoder.decode(provider: "codex", data: Data(codex.utf8))
    #expect(a.metrics.count == 1)
    #expect(a.metrics[0].label == "5h window")
    #expect(a.resetCredits?.availableCount == 3)
    #expect(a.resetCredits?.details == nil)
    let claude = #"{"limits":[{"kind":"weekly_scoped","group":"weekly","percent":98,"is_active":false,"scope":{"model":{"id":"f","display_name":"Fable"}}}],"five_hour":{"utilization":20}}"#
    let b = try UsageDecoder.decode(provider: "claude", data: Data(claude.utf8))
    #expect(b.metrics.count == 1)
    #expect(b.metrics[0].label == "Fable")
    #expect(throws: DecodeFailure.self) { try UsageDecoder.decode(provider: "claude", data: Data("{}".utf8)) }
}

@Test func providerResetCountdownHandlesExtremeAndBoundaryDates() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let source = Data(#"{"rate_limit":{"primary_window":{"used_percent":5,"reset_at":1e30}}}"#.utf8)
    let snapshot = try UsageDecoder.decode(provider: "codex", data: source, now: now)
    let extreme = try #require(snapshot.metrics.first?.resetsAt)
    #expect(resetCountdownText(resetAt: extreme, now: now) == "reset time unavailable")
    #expect(displayableResetDate(extreme) == nil)
    #expect(resetCountdownText(resetAt: now, now: now) == "reset due")
    #expect(resetCountdownText(resetAt: now.addingTimeInterval(-1), now: now) == "reset due")
    #expect(resetCountdownText(resetAt: now.addingTimeInterval(1), now: now) == "in 1m")
    #expect(resetCountdownText(resetAt: now.addingTimeInterval(60), now: now) == "in 1m")
    #expect(resetCountdownText(resetAt: now.addingTimeInterval(3_599), now: now) == "in 60m")
    #expect(resetCountdownText(resetAt: now.addingTimeInterval(3_600), now: now) == "in 1h")
    #expect(resetCountdownText(resetAt: now.addingTimeInterval(3_601), now: now) == "in 2h")
    #expect(resetCountdownText(resetAt: Date(timeIntervalSince1970: .infinity), now: now) == "reset time unavailable")
    #expect(resetCountdownText(resetAt: now, now: Date(timeIntervalSince1970: -Double.infinity)) == "reset time unavailable")
    #expect(resetCountdownText(resetAt: now, now: Date(timeIntervalSince1970: -Double.greatestFiniteMagnitude)) == "reset time unavailable")
}

@Test func credentialAndRequestDescriptionsAndReflectionAreRedacted() {
    let sentinel = "INVENTED_TOKEN_" + UUID().uuidString
    let account = "INVENTED_ACCOUNT_" + UUID().uuidString
    let credential = Credential(accessToken: sentinel, selectedAccountID: AccountID(account), expiresAt: nil)
    let request = HTTPRequest(providerID: "codex", bearer: sentinel, accountID: AccountID(account))
    for value in [String(describing: credential), String(reflecting: credential),
                  String(describing: request), String(reflecting: request)] {
        #expect(value.contains("<redacted>"))
        #expect(!value.contains(sentinel))
        #expect(!value.contains(account))
        #expect(!value.contains(credential.fingerprint))
    }
    var credentialDump = ""
    var requestDump = ""
    dump(credential, to: &credentialDump)
    dump(request, to: &requestDump)
    for value in [credentialDump, requestDump] {
        #expect(value.contains("<redacted>"))
        #expect(!value.contains(sentinel))
        #expect(!value.contains(account))
        #expect(!value.contains(credential.fingerprint))
    }
    #expect(credential.accessToken == sentinel)
    #expect(request.bearer == sentinel)
}

@Test func claudeEqualObservationsIgnoreAdvisoryChanges() throws {
    let source = Data(#"{"limits":[{"kind":"session","group":"all","percent":20,"resets_at":"2030-01-01T00:00:00Z","is_active":true,"display_name":"one"},{"kind":"session","group":"all","percent":20,"resets_at":"2030-01-01T00:00:00Z","is_active":false,"display_name":"two","future_row_field":{"note":"invented"}},{"kind":"weekly","group":"all","percent":50}]}"#.utf8)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = try UsageDecoder.decode(provider: "claude", data: source, now: now)
    #expect(snapshot.metrics.count == 2)
    #expect(snapshot.metrics.first(where: { $0.id.hasPrefix("session:") })?.usedPercent == 20)
    #expect(snapshot.metrics.first(where: { $0.id.hasPrefix("session:") })?.conflictingObservations == nil)
    #expect(!snapshot.partial)
    #expect(rankMetrics([snapshot], wallNow: now).map(\.metric.usedPercent) == [50, 20])
}

@Test func claudeFuturePrefixDoesNotChangeAuthoritativeBranch() throws {
    let modern = Data(#"{"limits":[{"kind":"session","percent":21}],"seven_day_note":"future advisory","five_hour_opaque":true,"five_hour":"wrong legacy type"}"#.utf8)
    let modernSnapshot = try UsageDecoder.decode(provider: "claude", data: modern)
    #expect(modernSnapshot.metrics.map(\.usedPercent) == [21])
    #expect(!modernSnapshot.partial)
    let legacy = Data(#"{"five_hour":{"utilization":42},"seven_day_note":"future advisory","seven_day_scoped":{"utilization":31}}"#.utf8)
    let legacySnapshot = try UsageDecoder.decode(provider: "claude", data: legacy)
    #expect(legacySnapshot.metrics.map(\.usedPercent) == [42, 31])
    #expect(legacySnapshot.metrics.last?.label == "seven_day_scoped")
    #expect(throws: DecodeFailure.self) {
        try UsageDecoder.decode(provider: "claude", data: Data(#"{"seven_day_note":"future advisory"}"#.utf8))
    }
    #expect(throws: DecodeFailure.self) {
        try UsageDecoder.decode(provider: "claude", data: Data(#"{"limits":{},"five_hour":{"utilization":42}}"#.utf8))
    }
    #expect(throws: DecodeFailure.self) {
        try UsageDecoder.decode(provider: "claude", data: Data(#"{"five_hour":"bad","seven_day_note":"future advisory"}"#.utf8))
    }
    #expect(try UsageDecoder.decode(provider: "claude", data: Data(#"{"limits":[],"five_hour":{"utilization":42}}"#.utf8)).metrics.isEmpty)
}

@Test func creditDecimalAndSemanticFlagsRequireFullTypes() throws {
    for (raw, expected) in [(#""0""#, "0"), (#""12.50""#, "12.5"),
                            (#""1e3""#, "1000"), (#""1.25E-2""#, "0.0125")] {
        let snapshot = try UsageDecoder.decode(provider: "codex", data: Data("{\"credits\":{\"balance\":\(raw)}}".utf8))
        #expect(snapshot.balances.first?.remaining == Decimal(string: expected))
        #expect(!snapshot.partial)
    }
    for raw in [#""12.5xyz""#, #""NaN""#, #""1e9999""#, #""1e-9999""#,
                #""999999999999999999999999999999999999999999999999""#] {
        let snapshot = try UsageDecoder.decode(provider: "codex", data: Data("{\"credits\":{\"balance\":\(raw)}}".utf8))
        #expect(snapshot.balances.first?.remaining == nil)
        #expect(snapshot.partial)
    }
    let malformed = try UsageDecoder.decode(provider: "codex", data: Data(#"{"rate_limit":{"primary_window":{"used_percent":30}},"credits":{"unlimited":1,"has_credits":1},"model_usage":{"model-a":{"available":1}}}"#.utf8))
    #expect(malformed.metrics.first?.usedPercent == 30)
    #expect(malformed.balances.first?.unlimited == false)
    #expect(malformed.balances.first?.state == .unknown)
    #expect(malformed.capabilities == ["model-a: availability unknown"])
    #expect(malformed.partial)
    let valid = try UsageDecoder.decode(provider: "codex", data: Data(#"{"credits":{"unlimited":true,"has_credits":false},"model_usage":{"model-a":{"available":false}}}"#.utf8))
    #expect(valid.balances.first?.unlimited == true)
    #expect(valid.capabilities == ["model-a: unavailable"])
    #expect(!valid.partial)
    let noCreditsFlag = try UsageDecoder.decode(provider: "codex", data: Data(#"{"credits":{"has_credits":false,"unlimited":false,"balance":null}}"#.utf8))
    #expect(noCreditsFlag.balances.first?.remaining == nil)
    #expect(noCreditsFlag.balances.first?.state == .unknown)
    #expect(!noCreditsFlag.partial)
    let claudeMalformed = try UsageDecoder.decode(provider: "claude", data: Data(#"{"limits":[{"kind":"session","percent":24}],"spend":{"enabled":1,"percent":75}}"#.utf8))
    #expect(claudeMalformed.metrics.map(\.usedPercent) == [24])
    #expect(claudeMalformed.partial)
    let extraMalformed = try UsageDecoder.decode(provider: "claude", data: Data(#"{"limits":[],"extra_usage":{"is_enabled":1,"utilization":25}}"#.utf8))
    #expect(extraMalformed.metrics.isEmpty)
    #expect(extraMalformed.partial)
    let extraTrue = try UsageDecoder.decode(provider: "claude", data: Data(#"{"limits":[],"extra_usage":{"is_enabled":true,"utilization":25}}"#.utf8))
    #expect(extraTrue.metrics.map(\.usedPercent) == [25])
}

@Test func authoritativeMapsConflictsAndExactMoney() throws {
    let invalidModern = Data(#"{"rateLimitsByLimitId":null,"rateLimits":{"primary":{"usedPercent":90}}}"#.utf8)
    #expect(throws: DecodeFailure.self) { try UsageDecoder.decode(provider: "codex", data: invalidModern) }
    let conflicting = Data(#"{"limits":[{"kind":"session","group":"all","percent":20},{"kind":"session","group":"all","percent":80}]}"#.utf8)
    let rows = try UsageDecoder.decode(provider: "claude", data: conflicting)
    #expect(rows.metrics.count == 1)
    #expect(rows.metrics[0].usedPercent == nil)
    #expect(rows.metrics[0].resetsAt == nil)
    #expect(rows.metrics[0].conflictingObservations?.map(\.usedPercent) == [20, 80])
    #expect(rankMetrics([rows], wallNow: rows.fetchedAt).isEmpty)
    #expect(rows.partial)
    #expect(!rows.warnings.isEmpty)
    let exact = Data(#"{"limits":[],"spend":{"enabled":true,"used":{"amount_minor":9007199254740993,"currency":"ZZZ","exponent":3},"balance":{"amount_minor":1,"currency":"ZZZ","exponent":3}}}"#.utf8)
    let spend = try UsageDecoder.decode(provider: "claude", data: exact)
    #expect(spend.balances.isEmpty)
    #expect(spend.informationalAmounts.first?.amount == Decimal(string: "9007199254740.993"))
    #expect(spend.partial)
    let overflow = Data(#"{"limits":[],"spend":{"enabled":true,"used":{"amount_minor":18446744073709551616,"currency":"ZZZ","exponent":3}}}"#.utf8)
    let unknown = try UsageDecoder.decode(provider: "claude", data: overflow)
    #expect(unknown.informationalAmounts.isEmpty)
    #expect(unknown.partial)
}

@Test func conflictingClaudeScopeKeepsObservationsAndHealthyScopeRanks() throws {
    let source = Data(#"{"limits":[{"kind":"weekly","group":"all","percent":20,"resets_at":"2030-01-01T00:00:00Z"},{"kind":"weekly","group":"all","percent":20,"resets_at":"2030-01-01T00:00:00Z"},{"kind":"weekly","group":"all","percent":80,"resets_at":"2030-01-02T00:00:00Z"},{"kind":"session","group":"all","percent":55}]}"#.utf8)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = try UsageDecoder.decode(provider: "claude", data: source, now: now)
    #expect(snapshot.metrics.count == 2)
    let conflicted = snapshot.metrics.first(where: { $0.id.hasPrefix("weekly:") })
    #expect(conflicted?.usedPercent == nil)
    #expect(conflicted?.conflictingObservations?.map(\.usedPercent) == [20, 80])
    #expect(conflicted?.conflictingObservations?.compactMap(\.resetsAt).count == 2)
    #expect(rankMetrics([snapshot], wallNow: now).map(\.metric.usedPercent) == [55])
}

@Test func secureFileReader() throws {
    guard let root = ProcessInfo.processInfo.environment["LIMITAUR_TEST_ROOT"] ??
            ProcessInfo.processInfo.environment["TMPDIR"], root.hasPrefix("/") else {
        throw CredentialFailure.unreadable
    }
    let folder = URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent("limitaur-reader-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let prefix = ""
    let file = folder.appendingPathComponent(prefix + "auth.json")
    try Data("{}".utf8).write(to: file)
    #expect(try SecureFileReader().read(path: file.path) == Data("{}".utf8))
    let link = folder.appendingPathComponent(prefix + "link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: CredentialFailure.self) { try SecureFileReader().read(path: link.path) }
    let fifo = folder.appendingPathComponent(prefix + "fifo")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    #expect(throws: CredentialFailure.self) { try SecureFileReader().read(path: fifo.path) }
    let oversized = folder.appendingPathComponent(prefix + "oversized")
    try Data(repeating: 0, count: 1_048_577).write(to: oversized)
    #expect(throws: CredentialFailure.self) { try SecureFileReader().read(path: oversized.path) }
    let descriptor = open(file.path, O_RDONLY | O_CLOEXEC)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    let moved = folder.appendingPathComponent(prefix + "moved")
    try FileManager.default.moveItem(at: file, to: moved)
    try Data("new".utf8).write(to: file)
    #expect(try SecureFileReader().readOpenedDescriptor(descriptor) == Data("{}".utf8))
    #expect(try SecureFileReader().read(path: file.path) == Data("new".utf8))
    #expect(throws: CredentialFailure.self) { try SecureFileReader().read(path: folder.path) }
    #expect(throws: CredentialFailure.self) { try SecureFileReader().read(path: folder.appendingPathComponent("missing").path) }
}

@Test func statisticsOutputNeverOverwritesExistingOrCredentialPaths() throws {
    guard let root = ProcessInfo.processInfo.environment["LIMITAUR_TEST_ROOT"] ??
            ProcessInfo.processInfo.environment["TMPDIR"], root.hasPrefix("/") else {
        throw StatisticsOutputFailure.invalidPath
    }
    let folder = URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent("limitaur-statistics-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }

    let existing = folder.appendingPathComponent("existing.json")
    let sentinel = Data("synthetic existing file".utf8)
    try sentinel.write(to: existing)
    #expect(throws: StatisticsOutputFailure.self) {
        try StatisticsOutput(path: existing.path, forbiddenPaths: [])
    }
    #expect(try Data(contentsOf: existing) == sentinel)

    let credentialPath = folder.appendingPathComponent("auth.json")
    #expect(throws: StatisticsOutputFailure.self) {
        try StatisticsOutput(path: credentialPath.path, forbiddenPaths: [credentialPath.path])
    }
    #expect(!FileManager.default.fileExists(atPath: credentialPath.path))

    let link = folder.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: existing)
    #expect(throws: StatisticsOutputFailure.self) {
        try StatisticsOutput(path: link.path, forbiddenPaths: [])
    }
    #expect(try Data(contentsOf: existing) == sentinel)

    let fresh = folder.appendingPathComponent("fresh.json")
    let writer = try StatisticsOutput(path: fresh.path, forbiddenPaths: [credentialPath.path])
    try writer.write(["codex": ["success": 1]])
    #expect(throws: StatisticsOutputFailure.self) {
        try StatisticsOutput(path: fresh.path, forbiddenPaths: [])
    }
    let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: fresh)) as? [String: [String: Int]]
    #expect(parsed?["codex"]?["success"] == 1)
}

private final class RecordingFiles: CredentialFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [String] = []
    let data: Data
    init(_ data: Data) { self.data = data }
    func read(path: String) throws -> Data { lock.lock(); reads.append(path); lock.unlock(); return data }
    func paths() -> [String] { lock.lock(); defer { lock.unlock() }; return reads }
}
private final class RecordingKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var policies: [Bool] = []
    let result: KeychainResult
    init(_ result: KeychainResult) { self.result = result }
    func claudeCredential() -> KeychainResult { claudeCredential(interactive: false) }
    func claudeCredential(interactive: Bool) -> KeychainResult {
        lock.lock(); count += 1; policies.append(interactive); lock.unlock(); return result
    }
    func calls() -> Int { lock.lock(); defer { lock.unlock() }; return count }
    func interactions() -> [Bool] { lock.lock(); defer { lock.unlock() }; return policies }
}

@Test func credentialBoundaryMatrix() throws {
    let sentinel = "INVENTED_CREDENTIAL_SENTINEL_" + UUID().uuidString
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let valid = Data("{\"claudeAiOauth\":{\"accessToken\":\"\(sentinel)\",\"expiresAt\":1800000001000}}".utf8)
    let files = RecordingFiles(valid)
    let keychain = RecordingKeychain(.denied)
    let store = CredentialStore(files: files, keychain: keychain)
    let credential = try store.load(.claudeFile("/invented"), now: now)
    #expect(credential.expiresAt == now.addingTimeInterval(1))
    #expect(keychain.calls() == 0)
    #expect(files.paths() == ["/invented"])
    #expect(!String(describing: credential.selectedAccountID).contains(sentinel))
    let normalized = try UsageDecoder.decode(provider: "claude", data: Data(#"{"limits":[{"kind":"session","percent":12}]}"#.utf8))
    let encodedSnapshot = try JSONEncoder().encode(normalized)
    let preferences = try JSONEncoder().encode([AccountProfile(id: "invented", providerID: "claude", label: "Synthetic", source: .claudeFile("/invented"))])
    #expect(!String(decoding: encodedSnapshot, as: UTF8.self).contains(sentinel))
    #expect(!String(decoding: preferences, as: UTF8.self).contains(sentinel))
    #expect(throws: CredentialFailure.self) { try store.load(.claudeDefaultDiscovery, now: now) }
    #expect(files.paths() == ["/invented"])
    #expect(keychain.interactions() == [false])
    #expect(throws: CredentialFailure.self) { try store.load(.claudeDefaultDiscovery, now: now, interactive: true) }
    #expect(keychain.interactions() == [false, true])
    let fallback = CredentialStore(files: files, keychain: RecordingKeychain(.notFound))
    _ = try fallback.load(.claudeDefaultDiscovery, now: now)
    #expect(files.paths().last == CredentialStore.defaultClaudePath)
    let malformedValues = ["true", "\"1800000001000\"", "-1", "1.5", "18446744073709551616", "18000000000000001"]
    for value in malformedValues {
        let data = Data("{\"claudeAiOauth\":{\"accessToken\":\"\(sentinel)\",\"expiresAt\":\(value)}}".utf8)
        let broken = CredentialStore(files: RecordingFiles(data), keychain: RecordingKeychain(.notFound))
        do { _ = try broken.load(.claudeFile("/invented"), now: now); Issue.record("Malformed expiry accepted") }
        catch { #expect(!String(describing: error).contains(sentinel)) }
    }
    let expired = CredentialStore(files: RecordingFiles(Data("{\"claudeAiOauth\":{\"accessToken\":\"\(sentinel)\",\"expiresAt\":1800000000000}}".utf8)),
                                  keychain: RecordingKeychain(.notFound))
    #expect(throws: CredentialFailure.self) { try expired.load(.claudeFile("/invented"), now: now) }
    let apiOnly = CredentialStore(files: RecordingFiles(Data("{\"OPENAI_API_KEY\":\"\(sentinel)\"}".utf8)),
                                  keychain: RecordingKeychain(.notFound))
    #expect(throws: CredentialFailure.self) { try apiOnly.load(.codexFile("/invented"), now: now) }
    let invalidKeychain = CredentialStore(files: files, keychain: RecordingKeychain(.found(Data("invalid".utf8))))
    #expect(throws: CredentialFailure.self) { try invalidKeychain.load(.claudeDefaultDiscovery, now: now) }
    for content in ["{}", #"{"claudeAiOauth":{}}"#, #"{"claudeAiOauth":{"accessToken":""}}"#,
                    #"{"claudeAiOauth":{"accessToken":"invented","expiresAt":false}}"#] {
        let bad = CredentialStore(files: RecordingFiles(Data(content.utf8)), keychain: RecordingKeychain(.notFound))
        #expect(throws: CredentialFailure.self) { try bad.load(.claudeFile("/invented"), now: now) }
    }
    let absentExpiry = CredentialStore(files: RecordingFiles(Data(#"{"claudeAiOauth":{"accessToken":"invented"}}"#.utf8)),
                                       keychain: RecordingKeychain(.notFound))
    #expect(try absentExpiry.load(.claudeFile("/invented"), now: now).expiresAt == nil)
    let nullExpiry = CredentialStore(files: RecordingFiles(Data(#"{"claudeAiOauth":{"accessToken":"invented","expiresAt":null}}"#.utf8)),
                                     keychain: RecordingKeychain(.notFound))
    #expect(try nullExpiry.load(.claudeFile("/invented"), now: now).expiresAt == nil)
}

@Test func productionReaderMalformedCredentialIsSanitized() throws {
    guard let root = ProcessInfo.processInfo.environment["LIMITAUR_TEST_ROOT"] ??
            ProcessInfo.processInfo.environment["TMPDIR"], root.hasPrefix("/") else {
        throw CredentialFailure.unreadable
    }
    let folder = URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent("limitaur-malformed-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("synthetic.json")
    let sentinel = "INVENTED_SECRET_" + UUID().uuidString
    try Data("{\"claudeAiOauth\":{\"accessToken\":\"\(sentinel)\"".utf8).write(to: path)
    let keychain = RecordingKeychain(.denied)
    let store = CredentialStore(files: SecureFileReader(), keychain: keychain)
    do {
        _ = try store.load(.claudeFile(path.path), now: Date(timeIntervalSince1970: 1_800_000_000))
        Issue.record("Malformed synthetic file was accepted")
    } catch {
        #expect(error is CredentialFailure)
        #expect(String(describing: error) == "malformed")
        #expect(!String(describing: error).contains(sentinel))
    }
    #expect(keychain.calls() == 0)
}

@Test func boundedStreamingAndRedirect() throws {
    var body = BoundedAccumulator()
    try body.append(Data(repeating: 1, count: 600_000))
    try body.append(Data(repeating: 2, count: 448_576))
    #expect(body.data.count == 1_048_576)
    #expect(throws: TransportFailure.self) { try body.append(Data([3])) }
    let response = HTTPURLResponse(url: URL(string: "https://chatgpt.com")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
    #expect(!RequestPolicy.allowsRedirect(response, to: URLRequest(url: URL(string: "https://example.com")!)))
    let request = try RequestPolicy.makeRequest(HTTPRequest(providerID: "codex", bearer: "synthetic", accountID: "a"))
    #expect(request.timeoutInterval == 15)
    #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
    #expect(!(request.url?.absoluteString.contains("synthetic") ?? true))
    #expect(throws: TransportFailure.self) {
        try RequestPolicy.makeRequest(HTTPRequest(providerID: "invented", bearer: "synthetic", accountID: nil))
    }
    let claude = try RequestPolicy.makeRequest(HTTPRequest(providerID: "claude", bearer: "synthetic", accountID: nil))
    #expect(claude.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(Set((claude.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) ==
            Set(["authorization", "accept", "user-agent", "anthropic-beta"]))
}
