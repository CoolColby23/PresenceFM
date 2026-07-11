import Foundation
import SwiftData

@Model
final class ActivityRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String?
    var startedAt: Date
    var outcomeRaw: String

    init(session: PlaybackSession) {
        id = session.id; title = session.track.title; artist = session.track.artist
        album = session.track.album; startedAt = session.startedAt; outcomeRaw = session.outcome.rawValue
    }

    var outcomeLabel: String {
        switch SessionOutcome(rawValue: outcomeRaw) {
        case .played, .queued, .submitted: "Played"
        case .skipped: "Skipped"
        case .failed: "Failed"
        case .active: "Playing"
        case nil: outcomeRaw.capitalized
        }
    }
}

enum QueueState: String, Codable, Sendable { case pending, retrying, permanentlyFailed, submitted }

@Model
final class ScrobbleRecord {
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

    init(session: PlaybackSession) {
        id = UUID(); duplicateKey = session.duplicateKey
        title = session.track.title; artist = session.track.artist; album = session.track.album
        startedAt = session.startedAt; duration = session.track.duration
        attempts = 0; nextAttemptAt = .now; stateRaw = QueueState.pending.rawValue
    }

    var state: QueueState {
        get { QueueState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }
}

@Model
final class DiagnosticRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var category: String
    var message: String
    init(category: String, message: String) {
        id = UUID(); timestamp = .now; self.category = category; self.message = message
    }
}

@MainActor
final class PersistenceStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let schema = Schema([ActivityRecord.self, ScrobbleRecord.self, DiagnosticRecord.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    func record(_ session: PlaybackSession) {
        context.insert(ActivityRecord(session: session))
        trim(ActivityRecord.self, limit: 200, sort: [SortDescriptor(\.startedAt, order: .reverse)])
        try? context.save()
    }

    func enqueue(_ session: PlaybackSession) {
        let key = session.duplicateKey
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.duplicateKey == key })
        guard (try? context.fetchCount(descriptor)) == 0 else { return }
        context.insert(ScrobbleRecord(session: session)); try? context.save()
    }

    @discardableResult
    func retryScrobble(id: UUID) -> Bool {
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first else { return false }
        record.state = .pending
        record.attempts = 0
        record.nextAttemptAt = .now
        record.lastError = nil
        try? context.save()
        return true
    }

    func removeScrobble(id: UUID) {
        let descriptor = FetchDescriptor<ScrobbleRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first else { return }
        context.delete(record)
        try? context.save()
    }

    func log(_ category: String, _ message: String) {
        context.insert(DiagnosticRecord(category: category, message: Redactor.redact(message)))
        try? context.save()
    }

    private func trim<T: PersistentModel>(_ type: T.Type, limit: Int, sort: [SortDescriptor<T>]) {
        let descriptor = FetchDescriptor<T>(sortBy: sort)
        guard let records = try? context.fetch(descriptor), records.count > limit else { return }
        records.dropFirst(limit).forEach(context.delete)
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
