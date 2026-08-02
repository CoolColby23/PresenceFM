import CryptoKit
import Foundation
import Security

struct EncryptedBackupEnvelope: Codable, Equatable {
    static let currentVersion = 1
    let version: Int
    let salt: Data
    let iterations: Int
    let sealedData: Data
}

enum SecureBackupError: LocalizedError {
    case passphraseTooShort
    case invalidEnvelope
    case unsupportedVersion(Int)
    case iCloudUnavailable
    case noBackup

    var errorDescription: String? {
        switch self {
        case .passphraseTooShort: "Use a passphrase with at least 12 characters."
        case .invalidEnvelope: "The encrypted backup or passphrase is invalid."
        case .unsupportedVersion(let version): "Encrypted backup version \(version) is not supported."
        case .iCloudUnavailable:
            "Encrypted iCloud backup is unavailable in this build. Sign in to iCloud and use a build with an iCloud container entitlement."
        case .noBackup: "No encrypted PresenceFM backup was found in iCloud Drive."
        }
    }
}

enum SecureBackupService {
    static let iterations = 120_000

    static func encrypt(_ plaintext: Data, passphrase: String) throws -> Data {
        guard passphrase.count >= 12 else { throw SecureBackupError.passphraseTooShort }
        var salt = Data(count: 16)
        let result = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard result == errSecSuccess else { throw SecureBackupError.invalidEnvelope }
        let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw SecureBackupError.invalidEnvelope }
        return try JSONEncoder().encode(
            EncryptedBackupEnvelope(
                version: EncryptedBackupEnvelope.currentVersion,
                salt: salt,
                iterations: iterations,
                sealedData: combined
            )
        )
    }

    static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        guard passphrase.count >= 12 else { throw SecureBackupError.passphraseTooShort }
        let envelope: EncryptedBackupEnvelope
        do { envelope = try JSONDecoder().decode(EncryptedBackupEnvelope.self, from: data) } catch { throw SecureBackupError.invalidEnvelope }
        guard envelope.version == EncryptedBackupEnvelope.currentVersion else {
            throw SecureBackupError.unsupportedVersion(envelope.version)
        }
        guard envelope.iterations >= 100_000, envelope.iterations <= 2_000_000, envelope.salt.count >= 16 else {
            throw SecureBackupError.invalidEnvelope
        }
        let key = deriveKey(
            passphrase: passphrase,
            salt: envelope.salt,
            iterations: envelope.iterations
        )
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealedData), using: key)
        } catch {
            throw SecureBackupError.invalidEnvelope
        }
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        let password = Data(passphrase.utf8)
        let passwordKey = SymmetricKey(data: password)
        var blockIndex = UInt32(1).bigEndian
        var initial = salt
        withUnsafeBytes(of: &blockIndex) { initial.append(contentsOf: $0) }
        var result = Data(HMAC<SHA256>.authenticationCode(for: initial, using: passwordKey))
        var previous = result
        for _ in 1..<iterations {
            previous = Data(HMAC<SHA256>.authenticationCode(for: previous, using: passwordKey))
            for index in result.indices { result[index] ^= previous[index] }
        }
        return SymmetricKey(data: result)
    }
}

enum ICloudBackupStore {
    private static let fileName = "PresenceFM-Latest.presencefmencrypted"

    static func save(_ data: Data) throws -> URL {
        let directory = try backupDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func loadLatest() throws -> Data {
        let url = try backupDirectory().appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { throw SecureBackupError.noBackup }
        return try Data(contentsOf: url)
    }

    static var isAvailable: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    private static func backupDirectory() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw SecureBackupError.iCloudUnavailable
        }
        return container.appendingPathComponent("Documents/PresenceFM", isDirectory: true)
    }
}
