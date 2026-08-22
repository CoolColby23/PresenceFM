import Foundation
import MediaPlayer
import MusicKit
import PresenceFMCore

actor AppleMusicEvidenceSource: PlaybackEvidenceSource {
    private let player = MPMusicPlayerController.systemMusicPlayer
    private let deviceID: UUID
    private var lastItemID: String?
    private var accumulated: TimeInterval = 0
    private var lastPosition: TimeInterval?
    private var lastObservedAt: Date?

    init(deviceID: UUID) { self.deviceID = deviceID }

    func requestAuthorization() async -> MusicAuthorization.Status { await MusicAuthorization.request() }
    func establishBaseline() async throws -> CaptureBaseline { CaptureBaseline() }

    func currentEvidence() async -> PlaybackEvidence? {
        guard let item = player.nowPlayingItem else { reset(); return nil }
        let now = Date(); let position = max(0, player.currentPlaybackTime)
        let itemID = item.playbackStoreID.isEmpty ? String(item.persistentID) : item.playbackStoreID
        if itemID != lastItemID { accumulated = 0; lastPosition = nil; lastObservedAt = nil; lastItemID = itemID }
        if player.playbackState == .playing, let priorPosition = lastPosition, let priorDate = lastObservedAt {
            let wall = max(0, now.timeIntervalSince(priorDate)); let delta = position - priorPosition
            if delta >= -2, delta <= wall + 4 { accumulated += min(wall, max(0, delta + 1)) }
        }
        lastPosition = position; lastObservedAt = now
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let duration = item.playbackDuration > 0 ? item.playbackDuration : nil
        let startedAt = now.addingTimeInterval(-position)
        return PlaybackEvidence(
            deviceID: deviceID, platform: item.playbackStoreID.isEmpty ? .localMusic : .appleMusic,
            sourceTrackID: itemID, metadata: .init(title: title, artist: artist, album: item.albumTitle, duration: duration, startedAt: startedAt),
            observedPlayTime: accumulated, origin: .observed, confidence: .strong, capturedAt: now
        )
    }

    func reconcile(since cursor: ReconciliationCursor) async throws -> ReconciliationResult {
        var request = MusicRecentlyPlayedRequest<Song>(); request.limit = 50
        let response = try await request.response()
        var items = response.items
        while items.hasNextBatch {
            let previousCount = items.count
            guard let next = try await items.nextBatch(limit: 50), !next.isEmpty else { break }
            items += next
            guard items.count > previousCount else { break }
        }
        let evidence = items.compactMap { song -> PlaybackEvidence? in
            guard let played = song.lastPlayedDate, played > cursor.lastCheckedAt else { return nil }
            return PlaybackEvidence(
                deviceID: deviceID, sourceTrackID: song.id.rawValue,
                metadata: .init(title: song.title, artist: song.artistName, album: song.albumTitle, duration: song.duration, startedAt: played),
                observedPlayTime: nil, origin: .reconciled, confidence: .probable, capturedAt: .now
            )
        }
        return ReconciliationResult(evidence: evidence, cursor: .init(lastCheckedAt: .now))
    }

    func beginNotifications(_ action: @escaping @Sendable () -> Void) {
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { _ in action() }
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { _ in action() }
    }

    private func reset() { lastItemID = nil; accumulated = 0; lastPosition = nil; lastObservedAt = nil }
}
