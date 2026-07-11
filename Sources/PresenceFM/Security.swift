import Foundation
import Security

enum Credential: String, CaseIterable, Sendable {
    case discordApplicationID, lastFMAPIKey, lastFMSecret, lastFMSessionKey, lastFMUsername
}

actor KeychainStore {
    private let service = "fm.presence.PresenceFM"

    func set(_ value: String, for credential: Credential) throws {
        let key = credential.rawValue
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func value(for credential: Credential) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ credential: Credential) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue
        ] as CFDictionary)
    }
}

enum KeychainError: Error { case status(OSStatus) }
