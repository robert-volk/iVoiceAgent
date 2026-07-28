import Foundation
import Security

/// Minimal Keychain helper for the secrets this app holds: the Anthropic API
/// key (required — every answer is a Claude API call) and the optional
/// Breeze key (upgrades the spoken voice from the on-device fallback).
/// Never UserDefaults, never in source — see README "What leaves this device".
enum Keychain {
    enum Item: String {
        case anthropicAPIKey = "anthropic-api-key"
        case breezeAPIKey = "breeze-api-key"
    }

    private static let service = "com.robertvolk.voiceagent"

    static func save(_ value: String, for item: Item) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(_ item: Item) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func delete(_ item: Item) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
