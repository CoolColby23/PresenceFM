import Foundation

enum Credential: String, CaseIterable, Sendable {
    case discordApplicationID, lastFMAPIKey, lastFMSecret, lastFMAuthToken, lastFMSessionKey, lastFMUsername, ytmDesktopToken
}

/// Stores credentials without invoking macOS Keychain. Ad-hoc signed builds change
/// identity between releases, which makes Keychain repeatedly request the user's
/// password. This owner-only file works consistently for free, unsigned distribution.
actor CredentialStore {
    private let fileURL: URL
    private var values: [String: String]

    init(baseDirectory: URL? = nil) {
        let directory = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("PresenceFM", isDirectory: true)
        fileURL = directory.appendingPathComponent("credentials.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    func set(_ value: String, for credential: Credential) throws {
        if value.isEmpty { values.removeValue(forKey: credential.rawValue) }
        else { values[credential.rawValue] = value }
        try persist()
    }

    func value(for credential: Credential) -> String? {
        values[credential.rawValue]
    }

    func remove(_ credential: Credential) throws {
        values.removeValue(forKey: credential.rawValue)
        try persist()
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
