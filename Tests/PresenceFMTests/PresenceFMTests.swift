import Foundation
import AppKit
import SwiftData
import Testing
@testable import PresenceFM

@Suite("Playback sessions")
struct PlaybackSessionTests {
    let track = TrackMetadata(identity: TrackIdentity(persistentID: "1"), title: "Track", artist: "Artist", album: "Album", duration: 100, source: .appleMusicCatalog, appleMusicURL: nil, artworkReference: nil)

    @Test func qualifiesAtHalfDuration() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 0, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 50, observedAt: start.addingTimeInterval(50), confidence: .high))
        #expect(await tracker.active?.eligibility == .eligible)
    }

    @Test func pausedTimeDoesNotCount() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 10, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: track, state: .paused, position: 10, observedAt: start.addingTimeInterval(100), confidence: .high))
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 10, observedAt: start.addingTimeInterval(200), confidence: .high))
        #expect(await tracker.active?.accumulatedPlayTime == 0)
    }

    @Test func eligibleTrackIsFinalizedAsPlayed() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        let nextTrack = TrackMetadata(identity: TrackIdentity(persistentID: "2"), title: "Next", artist: "Artist", album: nil, duration: 100, source: .appleMusicCatalog, appleMusicURL: nil, artworkReference: nil)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 0, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 50, observedAt: start.addingTimeInterval(50), confidence: .high))

        let events = await tracker.ingest(.init(track: nextTrack, state: .playing, position: 0, observedAt: start.addingTimeInterval(51), confidence: .high))

        let finalized = events.compactMap { event -> PlaybackSession? in
            guard case .finalized(let session) = event else { return nil }
            return session
        }.first
        #expect(finalized?.outcome == .played)
    }

    @Test func shortTrackIsNotScrobbleable() {
        let short = TrackMetadata(identity: .init(persistentID: "2"), title: "Tiny", artist: "Artist", album: nil, duration: 30, source: .localFile, appleMusicURL: nil, artworkReference: nil)
        #expect(!short.isScrobbleable)
    }

    @Test func transientLowConfidenceDoesNotFinalizeSession() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 10, observedAt: start, confidence: .high))
        let events = await tracker.ingest(.init(track: nil, state: .stopped, position: 0, observedAt: start.addingTimeInterval(2), confidence: .low))
        #expect(await tracker.active != nil)
        #expect(events.count == 1)
    }

    @Test func forwardSeekDoesNotEarnListeningCredit() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 0, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 80, observedAt: start.addingTimeInterval(2), confidence: .high))
        #expect(await tracker.active?.accumulatedPlayTime == 0)
    }

    @Test func backwardSeekKeepsPreviouslyEarnedCredit() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 0, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 20, observedAt: start.addingTimeInterval(20), confidence: .high))
        let earned = await tracker.active?.accumulatedPlayTime
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 5, observedAt: start.addingTimeInterval(22), confidence: .high))
        #expect(await tracker.active?.accumulatedPlayTime == earned)
    }

    @Test func repeatedSnapshotDoesNotStartDuplicateSession() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        let first = await tracker.ingest(.init(track: track, state: .playing, position: 0, observedAt: start, confidence: .high))
        let second = await tracker.ingest(.init(track: track, state: .playing, position: 1, observedAt: start.addingTimeInterval(1), confidence: .high))
        #expect(first.contains { if case .started = $0 { true } else { false } })
        #expect(!second.contains { if case .started = $0 { true } else { false } })
    }

    @Test func streamIsNeverEligible() async {
        let stream = TrackMetadata(identity: .init(persistentID: "radio"), title: "Station", artist: "Host", album: nil, duration: 3_600, source: .unsupportedStream, appleMusicURL: nil, artworkReference: nil)
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: stream, state: .playing, position: 0, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: stream, state: .playing, position: 300, observedAt: start.addingTimeInterval(300), confidence: .high))
        #expect(await tracker.active?.eligibility == .ineligible)
    }

    @Test func listeningPresentationReportsProgressAndRemainingTime() {
        var session = PlaybackSession(id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 25, lastPosition: 25, eligibility: .listening, outcome: .active)
        guard case .listening(let progress, let remaining) = session.scrobblePresentation else {
            Issue.record("Expected listening presentation")
            return
        }
        #expect(progress == 0.5)
        #expect(remaining == 25)
        session.accumulatedPlayTime = 50
        session.eligibility = .eligible
        #expect(session.scrobblePresentation == .ready)
    }

    @Test func ineligiblePresentationExplainsStreams() {
        let stream = TrackMetadata(identity: .init(persistentID: "radio"), title: "Station", artist: "Host", album: nil, duration: 3_600, source: .unsupportedStream, appleMusicURL: nil, artworkReference: nil)
        let session = PlaybackSession(id: UUID(), track: stream, startedAt: .now, accumulatedPlayTime: 0, lastPosition: 0, eligibility: .ineligible, outcome: .active)
        #expect(session.scrobblePresentation == .ineligible("Radio streams are not scrobbled."))
    }
}

@Suite("Artwork")
struct ArtworkTests {
    @Test func rejectsCorruptArtworkAndBoundsMemoryCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ArtworkService(memoryLimit: 2, diskLimit: 2, directory: directory)
        #expect(await !service.cache(Data("not an image".utf8), for: .init(persistentID: "bad")))
        let imageData = try #require(Self.imageData())
        #expect(await service.cache(imageData, for: .init(persistentID: "1")))
        #expect(await service.cache(imageData, for: .init(persistentID: "2")))
        #expect(await service.cache(imageData, for: .init(persistentID: "3")))
        #expect(await service.memoryEntryCount == 2)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
    }

    private static func imageData() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
@Suite("Preferences and notifications")
struct PreferencesAndNotificationTests {
    @Test func preferencesPersistAndRemainObservableState() {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.showAlbum = false
        preferences.privateUntil = Date(timeIntervalSince1970: 123)
        let reloaded = Preferences(defaults: defaults)
        #expect(!reloaded.showAlbum)
        #expect(reloaded.privateUntil == Date(timeIntervalSince1970: 123))
    }

    @Test func notificationsAreDeduplicatedAndResettable() async {
        let delivery = FakeNotificationDelivery()
        let coordinator = NotificationCoordinator(delivery: delivery)
        await coordinator.notifyOnce(key: "permission", title: "Title", body: "Body", section: .diagnostics)
        await coordinator.notifyOnce(key: "permission", title: "Title", body: "Body", section: .diagnostics)
        #expect(delivery.sections == [.diagnostics])
        coordinator.reset("permission")
        await coordinator.notifyOnce(key: "permission", title: "Title", body: "Body", section: .settings)
        #expect(delivery.sections == [.diagnostics, .settings])
    }

    @Test func timedPrivacyExpiresWithoutAViewRead() async throws {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.privateMode = true
        preferences.privateUntil = .now.addingTimeInterval(0.05)
        let store = try PersistenceStore(inMemory: true)
        let model = AppModel(
            store: store,
            preferences: preferences,
            notifications: NotificationCoordinator(delivery: FakeNotificationDelivery())
        )
        try await Task.sleep(for: .milliseconds(150))
        #expect(!preferences.privateMode)
        #expect(preferences.privateUntil == nil)
        #expect(!model.isPrivate)
    }
}

@MainActor
private final class FakeNotificationDelivery: NotificationDelivering {
    var sections: [DashboardSection] = []
    func requestAuthorization() async -> Bool { true }
    func deliver(identifier: String, title: String, body: String, section: DashboardSection) async { sections.append(section) }
}

@Suite("Security")
struct SecurityTests {
    @Test func redactsSecretsAndUserPaths() {
        let output = Redactor.redact("api_key=abc123 /Users/colby/file token xyz Authorization: Bearer bearer-value")
        #expect(!output.contains("abc123")); #expect(!output.contains("colby")); #expect(!output.contains("xyz")); #expect(!output.contains("bearer-value"))
    }

    @Test func signatureIsDeterministic() {
        let values = ["method": "auth.getToken", "api_key": "key", "format": "json"]
        #expect(LastFMClient.signature(values, secret: "secret") == LastFMClient.signature(values, secret: "secret"))
        #expect(LastFMClient.signature(values, secret: "secret").count == 32)
    }
}

@MainActor
@Suite("Persistence and queue")
struct PersistenceAndQueueTests {
    private func session(id: UUID = UUID()) -> PlaybackSession {
        let track = TrackMetadata(identity: .init(persistentID: "persisted"), title: "Track", artist: "Artist", album: "Album", duration: 100, source: .appleMusicCatalog, appleMusicURL: nil, artworkReference: nil)
        return PlaybackSession(id: id, track: track, startedAt: Date(timeIntervalSince1970: 1_000), accumulatedPlayTime: 50, lastPosition: 50, eligibility: .eligible, outcome: .queued)
    }

    @Test func duplicateScrobblesAreStoredOnce() throws {
        let store = try PersistenceStore(inMemory: true)
        let value = session()
        store.enqueue(value)
        store.enqueue(value)
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 1)
    }

    @Test func retryResetsPermanentFailure() throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(session())
        let record = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
        record.state = .permanentlyFailed
        record.attempts = 4
        record.lastError = "bad session"
        #expect(store.retryScrobble(id: record.id))
        #expect(record.state == .pending)
        #expect(record.attempts == 0)
        #expect(record.lastError == nil)
    }

    @Test func retryBackoffIsDeterministicAndCapped() throws {
        let store = try PersistenceStore(inMemory: true)
        let queue = ScrobbleQueue(store: store, client: SuccessfulSubmitter())
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(queue.retryDate(attempts: 1, from: start).timeIntervalSince(start) == 10)
        #expect(queue.retryDate(attempts: 99, from: start).timeIntervalSince(start) == 3_600)
    }

    @Test func expiredAuthorizationBecomesPermanentFailure() async throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(session())
        let queue = ScrobbleQueue(store: store, client: FailingSubmitter(error: .api(9, "Invalid session")))
        await queue.process()
        let record = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
        #expect(record.state == .permanentlyFailed)
        #expect(record.attempts == 1)
    }

    @Test func transportFailureRemainsQueued() async throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(session())
        let pending = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
        pending.nextAttemptAt = .distantPast
        let queue = ScrobbleQueue(store: store, client: FailingSubmitter(error: .transport("Offline")), now: { Date(timeIntervalSince1970: 2_000) })
        await queue.process()
        #expect(pending.state == .pending)
        #expect(pending.attempts == 1)
        #expect(pending.nextAttemptAt == Date(timeIntervalSince1970: 2_010))
    }

    @Test func interruptedRetryingRecordResumesAfterRestart() async throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(session())
        let record = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
        record.state = .retrying
        record.nextAttemptAt = .distantPast
        let queue = ScrobbleQueue(store: store, client: SuccessfulSubmitter())
        await queue.process()
        #expect(record.state == .submitted)
    }
}

private actor SuccessfulSubmitter: ScrobbleSubmitting {
    func scrobble(title: String, artist: String, album: String?, duration: Double, startedAt: Date) async throws {}
}

private actor FailingSubmitter: ScrobbleSubmitting {
    let error: LastFMError
    init(error: LastFMError) { self.error = error }
    func scrobble(title: String, artist: String, album: String?, duration: Double, startedAt: Date) async throws { throw error }
}

@MainActor
@Suite("Listening insights")
struct ListeningInsightsTests {
    @Test func summaryCountsListensMinutesArtistsAndDays() throws {
        let store = try PersistenceStore(inMemory: true)
        let now = Date.now
        store.record(session(title: "One", artist: "Artist A", startedAt: now.addingTimeInterval(-3_600), listened: 120, outcome: .played))
        store.record(session(title: "Two", artist: "Artist A", startedAt: now.addingTimeInterval(-1_800), listened: 180, outcome: .played))
        store.record(session(title: "Skip", artist: "Artist B", startedAt: now, listened: 10, outcome: .skipped))
        let records = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        let summary = ListeningSummary(records: records, now: now)
        #expect(summary.total == 3)
        #expect(summary.played == 2)
        #expect(summary.skipped == 1)
        #expect(summary.listeningMinutes == 5)
        #expect(summary.topArtists.first == ArtistPlayCount(artist: "Artist A", plays: 2))
        #expect(summary.dailyCounts.reduce(0) { $0 + $1.plays } == 2)
    }

    @Test func csvEscapesMetadataAndClearHistoryDoesNotTouchQueue() throws {
        let store = try PersistenceStore(inMemory: true)
        let value = session(title: "A, \"Quoted\" Song", artist: "Artist", startedAt: .now, listened: 60, outcome: .played)
        store.record(value)
        store.enqueue(value)
        let records = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        let csv = HistoryCSVExporter.csv(records: records)
        #expect(csv.contains("\"A, \"\"Quoted\"\" Song\""))
        store.clearActivity()
        #expect(try store.context.fetchCount(FetchDescriptor<ActivityRecord>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 1)
    }

    @Test func discordApplicationIDIsBundled() {
        #expect(ReleaseConfiguration.discordApplicationID == "1525555974390153346")
    }

    private func session(
        title: String,
        artist: String,
        startedAt: Date,
        listened: TimeInterval,
        outcome: SessionOutcome
    ) -> PlaybackSession {
        let track = TrackMetadata(
            identity: .init(persistentID: UUID().uuidString), title: title, artist: artist,
            album: "Album", duration: 240, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        return PlaybackSession(
            id: UUID(), track: track, startedAt: startedAt, accumulatedPlayTime: listened,
            lastPosition: listened, eligibility: outcome == .played ? .eligible : .listening, outcome: outcome
        )
    }
}
