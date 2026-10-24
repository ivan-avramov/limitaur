import Foundation
import Darwin
import CryptoKit
import CoreFoundation

public enum CredentialSource: Hashable, Codable, Sendable {
    case codexFile(String)
    case claudeFile(String)
    case claudeDefaultDiscovery
    public var stableID: String {
        switch self {
        case .codexFile(let path): return "codex:" + path
        case .claudeFile(let path): return "claude:" + path
        case .claudeDefaultDiscovery: return "claude:default"
        }
    }
}

public struct AccountProfile: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var providerID: ProviderID
    public var label: String
    public var source: CredentialSource
    public var expectedAccountID: AccountID?
    public var enabled: Bool
    public init(id: String, providerID: ProviderID, label: String, source: CredentialSource,
                expectedAccountID: AccountID? = nil, enabled: Bool = true) {
        self.id = id; self.providerID = providerID; self.label = label; self.source = source
        self.expectedAccountID = expectedAccountID; self.enabled = enabled
    }
}

/// Keep the first configured occurrence of each stable profile ID. A malformed
/// preferences file must not turn an account update into a dictionary trap.
public func normalizedProfiles(_ profiles: [AccountProfile]) -> [AccountProfile] {
    var seen = Set<String>()
    return profiles.filter { seen.insert($0.id).inserted }
}

public struct Credential: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let accessToken: String
    public let selectedAccountID: AccountID?
    public let expiresAt: Date?
    public let fingerprint: String
    public init(accessToken: String, selectedAccountID: AccountID?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.selectedAccountID = selectedAccountID
        self.expiresAt = expiresAt
        self.fingerprint = SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public var description: String { "Credential(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: [(label: "value", value: "<redacted>" as Any)], displayStyle: .struct)
    }
}

public enum CredentialFailure: Error, Sendable { case missing, unreadable, malformed, oversized, expired, keychainDenied, accountMismatch }

public protocol CredentialFileReading: Sendable {
    func read(path: String) throws -> Data
}

public struct SecureFileReader: CredentialFileReading {
    public init() {}
    public func read(path: String) throws -> Data {
        guard path.hasPrefix("/"), !path.isEmpty else { throw CredentialFailure.unreadable }
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CredentialFailure.unreadable }
        defer { close(descriptor) }
        return try readOpenedDescriptor(descriptor)
    }
    func readOpenedDescriptor(_ descriptor: Int32) throws -> Data {
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw CredentialFailure.unreadable
        }
        guard status.st_size >= 0, status.st_size <= 1_048_576 else { throw CredentialFailure.oversized }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = chunk.withUnsafeMutableBytes { buffer in Darwin.read(descriptor, buffer.baseAddress, buffer.count) }
            if count < 0 { throw CredentialFailure.unreadable }
            if count == 0 { return data }
            guard data.count + count <= 1_048_576 else { throw CredentialFailure.oversized }
            data.append(contentsOf: chunk.prefix(count))
        }
    }
}

public enum KeychainReadReason: Sendable, Equatable { case found, notFound, exit(Int32), timeout, signaled, oversized, launch, suspended, busy }
public struct KeychainReadOutcome: Sendable {
    public let result: KeychainResult, reason: KeychainReadReason
    /// True when this read itself suspended the service; the reason stays as classified.
    public let suspendedNow: Bool
    public init(result: KeychainResult, reason: KeychainReadReason, suspendedNow: Bool = false) {
        self.result = result; self.reason = reason; self.suspendedNow = suspendedNow
    }
}

public final class KeychainSuspensions: @unchecked Sendable {
    public static let shared = KeychainSuspensions()
    enum Admission { case run, suspended, busy }
    private struct Entry { var active = false, suspended = false, deferred = false; var interactive = 0 }
    private let condition = NSCondition()
    private var entries: [String: Entry] = [:]
    public init() {}
    public func isSuspended(_ service: String) -> Bool {
        condition.lock(); defer { condition.unlock() }
        return entries[service]?.suspended ?? false
    }
    func admit(_ service: String, interactive: Bool) -> Admission {
        condition.lock(); defer { condition.unlock() }
        if interactive { entries[service, default: Entry()].interactive += 1 }
        else if entries[service]?.interactive ?? 0 > 0 { return .busy }
        // Covers the active read's 5 s timeout, 1 s grace and 2 s drain bound.
        let deadline = Date(timeIntervalSinceNow: 8.5)
        while entries[service]?.active == true {
            if interactive { condition.wait() }
            else if entries[service]?.interactive ?? 0 > 0 { return .busy }
            else if !condition.wait(until: deadline) { break }
        }
        let entry = entries[service, default: Entry()]
        if !interactive {
            if entry.interactive > 0 { return .busy }
            if entry.suspended { return .suspended }
            if entry.active { return .busy }
        }
        entries[service, default: Entry()].active = true
        return .run
    }
    /// Returns true when this non-interactive completion itself suspended the service.
    @discardableResult
    func finish(_ service: String, interactive: Bool, suspend: Bool, clear: Bool = false) -> Bool {
        condition.lock(); defer { condition.unlock() }
        var suspendedNow = false
        entries[service]?.active = false
        if interactive {
            entries[service]?.interactive -= 1
            if clear { entries[service]?.suspended = false }
            else if entries[service]?.deferred == true { entries[service]?.suspended = true }
            entries[service]?.deferred = false
        } else if suspend {
            if entries[service]?.interactive == 0 { entries[service]?.suspended = true; suspendedNow = true }
            else { entries[service]?.deferred = true }
        }
        condition.broadcast()
        return suspendedNow
    }
}

public enum KeychainResult: Sendable { case found(Data), notFound, denied }
public protocol KeychainReading: Sendable {
    func claudeCredential() -> KeychainResult
    func claudeCredential(interactive: Bool) -> KeychainResult
    func claudeCredentialDetailed(interactive: Bool) -> KeychainReadOutcome
}
public extension KeychainReading {
    func claudeCredential(interactive: Bool) -> KeychainResult { claudeCredential() }
    func claudeCredentialDetailed(interactive: Bool) -> KeychainReadOutcome {
        switch claudeCredential(interactive: interactive) {
        case .found(let data): return KeychainReadOutcome(result: .found(data), reason: .found)
        case .notFound: return KeychainReadOutcome(result: .notFound, reason: .notFound)
        case .denied: return KeychainReadOutcome(result: .denied, reason: .launch)
        }
    }
}

public struct SecurityToolKeychainReader: KeychainReading {
    private let runner: any ProcessRunning
    private let service: String, account: String
    private let registry: ProcessRegistry?
    private let suspensions: KeychainSuspensions
    public init(runner: any ProcessRunning = SystemProcessRunner(), service: String = "Claude Code-credentials",
                account: String = NSUserName(), registry: ProcessRegistry? = .shared, suspensions: KeychainSuspensions = .shared) {
        self.runner = runner; self.service = service; self.account = account
        self.registry = registry; self.suspensions = suspensions
    }
    public func claudeCredential() -> KeychainResult { claudeCredentialDetailed(interactive: false).result }
    public func claudeCredential(interactive: Bool) -> KeychainResult { claudeCredentialDetailed(interactive: interactive).result }
    public func claudeCredentialDetailed(interactive: Bool) -> KeychainReadOutcome {
        switch suspensions.admit(service, interactive: interactive) {
        case .suspended: return KeychainReadOutcome(result: .denied, reason: .suspended)
        case .busy: return KeychainReadOutcome(result: .denied, reason: .busy)
        case .run: break
        }
        let run = runner.run(executable: "/usr/bin/security", arguments: ["find-generic-password", "-a", account, "-s", service, "-w"],
                             environment: [:], workingDirectory: nil, timeout: interactive ? 600 : 5,
                             graceAfterTerm: interactive ? 5 : 1, output: .capture(limit: 2_097_154), registry: registry)
        let outcome = Self.classify(run)
        let slow = outcome.reason == .timeout || outcome.reason == .exit(51) || outcome.reason == .exit(128)
        let clear = outcome.reason == .found || outcome.reason == .notFound
        let suspendedNow = suspensions.finish(service, interactive: interactive, suspend: slow, clear: clear)
        return KeychainReadOutcome(result: outcome.result, reason: outcome.reason, suspendedNow: suspendedNow)
    }
    static func classify(_ run: ProcessResult) -> KeychainReadOutcome {
        func denied(_ reason: KeychainReadReason) -> KeychainReadOutcome { KeychainReadOutcome(result: .denied, reason: reason) }
        if run.timedOut { return denied(.timeout) }
        guard let code = run.exitCode else { return denied(run.signaled ? .signaled : .launch) }
        if run.oversized { return denied(.oversized) }
        if code == 44 { return KeychainReadOutcome(result: .notFound, reason: .notFound) }
        if code != 0 { return denied(.exit(code)) }
        var bytes = [UInt8](run.output)
        if bytes.last == 0x0A { bytes.removeLast() }
        func nibble(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: return byte - 0x30
            case 0x61...0x66: return byte - 0x57
            case 0x41...0x46: return byte - 0x37
            default: return nil
            }
        }
        if bytes.count >= 2, bytes.count % 2 == 0, bytes.allSatisfy({ nibble($0) != nil }) {
            bytes = stride(from: 0, to: bytes.count, by: 2).map { nibble(bytes[$0])! << 4 | nibble(bytes[$0 + 1])! }
        }
        if bytes.isEmpty || bytes.count > 1_048_576 { return denied(.oversized) }
        return KeychainReadOutcome(result: .found(Data(bytes)), reason: .found)
    }
}

public struct CredentialStore: Sendable {
    public let files: any CredentialFileReading
    public let keychain: any KeychainReading
    public init(files: any CredentialFileReading = SecureFileReader(), keychain: any KeychainReading = SecurityToolKeychainReader()) {
        self.files = files; self.keychain = keychain
    }
    public func load(_ source: CredentialSource, now: Date, interactive: Bool = false) throws -> Credential {
        try loadDetailed(source, now: now, interactive: interactive).result.get()
    }
    public func loadDetailed(_ source: CredentialSource, now: Date, interactive: Bool = false)
        -> (result: Result<Credential, CredentialFailure>, viaKeychain: Bool, suspended: Bool, busy: Bool) {
        var viaKeychain = false, suspended = false, busy = false
        do {
            let data: Data
            switch source {
            case .codexFile(let path), .claudeFile(let path): data = try files.read(path: path)
            case .claudeDefaultDiscovery:
                let outcome = keychain.claudeCredentialDetailed(interactive: interactive)
                switch outcome.result {
                case .found(let value): data = value; viaKeychain = true
                case .notFound: data = try files.read(path: Self.defaultClaudePath)
                case .denied:
                    suspended = outcome.reason == .suspended || outcome.suspendedNow
                    busy = outcome.reason == .busy
                    throw CredentialFailure.keychainDenied
                }
            }
            return (.success(try parse(data, source: source, now: now)), viaKeychain, suspended, busy)
        } catch {
            return (.failure((error as? CredentialFailure) ?? .unreadable), viaKeychain, suspended, busy)
        }
    }
    private func parse(_ data: Data, source: CredentialSource, now: Date) throws -> Credential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialFailure.malformed
        }
        switch source {
        case .codexFile(_):
            guard let tokens = root["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String, !token.isEmpty,
                  let account = tokens["account_id"] as? String, !account.isEmpty else {
                throw CredentialFailure.malformed
            }
            return Credential(accessToken: token, selectedAccountID: AccountID(account), expiresAt: nil)
        case .claudeFile(_), .claudeDefaultDiscovery:
            guard let oauth = root["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty else { throw CredentialFailure.malformed }
            var expiry: Date?
            if let value = oauth["expiresAt"], !(value is NSNull) {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      let milliseconds = UInt64(number.stringValue),
                      milliseconds <= 8_640_000_000_000_000 else { throw CredentialFailure.malformed }
                expiry = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
            }
            if let expiry, expiry <= now { throw CredentialFailure.expired }
            return Credential(accessToken: token, selectedAccountID: nil, expiresAt: expiry)
        }
    }
    public static var defaultCodexPath: String { NSHomeDirectory() + "/.codex/auth.json" }
    public static var defaultClaudePath: String { NSHomeDirectory() + "/.claude/.credentials.json" }
}
