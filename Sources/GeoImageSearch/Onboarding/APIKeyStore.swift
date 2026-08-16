import Foundation
import Security

// DESIGN.md's Architecture Decisions: "LLM API key storage: macOS Keychain
// (Security framework), not a config file or environment variable." This is
// the first Keychain code in the repo — the onboarding API key step is what
// actually needs it.
protocol APIKeyStoring: Sendable {
    func save(_ key: String) throws
    func load() -> String?
    func delete() throws
}

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
}

final class KeychainAPIKeyStore: APIKeyStoring, Sendable {
    private let service: String
    private let account = "openai-api-key"

    init(service: String = "com.geoimagesearch.app.openai-api-key") {
        self.service = service
    }

    func save(_ key: String) throws {
        let data = Data(key.utf8)
        var query = baseQuery
        if load() != nil {
            let update: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
        } else {
            query[kSecValueData as String] = data
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
        }
    }

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
