import Foundation
import Security

// Protocol boundary around the Keychain so tests inject an in-memory fake
// instead of touching the real macOS Keychain (DESIGN.md's Architecture
// Decisions: Keychain, not a config file or environment variable).
protocol SecureKeyStoring: Sendable {
    func read() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case unexpectedData
}

struct KeychainKeyStore: SecureKeyStoring {
    private let service: String
    private let account: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.geoimagesearch.app", account: String = "openai-api-key") {
        self.service = service
        self.account = account
    }

    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        // Update-if-present, add-otherwise: SecItemAdd fails with
        // errSecDuplicateItem on a key rotation (TODOS.md item 3) if an
        // item already exists for this service/account.
        if try read() != nil {
            let status = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        } else {
            var query = baseQuery()
            query[kSecValueData as String] = data
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// UI-presentation state (TODOS.md deferred item 3: missing-key state,
// validation, quota exhaustion). Deliberately NOT a new AppError case —
// AppError's cases are exhaustively switched over elsewhere (ErrorReporter,
// LLMRetryPolicy) and locked by CONTRACT.md, so a quota-exhausted OpenAI
// response (error.code == "insufficient_quota") is still reported as the
// existing AppError.llmRateLimited case while this richer enum drives the
// chat UI's messaging.
enum APIKeyState: Equatable, Sendable {
    case missing
    case invalid
    case valid
    case quotaExhausted
}

protocol APIKeyValidating: Sendable {
    func validate(apiKey: String) async -> APIKeyState
}

// Combines Keychain storage with live validation (a lightweight call through
// OpenAIClient) to produce the state the chat UI presents.
final class APIKeyManager: Sendable {
    private let store: any SecureKeyStoring
    private let validator: any APIKeyValidating

    init(store: any SecureKeyStoring, validator: any APIKeyValidating) {
        self.store = store
        self.validator = validator
    }

    func currentState() async -> APIKeyState {
        guard let key = try? store.read(), !key.isEmpty else { return .missing }
        return await validator.validate(apiKey: key)
    }

    @discardableResult
    func save(_ apiKey: String) async throws -> APIKeyState {
        try store.save(apiKey)
        return await validator.validate(apiKey: apiKey)
    }

    func clear() throws {
        try store.delete()
    }

    func currentKey() throws -> String? {
        try store.read()
    }
}
