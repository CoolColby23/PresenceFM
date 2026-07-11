import Foundation
import SwiftData

@MainActor
final class ScrobbleQueue {
    private let store: PersistenceStore
    private let client: any ScrobbleSubmitting
    private let now: @Sendable () -> Date
    private var processingTask: Task<Void, Never>?

    init(store: PersistenceStore, client: any ScrobbleSubmitting, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.client = client
        self.now = now
    }

    func enqueue(_ session: PlaybackSession) { store.enqueue(session); Task { await process() } }

    func start() {
        guard processingTask == nil else { return }
        processingTask = Task {
            while !Task.isCancelled {
                await process()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() { processingTask?.cancel(); processingTask = nil }

    func retry(id: UUID) { if store.retryScrobble(id: id) { Task { await process() } } }
    func remove(id: UUID) { store.removeScrobble(id: id) }

    func process() async {
        let now = now()
        let descriptor = FetchDescriptor<ScrobbleRecord>(
            predicate: #Predicate { ($0.stateRaw == "pending" || $0.stateRaw == "retrying") && $0.nextAttemptAt <= now },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        guard let records = try? store.context.fetch(descriptor) else { return }
        for record in records {
            record.state = .retrying
            do {
                try await client.scrobble(title: record.title, artist: record.artist, album: record.album,
                                           duration: record.duration, startedAt: record.startedAt)
                record.state = .submitted; record.lastError = nil
            } catch let error as LastFMError {
                record.attempts += 1; record.lastError = error.localizedDescription
                if case .api(let code, _) = error, [4, 6, 7, 8, 9, 10, 13, 14, 15, 26].contains(code) { record.state = .permanentlyFailed }
                else {
                    record.state = .pending
                    record.nextAttemptAt = retryDate(attempts: record.attempts, from: now)
                }
            } catch {
                record.attempts += 1
                record.state = .pending
                record.lastError = Redactor.redact(error.localizedDescription)
                record.nextAttemptAt = retryDate(attempts: record.attempts, from: now)
            }
            try? store.context.save()
        }
    }

    func retryDate(attempts: Int, from date: Date) -> Date {
        let delay = min(3600, pow(2, Double(min(max(attempts, 1), 11))) * 5)
        return date.addingTimeInterval(delay)
    }
}
