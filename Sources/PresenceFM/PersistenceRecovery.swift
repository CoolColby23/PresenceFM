import Foundation

struct PersistencePreparation: Sendable {
    let storeURL: URL
    let importedLegacyStore: Bool
    let backupURL: URL?
}

enum PersistenceRecoveryError: LocalizedError {
    case noBackup
    case missingStore

    var errorDescription: String? {
        switch self {
        case .noBackup: "No automatic database backup is available."
        case .missingStore: "The local database could not be found."
        }
    }
}

enum PersistenceRecovery {
    static let schemaVersion = 1

    static func applicationDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("PresenceFM", isDirectory: true)
    }

    static func defaultStoreURL(fileManager: FileManager = .default) throws -> URL {
        try applicationDirectory(fileManager: fileManager).appendingPathComponent("PresenceFM.store")
    }

    static func legacyStoreURL(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("default.store")
    }

    static func prepare(
        storeURL: URL,
        legacyStoreURL: URL?,
        schemaVersion: Int = schemaVersion,
        fileManager: FileManager = .default
    ) throws -> PersistencePreparation {
        let directory = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacySentinel = directory.appendingPathComponent(".legacy-store-imported")
        var importedLegacy = false

        if !fileManager.fileExists(atPath: storeURL.path),
           !fileManager.fileExists(atPath: legacySentinel.path),
           let legacyStoreURL, fileManager.fileExists(atPath: legacyStoreURL.path) {
            try copyStoreBundle(from: legacyStoreURL, to: storeURL, fileManager: fileManager)
            try Data().write(to: legacySentinel, options: .atomic)
            importedLegacy = true
        }

        let marker = directory.appendingPathComponent("store-schema-version")
        let storedVersion = (try? String(contentsOf: marker, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let backupURL: URL?
        if fileManager.fileExists(atPath: storeURL.path), storedVersion != schemaVersion {
            backupURL = try createStoreBackup(storeURL: storeURL, fileManager: fileManager)
        } else { backupURL = nil }

        return PersistencePreparation(storeURL: storeURL, importedLegacyStore: importedLegacy, backupURL: backupURL)
    }

    static func markMigrationSuccessful(
        storeURL: URL, schemaVersion: Int = schemaVersion
    ) throws {
        let marker = storeURL.deletingLastPathComponent().appendingPathComponent("store-schema-version")
        try Data("\(schemaVersion)\n".utf8).write(to: marker, options: .atomic)
    }

    static func restoreLatestBackup(
        storeURL: URL? = nil, fileManager: FileManager = .default
    ) throws {
        let storeURL = try storeURL ?? defaultStoreURL(fileManager: fileManager)
        let backups = try backupDirectories(for: storeURL, fileManager: fileManager)
        guard let latest = backups.first else { throw PersistenceRecoveryError.noBackup }
        try preserveFailedStore(storeURL: storeURL, fileManager: fileManager)
        let backedUpStore = latest.appendingPathComponent(storeURL.lastPathComponent)
        guard fileManager.fileExists(atPath: backedUpStore.path) else { throw PersistenceRecoveryError.noBackup }
        try copyStoreBundle(from: backedUpStore, to: storeURL, fileManager: fileManager)
    }

    static func prepareFreshStore(
        storeURL: URL? = nil, fileManager: FileManager = .default
    ) throws {
        let storeURL = try storeURL ?? defaultStoreURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: storeURL.path) {
            try preserveFailedStore(storeURL: storeURL, fileManager: fileManager)
        }
        let sentinel = storeURL.deletingLastPathComponent().appendingPathComponent(".legacy-store-imported")
        if !fileManager.fileExists(atPath: sentinel.path) { try Data().write(to: sentinel, options: .atomic) }
        try? fileManager.removeItem(at: storeURL.deletingLastPathComponent().appendingPathComponent("store-schema-version"))
    }

    private static func createStoreBackup(storeURL: URL, fileManager: FileManager) throws -> URL {
        let root = storeURL.deletingLastPathComponent().appendingPathComponent("StoreBackups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let backup = root.appendingPathComponent("migration-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        try copyStoreBundle(from: storeURL, to: backup.appendingPathComponent(storeURL.lastPathComponent), fileManager: fileManager)
        for old in try backupDirectories(for: storeURL, fileManager: fileManager).dropFirst(2) {
            try? fileManager.removeItem(at: old)
        }
        return backup
    }

    private static func backupDirectories(for storeURL: URL, fileManager: FileManager) throws -> [URL] {
        let root = storeURL.deletingLastPathComponent().appendingPathComponent("StoreBackups", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ).filter { $0.hasDirectoryPath }.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhs > rhs
        }
    }

    private static func preserveFailedStore(storeURL: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: storeURL.path) else { return }
        let root = storeURL.deletingLastPathComponent().appendingPathComponent("FailedStores", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("failed-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for source in storeBundleURLs(storeURL) where fileManager.fileExists(atPath: source.path) {
            try fileManager.moveItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
        }
    }

    private static func copyStoreBundle(from source: URL, to destination: URL, fileManager: FileManager) throws {
        for (sourceFile, destinationFile) in zip(storeBundleURLs(source), storeBundleURLs(destination)) {
            guard fileManager.fileExists(atPath: sourceFile.path) else { continue }
            let temporary = destinationFile.deletingLastPathComponent().appendingPathComponent(".\(destinationFile.lastPathComponent).\(UUID().uuidString).tmp")
            try fileManager.copyItem(at: sourceFile, to: temporary)
            if fileManager.fileExists(atPath: destinationFile.path) { try fileManager.removeItem(at: destinationFile) }
            try fileManager.moveItem(at: temporary, to: destinationFile)
        }
    }

    private static func storeBundleURLs(_ storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
    }
}
