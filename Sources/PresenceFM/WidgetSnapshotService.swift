import Foundation
import WidgetKit

struct PresenceFMWidgetSnapshot: Codable, Equatable {
    let title: String
    let artist: String
    let platform: String
    let state: String
    let position: TimeInterval
    let duration: TimeInterval
    let observedAt: Date
    let isPrivate: Bool
}

@MainActor
enum WidgetSnapshotService {
    static let kind = "PresenceFMNowPlaying"
    static let suiteName = "group.fm.presence.PresenceFM"
    static let storageKey = "widgetSnapshot"
    private static var lastSignature = ""

    static func publish(_ playback: PlaybackSnapshot, isPrivate: Bool) {
        let snapshot = PresenceFMWidgetSnapshot(
            title: playback.track?.title ?? "Nothing Playing",
            artist: playback.track?.artist ?? "Open PresenceFM to start listening",
            platform: playback.track?.platform.rawValue ?? "PresenceFM",
            state: playback.state.rawValue,
            position: playback.position,
            duration: playback.track?.duration ?? 0,
            observedAt: playback.observedAt,
            isPrivate: isPrivate
        )
        let signature = [
            playback.track?.identity.persistentID ?? "none",
            playback.state.rawValue,
            String(Int(playback.position / 30)),
            isPrivate ? "private" : "public",
        ].joined(separator: "|")
        guard signature != lastSignature else { return }
        lastSignature = signature
        guard let defaults = UserDefaults(suiteName: suiteName),
            let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
