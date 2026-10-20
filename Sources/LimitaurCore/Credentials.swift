import Foundation
import Darwin
import Security
import CryptoKit
import CoreFoundation
import LocalAuthentication

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

public enum KeychainResult: Sendable { case found(Data), notFound, denied }
public protocol KeychainReading: Sendable {
    func claudeCredential() -> KeychainResult
    func claudeCredential(interactive: Bool) -> KeychainResult
}
public extension KeychainReading {
    func claudeCredential(interactive: Bool) -> KeychainResult { claudeCredential() }
}

protocol KeychainOperations: Sendable {
    func interactionAllowed() -> (OSStatus, Bool)
    func setInteractionAllowed(_ allowed: Bool) -> OSStatus
    func copyMatching(_ query: CFDictionary) -> (OSStatus, Data?)
}

struct SecurityKeychainOperations: KeychainOperations {
    func interactionAllowed() -> (OSStatus, Bool) {
        var allowed = DarwinBoolean(false)
        let status = SecKeychainGetUserInteractionAllowed(&allowed)
        return (status, allowed.boolValue)
    }
    func setInteractionAllowed(_ allowed: Bool) -> OSStatus {
        SecKeychainSetUserInteractionAllowed(allowed)
    }
    func copyMatching(_ query: CFDictionary) -> (OSStatus, Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        return (status, item as? Data)
    }
}

public struct SystemKeychainReader: KeychainReading {
    private static let policyLock = NSLock()
    private let operations: any KeychainOperations
    public init() { operations = SecurityKeychainOperations() }
    init(operations: any KeychainOperations) { self.operations = operations }
    public func claudeCredential() -> KeychainResult { claudeCredential(interactive: false) }
    public func claudeCredential(interactive: Bool) -> KeychainResult {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let context = LAContext()
        context.interactionNotAllowed = !interactive
        query[kSecUseAuthenticationContext as String] = context
        // The classic Keychain path can ignore LAContext. Serialize the process-wide
        // interaction policy. Every background query sets false or returns denied.
        Self.policyLock.lock()
        defer { Self.policyLock.unlock() }
        let (policyStatus, previous) = operations.interactionAllowed()
        guard policyStatus == errSecSuccess else { return .denied }
        guard operations.setInteractionAllowed(interactive) == errSecSuccess else {
            _ = operations.setInteractionAllowed(false)
            return .denied
        }
        let (status, data) = operations.copyMatching(query as CFDictionary)
        guard operations.setInteractionAllowed(previous) == errSecSuccess else {
            // A failed restore is never reported as a successful credential read.
            // Leave the process noninteractive if the OS permits the best-effort reset.
            _ = operations.setInteractionAllowed(false)
            return .denied
        }
        if status == errSecItemNotFound { return .notFound }
        guard status == errSecSuccess, let data, data.count <= 1_048_576 else {
            return .denied
        }
        return .found(data)
    }
}

public struct CredentialStore: Sendable {
    public let files: any CredentialFileReading
    public let keychain: any KeychainReading
    public init(files: any CredentialFileReading = SecureFileReader(), keychain: any KeychainReading = SystemKeychainReader()) {
        self.files = files; self.keychain = keychain
    }
    public func load(_ source: CredentialSource, now: Date, interactive: Bool = false) throws -> Credential {
        let data: Data
        switch source {
        case .codexFile(let path), .claudeFile(let path): data = try files.read(path: path)
        case .claudeDefaultDiscovery:
            switch keychain.claudeCredential(interactive: interactive) {
            case .found(let value): data = value
            case .notFound: data = try files.read(path: Self.defaultClaudePath)
            case .denied: throw CredentialFailure.keychainDenied
            }
        }
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
