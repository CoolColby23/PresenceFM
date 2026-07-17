import Foundation

/// Deterministic, credential-free playback used for demos and judge evaluation.
/// The short tracks exercise the real eligibility and history pipeline quickly.
enum DemoPlaybackSequence {
    static let trackDuration: TimeInterval = 32
    static let gapDuration: TimeInterval = 4
    static let cycleDuration = trackDuration + gapDuration

    private struct DemoTrack {
        let title: String
        let artist: String
        let album: String
        let platform: PlaybackPlatform
    }

    private static let tracks = [
        DemoTrack(title: "Midnight Signal", artist: "The Satellites", album: "Afterglow", platform: .appleMusic),
        DemoTrack(title: "Electric Morning", artist: "Neon Valley", album: "Daybreak", platform: .spotify),
        DemoTrack(title: "Open Skies", artist: "Northbound", album: "Windows Down", platform: .youtubeMusic)
    ]

    static func snapshot(at now: Date, startedAt: Date) -> PlaybackSnapshot {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let cycleIndex = Int(elapsed / cycleDuration)
        let position = elapsed.truncatingRemainder(dividingBy: cycleDuration)

        guard position < trackDuration else {
            return PlaybackSnapshot(
                track: nil, state: .stopped, position: 0,
                observedAt: now, confidence: .high
            )
        }

        let value = tracks[cycleIndex % tracks.count]
        let track = TrackMetadata(
            identity: .init(persistentID: "presencefm-demo-\(cycleIndex)"),
            title: value.title,
            artist: value.artist,
            album: value.album,
            duration: trackDuration,
            source: .localFile,
            appleMusicURL: nil,
            artworkReference: nil,
            platform: value.platform
        )
        return PlaybackSnapshot(
            track: track, state: .playing, position: position,
            observedAt: now, confidence: .high
        )
    }
}
