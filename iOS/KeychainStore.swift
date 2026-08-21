import Foundation
import Security

actor CompanionKeychain {
    enum Key: String { case lastFMSession, lastFMUsername, deviceID }
    private let service = "fm.presence.companion"

    func value(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for key: Key) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func stableDeviceID() throws -> UUID {
        if let raw = value(for: .deviceID), let id = UUID(uuidString: raw) { return id }
        let id = UUID(); try set(id.uuidString, for: .deviceID); return id
    }
}

enum KeychainError: LocalizedError { case status(OSStatus); var errorDescription: String? { "Keychain operation failed." } }
