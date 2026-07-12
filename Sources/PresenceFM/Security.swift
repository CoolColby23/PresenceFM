import Foundation
import LocalAuthentication
import Security

enum Credential: String, CaseIterable, Sendable {
    case discordApplicationID, lastFMAPIKey, lastFMSecret, lastFMSessionKey, lastFMUsername
}

actor KeychainStore {
    private let service = "fm.presence.PresenceFM"
    private var cache: [Credential: String] = [:]
    private var loaded: Set<Credential> = []

    func set(_ value: String, for credential: Credential) throws {
        let key = credential.rawValue
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        } else {
            status = updateStatus
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        cache[credential] = value
        loaded.insert(credential)
    }

    func value(for credential: Credential) -> String? {
        if loaded.contains(credential) { return cache[credential] }
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Background startup must never summon a password dialog or stall
            // playback while macOS evaluates an outdated unsigned-build ACL.
            kSecUseAuthenticationContext as String: authenticationContext
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            loaded.insert(credential)
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        cache[credential] = value
        loaded.insert(credential)
        return value
    }

    func remove(_ credential: Credential) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue
        ] as CFDictionary)
        cache.removeValue(forKey: credential)
        loaded.insert(credential)
    }
}

enum KeychainError: Error { case status(OSStatus) }
