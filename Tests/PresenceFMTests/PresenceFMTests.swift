import Foundation
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
