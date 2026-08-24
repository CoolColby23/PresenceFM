import Foundation
import SwiftData

enum QueueState: String, Codable, Sendable { case pending, retrying, permanentlyFailed, submitted }

enum PresenceFMSchemaV0: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ActivityRecord.self, ScrobbleRecord.self, DiagnosticRecord.self]
    }

    @Model final class ActivityRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var artist: String
        var album: String?
        var startedAt: Date
        var outcomeRaw: String
        var persistentID: String?
        var duration: Double?
        var listenedTime: Double?
        @Attribute(.externalStorage) var artworkData: Data?

        init(
            id: UUID, title: String, artist: String, album: String?, startedAt: Date,
            outcomeRaw: String, persistentID: String?, duration: Double?, listenedTime: Double?
        ) {
            self.id = id; self.title = title; self.artist = artist; self.album = album
            self.startedAt = startedAt; self.outcomeRaw = outcomeRaw; self.persistentID = persistentID
            self.duration = duration; self.listenedTime = listenedTime
        }
    }

    @Model final class ScrobbleRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var duplicateKey: String
        var title: String
        var artist: String
        var album: String?
        var startedAt: Date
        var duration: Double
        var attempts: Int
        var nextAttemptAt: Date
        var lastError: String?
        var stateRaw: String

        init(id: UUID, duplicateKey: String, title: String, artist: String, startedAt: Date, duration: Double) {
            self.id = id; self.duplicateKey = duplicateKey; self.title = title; self.artist = artist
            self.startedAt = startedAt; self.duration = duration; attempts = 0
            nextAttemptAt = startedAt; stateRaw = QueueState.pending.rawValue
        }
    }

    @Model final class DiagnosticRecord {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var category: String
        var message: String
        init(category: String, message: String) {
            id = UUID(); timestamp = .now; self.category = category; self.message = message
        }
    }
}

enum PresenceFMSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ActivityRecord.self, ScrobbleRecord.self, DiagnosticRecord.self, IntegrationHealthEvent.self]
    }

    @Model final class ActivityRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var artist: String
        var album: String?
        var startedAt: Date
        var outcomeRaw: String
        var persistentID: String?
        var duration: Double?
        var trackDuration: Double?
        var listenedTime: Double?
        var finalizedAt: Date?
        var platformRaw: String?
        @Attribute(.externalStorage) var artworkData: Data?

        init(session: PlaybackSession, artworkData: Data? = nil) {
            id = session.id; title = session.track.title; artist = session.track.artist
            album = session.track.album; startedAt = session.startedAt; outcomeRaw = session.outcome.rawValue
            persistentID = session.track.identity.persistentID
            duration = session.track.duration; trackDuration = session.track.duration
            listenedTime = session.accumulatedPlayTime; finalizedAt = .now
            platformRaw = session.track.platform.rawValue; self.artworkData = artworkData
        }

        var outcomeLabel: String {
            switch SessionOutcome(rawValue: outcomeRaw) {
            case .played, .queued, .submitted: "Played"
            case .listened: "Listened"
            case .skipped: "Skipped"
            case .interrupted: "Interrupted"
            case .failed: "Failed"
            case .active: "Playing"
            case nil: outcomeRaw.capitalized
            }
        }
    }

    @Model final class ScrobbleRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var duplicateKey: String
        var title: String
        var artist: String
        var album: String?
        var startedAt: Date
        var duration: Double
        var attempts: Int
        var nextAttemptAt: Date
        var lastError: String?
        var stateRaw: String

        init(session: PlaybackSession, now: Date = .now) {
            id = UUID(); duplicateKey = session.duplicateKey
            title = session.track.title; artist = session.track.artist; album = session.track.album
            startedAt = session.startedAt
            // A zero duration is the queue's durable signal for Apple Music Radio:
            // the Last.fm client omits unknown duration and marks it as radio-selected.
            duration = session.track.isAppleMusicRadio ? 0 : session.track.duration
            attempts = 0; nextAttemptAt = now; stateRaw = QueueState.pending.rawValue
        }

        var state: QueueState {
            get { QueueState(rawValue: stateRaw) ?? .pending }
            set { stateRaw = newValue.rawValue }
        }
    }

    @Model final class DiagnosticRecord {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var category: String
        var message: String
        init(category: String, message: String) {
            id = UUID(); timestamp = .now; self.category = category; self.message = message
        }
    }

    @Model final class IntegrationHealthEvent {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var integrationRaw: String
        var stateRaw: String

        init(integration: IntegrationID, state: IntegrationState, timestamp: Date = .now) {
            id = UUID(); self.timestamp = timestamp
            integrationRaw = integration.rawValue; stateRaw = state.rawValue
        }
    }
}

typealias ActivityRecord = PresenceFMSchemaV1.ActivityRecord
typealias ScrobbleRecord = PresenceFMSchemaV1.ScrobbleRecord
typealias DiagnosticRecord = PresenceFMSchemaV1.DiagnosticRecord
typealias IntegrationHealthEvent = PresenceFMSchemaV1.IntegrationHealthEvent

enum PresenceFMMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PresenceFMSchemaV0.self, PresenceFMSchemaV1.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: PresenceFMSchemaV0.self, toVersion: PresenceFMSchemaV1.self)]
    }
}

enum PersistenceError: LocalizedError {
    case save(String)
    case queueCapacity(String)

    var errorDescription: String? {
        switch self {
        case .save(let message): "Local data could not be saved: \(message)"
        case .queueCapacity(let message): message
        }
    }
}

enum QueueAdmission: Equatable {
    case accepted
    case duplicate
    case warning(String)
    case rejected(String)
}

@MainActor
final class PersistenceStore {
    struct QueueLimits {
        let pendingWarning: Int
        let pendingLimit: Int
        let permanentWarning: Int
        let permanentLimit: Int

        static let production = QueueLimits(
            pendingWarning: IntegrationPolicy.pendingQueueWarning,
            pendingLimit: IntegrationPolicy.pendingQueueLimit,
            permanentWarning: IntegrationPolicy.permanentQueueWarning,
            permanentLimit: IntegrationPolicy.permanentQueueLimit
        )
    }

    let container: ModelContainer
    let isInMemory: Bool
    private let queueLimits: QueueLimits
    var context: ModelContext { container.mainContext }
    private(set) var lastError: PersistenceError?
    var onError: ((PersistenceError) -> Void)?

    init(
        inMemory: Bool = false,
        storeURL: URL? = nil,
        legacyStoreURL: URL? = nil,
        queueLimits: QueueLimits = .production
    ) throws {
        isInMemory = inMemory
        self.queueLimits = queueLimits
        let schema = Schema(versionedSchema: PresenceFMSchemaV1.self)
        let resolvedStoreURL: URL?
        let configuration: ModelConfiguration
        if inMemory {
            resolvedStoreURL = nil
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let resolved = try storeURL ?? PersistenceRecovery.defaultStoreURL()
            let legacy = try legacyStoreURL ?? PersistenceRecovery.legacyStoreURL()
            _ = try PersistenceRecovery.prepare(storeURL: resolved, legacyStoreURL: legacy)
            resolvedStoreURL = resolved
            configuration = ModelConfiguration("PresenceFM", schema: schema, url: resolved)
        }
        container = try ModelContainer(
            for: schema,
            migrationPlan: PresenceFMMigrationPlan.self,
            configurations: configuration
        )
        if let resolvedStoreURL { try PersistenceRecovery.markMigrationSuccessful(storeURL: resolvedStoreURL) }
    }

    func record(_ session: PlaybackSession, artworkData: Data? = nil) {
        context.insert(ActivityRecord(session: session, artworkData: artworkData))
        trim(ActivityRecord.self, limit: IntegrationPolicy.activityRecordLimit, oldestFirst: [SortDescriptor(\.startedAt)])
        removeActivity(olderThanDays: Preferences.shared.historyRetentionDays)
        save()
    }

    func backfillArtwork(for persistentID: String, artworkData: Data) {
        let descriptor = FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.persistentID == persistentID }
        )
        guard let records = try? context.fetch(descriptor) else { return }
        let missingArtwork = records.filter { $0.artworkData == nil }
        guard !missingArtwork.isEmpty else { return }
        missingArtwork.forEach { $0.artworkData = artworkData }
        save()
    }

    func clearActivity() {
        guard let records = try? context.fetch(FetchDescriptor<ActivityRecord>()) else { return }
        records.forEach(context.delete)
        save()
    }

    @discardableResult
    func clearDemoActivity() -> Int {
        guard let records = try? context.fetch(FetchDescriptor<ActivityRecord>()) else { return 0 }
        let demoRecords = records.filter { DemoPlaybackSequence.contains(persistentID: $0.persistentID) }
        guard !demoRecords.isEmpty else { return 0 }
        demoRecords.forEach(context.delete)
        save()
        return demoRecords.count
    }

    func applyHistoryRetention(days: Int) {
        removeActivity(olderThanDays: days)
        save()
    }

    @discardableResult
    func enqueue(_ session: PlaybackSession, now: Date = .now) -> QueueAdmission {
        let key = session.duplicateKey
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.duplicateKey == key })
        guard (try? context.fetchCount(descriptor)) == 0 else { return .duplicate }

        let pendingRaw = QueueState.pending.rawValue
        let retryingRaw = QueueState.retrying.rawValue
        let permanentRaw = QueueState.permanentlyFailed.rawValue
        let pendingDescriptor = FetchDescriptor<ScrobbleRecord>(
            predicate: #Predicate { $0.stateRaw == pendingRaw || $0.stateRaw == retryingRaw }
        )
        let permanentDescriptor = FetchDescriptor<ScrobbleRecord>(
            predicate: #Predicate { $0.stateRaw == permanentRaw }
        )
        let pending = (try? context.fetchCount(pendingDescriptor)) ?? 0
        let permanent = (try? context.fetchCount(permanentDescriptor)) ?? 0
        if pending >= queueLimits.pendingLimit {
            return rejectQueue("Scrobble queue is full. Reconnect Last.fm or remove queued items before new listens can be queued.")
        }
        if permanent >= queueLimits.permanentLimit {
            return rejectQueue("Too many scrobbles need attention. Retry or remove failed items before new listens can be queued.")
        }
        context.insert(ScrobbleRecord(session: session, now: now)); save()
        if pending + 1 == queueLimits.pendingWarning {
            return .warning("The offline scrobble queue is approaching its 5,000-item limit.")
        }
        if permanent == queueLimits.permanentWarning {
            return .warning("The failed scrobble queue is approaching its 500-item limit.")
        }
        return .accepted
    }

    @discardableResult
    func retryScrobble(id: UUID, now: Date = .now) -> Bool {
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first else { return false }
        record.state = .pending
        record.attempts = 0
        record.nextAttemptAt = now
        record.lastError = nil
        save()
        return true
    }

    func removeScrobble(id: UUID) {
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first else { return }
        context.delete(record)
        save()
    }

    /// Rearms every unsubmitted play at once. A single Last.fm outage can strand
    /// hundreds of plays for the same reason, and clearing that one record at a
    /// time is the kind of work a person should never have to do by hand.
    /// Returns how many records were rearmed.
    @discardableResult
    func retryAllScrobbles(now: Date = .now) -> Int {
        let submittedRaw = QueueState.submitted.rawValue
        let descriptor = FetchDescriptor<ScrobbleRecord>(
            predicate: #Predicate { $0.stateRaw != submittedRaw }
        )
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return 0 }
        for record in records {
            record.state = .pending
            record.attempts = 0
            record.nextAttemptAt = now
            record.lastError = nil
        }
        save()
        return records.count
    }

    /// Discards every play in one queue state, used to clear a block of listens
    /// that Last.fm will never accept. Returns how many records were removed.
    @discardableResult
    func removeScrobbles(in state: QueueState) -> Int {
        let stateRaw = state.rawValue
        let descriptor = FetchDescriptor<ScrobbleRecord>(
            predicate: #Predicate { $0.stateRaw == stateRaw }
        )
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return 0 }
        records.forEach(context.delete)
        save()
        return records.count
    }

    @discardableResult
    func correctScrobble(
        id: UUID,
        title: String,
        artist: String,
        album: String?,
        now: Date = .now
    ) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else { return false }
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first,
              record.state == .permanentlyFailed else { return false }
        record.title = cleanTitle
        record.artist = cleanArtist
        let cleanAlbum = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        record.album = cleanAlbum?.isEmpty == false ? cleanAlbum : nil
        record.state = .pending
        record.attempts = 0
        record.nextAttemptAt = now
        record.lastError = nil
        save()
        return true
    }

    func log(_ category: String, _ message: String) {
        context.insert(DiagnosticRecord(category: category, message: Redactor.redact(message)))
        trim(DiagnosticRecord.self, limit: IntegrationPolicy.diagnosticRecordLimit, oldestFirst: [SortDescriptor(\.timestamp)])
        save()
    }

    func recordHealth(_ integration: IntegrationID, state: IntegrationState, at timestamp: Date = .now) {
        let integrationRaw = integration.rawValue
        let descriptor = FetchDescriptor<IntegrationHealthEvent>(
            predicate: #Predicate { $0.integrationRaw == integrationRaw },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let latest = try? context.fetch(descriptor).first,
           latest.stateRaw == state.rawValue { return }
        context.insert(IntegrationHealthEvent(integration: integration, state: state, timestamp: timestamp))
        trim(IntegrationHealthEvent.self, limit: IntegrationPolicy.healthEventLimit, oldestFirst: [SortDescriptor(\.timestamp)])
        save()
    }

    func lastSuccessfulIntegrationDate(_ integration: IntegrationID) -> Date? {
        let integrationRaw = integration.rawValue
        let connected = IntegrationState.connected.rawValue
        let descriptor = FetchDescriptor<IntegrationHealthEvent>(
            predicate: #Predicate { $0.integrationRaw == integrationRaw && $0.stateRaw == connected },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try? context.fetch(descriptor).first?.timestamp
    }

    func deleteSubmittedScrobbles() {
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.stateRaw == "submitted" })
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return }
        records.forEach(context.delete)
        save()
    }

    func save() {
        do {
            try context.save()
            lastError = nil
        } catch {
            let wrapped = PersistenceError.save(Redactor.redact(error.localizedDescription))
            lastError = wrapped
            onError?(wrapped)
        }
    }

    private func rejectQueue(_ message: String) -> QueueAdmission {
        let error = PersistenceError.queueCapacity(message)
        lastError = error
        onError?(error)
        return .rejected(message)
    }

    private func trim<T: PersistentModel>(
        _ type: T.Type,
        limit: Int,
        oldestFirst: [SortDescriptor<T>]
    ) {
        let countDescriptor = FetchDescriptor<T>()
        guard let count = try? context.fetchCount(countDescriptor), count > limit else { return }
        var overflowDescriptor = FetchDescriptor<T>(sortBy: oldestFirst)
        overflowDescriptor.fetchLimit = count - limit
        guard let overflow = try? context.fetch(overflowDescriptor) else { return }
        overflow.forEach(context.delete)
    }

    private func removeActivity(olderThanDays days: Int) {
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        let descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.startedAt < cutoff })
        guard let records = try? context.fetch(descriptor) else { return }
        records.forEach(context.delete)
    }
}

enum Redactor {
    static func redact(_ input: String) -> String {
        var value = input
        for key in ["api_key", "api_sig", "sk", "token", "secret", "session"] {
            value = value.replacingOccurrences(of: "(?i)(\(key)[=: ]+)[^&\\s]+", with: "$1<redacted>", options: .regularExpression)
        }
        value = value.replacingOccurrences(of: "(?i)(authorization[=: ]+bearer[ ]+)[^&\\s]+", with: "$1<redacted>", options: .regularExpression)
        value = value.replacingOccurrences(of: "/Users/[^/\\s]+", with: "/Users/<redacted>", options: .regularExpression)
        return value
    }
}
