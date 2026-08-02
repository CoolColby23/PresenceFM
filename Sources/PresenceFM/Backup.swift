import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let presenceFMBackup = UTType(exportedAs: "fm.presence.backup", conformingTo: .json)
}

struct PresenceFMBackup: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let createdAt: Date
    let appVersion: String
    let activity: [ActivityBackupRecord]
    let queue: [QueueBackupRecord]
    let preferences: PreferenceBackup
}

struct ActivityBackupRecord: Codable {
    let id: UUID
    let title: String
    let artist: String
    let album: String?
    let startedAt: Date
    let finalizedAt: Date?
    let outcome: String
    let persistentID: String?
    let platform: String?
    let duration: Double?
    let listeningTime: Double?
}

struct QueueBackupRecord: Codable {
    let id: UUID
    let duplicateKey: String
    let title: String
    let artist: String
    let album: String?
    let startedAt: Date
    let duration: Double
    let attempts: Int
    let nextAttemptAt: Date
    let lastError: String?
    let state: String
}

struct PreferenceBackup: Codable, Equatable {
    let onboardingComplete: Bool
    let discordEnabled: Bool
    let sendNowPlaying: Bool
    let privateMode: Bool
    let privateUntil: Date?
    let showAlbum: Bool
    let showTimer: Bool
    let showLink: Bool
    let discordLineOne: String
    let discordLineTwo: String
    let discordCustomLineOne: String
    let discordCustomLineTwo: String
    let discordButtonLabel: String
    let discordSmallImage: String
    let discordLargeImage: String?
    let discordActivityType: String?
    let discordActivityName: String?
    let discordTimerStyle: String?
    let discordLargeImageText: String?
    let discordSmallImageText: String?
    let discordSharePaused: Bool?
    let discordPausedText: String?
    let launchAtLogin: Bool
    let historyRetentionDays: Int
    let discordPresenceProfiles: [DiscordPresenceProfile]?
    let selectedDiscordProfileID: UUID?
    let excludedScrobbleArtists: String?
    let excludedScrobbleAlbums: String?
    let excludedScrobbleTitleTerms: String?
    let excludedScrobblePlatforms: [String]?
}

struct PresenceFMBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.presenceFMBackup, .json] }
    let backup: PresenceFMBackup

    init(backup: PresenceFMBackup) { self.backup = backup }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalidDocument }
        backup = try BackupService.decode(data)
        try BackupService.validate(backup)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BackupService.encode(backup))
    }
}

enum BackupError: LocalizedError {
    case invalidDocument
    case unsupportedVersion(Int)
    case invalidRecord(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument: "This is not a valid PresenceFM backup."
        case .unsupportedVersion(let version): "Backup format \(version) is newer than this version of PresenceFM supports."
        case .invalidRecord(let message): "The backup contains an invalid record: \(message)"
        }
    }
}

@MainActor
enum BackupService {
    nonisolated private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    nonisolated static func encode(_ backup: PresenceFMBackup) throws -> Data {
        try makeEncoder().encode(backup)
    }

    nonisolated static func decode(_ data: Data) throws -> PresenceFMBackup {
        try makeDecoder().decode(PresenceFMBackup.self, from: data)
    }

    static func make(store: PersistenceStore, preferences: Preferences, now: Date = .now) throws -> PresenceFMBackup {
        let activity = try store.context.fetch(FetchDescriptor<ActivityRecord>()).map {
            ActivityBackupRecord(
                id: $0.id, title: $0.title, artist: $0.artist, album: $0.album,
                startedAt: $0.startedAt, finalizedAt: $0.finalizedAt, outcome: $0.outcomeRaw,
                persistentID: $0.persistentID, platform: $0.platformRaw,
                duration: $0.trackDuration ?? $0.duration, listeningTime: $0.listenedTime
            )
        }
        let queue = try store.context.fetch(FetchDescriptor<ScrobbleRecord>()).compactMap { record -> QueueBackupRecord? in
            guard record.state != .submitted else { return nil }
            return QueueBackupRecord(
                id: record.id, duplicateKey: record.duplicateKey, title: record.title,
                artist: record.artist, album: record.album, startedAt: record.startedAt,
                duration: record.duration, attempts: record.attempts,
                nextAttemptAt: record.nextAttemptAt, lastError: record.lastError.map(Redactor.redact),
                state: record.stateRaw
            )
        }
        return PresenceFMBackup(
            formatVersion: PresenceFMBackup.currentFormatVersion, createdAt: now,
            appVersion: ReleaseConfiguration.version, activity: activity, queue: queue,
            preferences: snapshot(preferences)
        )
    }

    nonisolated static func validate(_ backup: PresenceFMBackup) throws {
        guard backup.formatVersion <= PresenceFMBackup.currentFormatVersion else {
            throw BackupError.unsupportedVersion(backup.formatVersion)
        }
        guard backup.formatVersion > 0 else { throw BackupError.invalidDocument }
        for record in backup.activity {
            guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidRecord("a listening-history title is empty")
            }
        }
        for record in backup.queue {
            guard QueueState(rawValue: record.state) != nil, record.duration.isFinite, record.duration >= 0 else {
                throw BackupError.invalidRecord("a queue state or duration is invalid")
            }
        }
    }

    static func restore(_ backup: PresenceFMBackup, store: PersistenceStore, preferences: Preferences) throws {
        try validate(backup)
        if !store.isInMemory {
            try writeAutomaticBackup(make(store: store, preferences: preferences))
        }
        let context = store.context
        let oldActivity = try context.fetch(FetchDescriptor<ActivityRecord>())
        let oldQueue = try context.fetch(FetchDescriptor<ScrobbleRecord>())
        oldActivity.forEach(context.delete)
        oldQueue.forEach(context.delete)

        do {
            for value in backup.activity { context.insert(makeActivity(value)) }
            for value in backup.queue { context.insert(makeQueue(value)) }
            try context.save()
            apply(backup.preferences, to: preferences)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func writeAutomaticBackup(_ backup: PresenceFMBackup) throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("PresenceFM/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = "automatic-\(Int(backup.createdAt.timeIntervalSince1970)).presencefmbackup"
        try encode(backup).write(to: base.appendingPathComponent(name), options: .atomic)
        let existing = try FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "presencefmbackup" }.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhs > rhs
        }
        for url in existing.dropFirst(2) { try? FileManager.default.removeItem(at: url) }
    }

    private static func makeActivity(_ value: ActivityBackupRecord) -> ActivityRecord {
        let platform = PlaybackPlatform(rawValue: value.platform ?? "") ?? .appleMusic
        let track = TrackMetadata(
            identity: .init(persistentID: value.persistentID ?? "backup:\(value.id.uuidString)"),
            title: value.title, artist: value.artist, album: value.album,
            duration: value.duration ?? 0, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil, platform: platform
        )
        let outcome = SessionOutcome(rawValue: value.outcome) ?? .played
        let session = PlaybackSession(
            id: value.id, track: track, startedAt: value.startedAt,
            accumulatedPlayTime: value.listeningTime ?? 0, lastPosition: value.listeningTime ?? 0,
            eligibility: outcome == .skipped ? .listening : .eligible, outcome: outcome
        )
        let record = ActivityRecord(session: session)
        record.finalizedAt = value.finalizedAt
        record.platformRaw = value.platform
        return record
    }

    private static func makeQueue(_ value: QueueBackupRecord) -> ScrobbleRecord {
        let track = TrackMetadata(
            identity: .init(persistentID: value.duplicateKey), title: value.title,
            artist: value.artist, album: value.album, duration: value.duration,
            source: .appleMusicCatalog, appleMusicURL: nil, artworkReference: nil
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: value.startedAt,
            accumulatedPlayTime: value.duration, lastPosition: value.duration,
            eligibility: .eligible, outcome: .queued
        )
        let record = ScrobbleRecord(session: session)
        record.id = value.id
        record.duplicateKey = value.duplicateKey
        record.attempts = value.attempts
        record.nextAttemptAt = value.nextAttemptAt
        record.lastError = value.lastError.map(Redactor.redact)
        record.stateRaw = value.state
        return record
    }

    private static func snapshot(_ preferences: Preferences) -> PreferenceBackup {
        PreferenceBackup(
            onboardingComplete: preferences.onboardingComplete,
            discordEnabled: preferences.discordEnabled, sendNowPlaying: preferences.sendNowPlaying,
            privateMode: preferences.privateMode, privateUntil: preferences.privateUntil,
            showAlbum: preferences.showAlbum, showTimer: preferences.showTimer, showLink: preferences.showLink,
            discordLineOne: preferences.discordLineOne.rawValue,
            discordLineTwo: preferences.discordLineTwo.rawValue,
            discordCustomLineOne: preferences.discordCustomLineOne,
            discordCustomLineTwo: preferences.discordCustomLineTwo,
            discordButtonLabel: preferences.discordButtonLabel,
            discordSmallImage: preferences.discordSmallImage.rawValue,
            discordLargeImage: preferences.discordLargeImage.rawValue,
            discordActivityType: preferences.discordActivityType.rawValue,
            discordActivityName: preferences.discordActivityName,
            discordTimerStyle: preferences.discordTimerStyle.rawValue,
            discordLargeImageText: preferences.discordLargeImageText,
            discordSmallImageText: preferences.discordSmallImageText,
            discordSharePaused: preferences.discordSharePaused,
            discordPausedText: preferences.discordPausedText,
            launchAtLogin: preferences.launchAtLogin,
            historyRetentionDays: preferences.historyRetentionDays,
            discordPresenceProfiles: preferences.discordPresenceProfiles,
            selectedDiscordProfileID: preferences.selectedDiscordProfileID,
            excludedScrobbleArtists: preferences.excludedScrobbleArtists,
            excludedScrobbleAlbums: preferences.excludedScrobbleAlbums,
            excludedScrobbleTitleTerms: preferences.excludedScrobbleTitleTerms,
            excludedScrobblePlatforms: preferences.excludedScrobblePlatforms.map(\.rawValue).sorted()
        )
    }

    private static func apply(_ value: PreferenceBackup, to preferences: Preferences) {
        preferences.onboardingComplete = value.onboardingComplete
        preferences.discordEnabled = value.discordEnabled
        preferences.lastFMEnabled = false
        preferences.sendNowPlaying = value.sendNowPlaying
        preferences.privateMode = value.privateMode
        preferences.privateUntil = value.privateUntil
        preferences.showAlbum = value.showAlbum
        preferences.showTimer = value.showTimer
        preferences.showLink = value.showLink
        preferences.discordLineOne = DiscordLineFormat(rawValue: value.discordLineOne) ?? .title
        preferences.discordLineTwo = DiscordLineFormat(rawValue: value.discordLineTwo) ?? .artistAndAlbum
        preferences.discordCustomLineOne = value.discordCustomLineOne
        preferences.discordCustomLineTwo = value.discordCustomLineTwo
        preferences.discordButtonLabel = value.discordButtonLabel
        preferences.discordSmallImage = DiscordSmallImage(rawValue: value.discordSmallImage) ?? .playbackPlatform
        preferences.discordLargeImage = DiscordLargeImage(rawValue: value.discordLargeImage ?? "") ?? .artwork
        preferences.discordActivityType = DiscordActivityType(rawValue: value.discordActivityType ?? "") ?? .listening
        preferences.discordActivityName = value.discordActivityName ?? "PresenceFM"
        preferences.discordTimerStyle = DiscordTimerStyle(rawValue: value.discordTimerStyle ?? "")
            ?? (value.showTimer ? .remaining : .hidden)
        preferences.discordLargeImageText = value.discordLargeImageText ?? "{album}"
        preferences.discordSmallImageText = value.discordSmallImageText ?? "Playing on {platform}"
        preferences.discordSharePaused = value.discordSharePaused ?? false
        preferences.discordPausedText = value.discordPausedText ?? "Paused • {artist}"
        preferences.launchAtLogin = value.launchAtLogin
        preferences.historyRetentionDays = value.historyRetentionDays
        preferences.discordPresenceProfiles = value.discordPresenceProfiles ?? []
        preferences.selectedDiscordProfileID = value.selectedDiscordProfileID
        preferences.excludedScrobbleArtists = value.excludedScrobbleArtists ?? ""
        preferences.excludedScrobbleAlbums = value.excludedScrobbleAlbums ?? ""
        preferences.excludedScrobbleTitleTerms = value.excludedScrobbleTitleTerms ?? ""
        preferences.excludedScrobblePlatforms = Set(
            value.excludedScrobblePlatforms?.compactMap(PlaybackPlatform.init(rawValue:)) ?? []
        )
    }
}
