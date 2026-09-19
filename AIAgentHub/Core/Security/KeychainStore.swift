import Foundation
import Security

/// Thin, typed wrapper over the iOS Keychain. Tokens only — never passwords.
enum KeychainStore {

    enum Key: String, CaseIterable {
        case huggingFaceToken = "hf.token"
        case githubToken = "github.token"
        case openAIKey = "openai.key"
        case companionKey = "companion.psk"

        var displayName: String {
            switch self {
            case .huggingFaceToken: return "Hugging Face token"
            case .githubToken: return "GitHub token"
            case .openAIKey: return "OpenAI-compatible key"
            case .companionKey: return "Companion pairing key"
            }
        }
    }

    private static let service = "app.aiagenthub.secrets"

    @discardableResult
    static func set(_ value: String?, for key: Key) -> Bool {
        guard let value, !value.isEmpty else { return delete(key) }
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func has(_ key: Key) -> Bool { get(key) != nil }

    static func wipeAll() { Key.allCases.forEach { delete($0) } }
}
