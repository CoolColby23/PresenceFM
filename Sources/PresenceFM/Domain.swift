import Foundation

struct TrackIdentity: Sendable, Hashable, Codable {
    let persistentID: String
}

enum TrackSource: String, Sendable, Codable, CaseIterable {
    case appleMusicCatalog, matchedOrUploaded, localFile, unsupportedStream
}

enum ArtworkReference: Sendable, Hashable, Codable {
    case file(URL)
}

struct TrackMetadata: Sendable, Hashable, Codable {
    let identity: TrackIdentity
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
    let source: TrackSource
    let appleMusicURL: URL?
    let artworkReference: ArtworkReference?

    var isScrobbleable: Bool {
        duration > 30 && source != .unsupportedStream &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum PlaybackState: String, Sendable, Codable { case stopped, paused, playing }
enum MetadataConfidence: String, Sendable, Codable { case low, medium, high }

struct PlaybackSnapshot: Sendable, Hashable {
    let track: TrackMetadata?
    let state: PlaybackState
    let position: TimeInterval
    let observedAt: Date
    let confidence: MetadataConfidence
}

enum ScrobbleEligibility: String, Sendable, Codable { case ineligible, listening, eligible }
enum SessionOutcome: String, Sendable, Codable { case active, played, skipped, queued, submitted, failed }

struct PlaybackSession: Identifiable, Sendable, Codable, Hashable {
    let id: UUID
    let track: TrackMetadata
    let startedAt: Date
    var accumulatedPlayTime: TimeInterval
    var lastPosition: TimeInterval
    var eligibility: ScrobbleEligibility
    var outcome: SessionOutcome

    var duplicateKey: String {
        let minute = Int(startedAt.timeIntervalSince1970 / 60)
        return "\(track.identity.persistentID)|\(track.artist.normalized)|\(track.title.normalized)|\(minute)"
    }
}

struct DiscordPresence: Sendable, Equatable {
    let title: String
    let state: String
    let startedAt: Date?
    let appleMusicURL: URL?
}

enum ServiceStatus: Sendable, Equatable {
    case disabled
    case awaitingPermission
    case connecting
    case connected
    case offline
    case authorizationExpired
    case failed(String)

    var label: String {
        switch self {
        case .disabled: "Disabled"
        case .awaitingPermission: "Permission required"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .offline: "Offline"
        case .authorizationExpired: "Authorization expired"
        case .failed(let message): message
        }
    }

    var isConnected: Bool { self == .connected }
}

protocol PlaybackProviding: Sendable { func snapshots() async -> AsyncStream<PlaybackSnapshot> }
protocol PresencePublishing: Sendable {
    func publish(_ presence: DiscordPresence) async throws
    func clear() async
}
protocol Scrobbling: Sendable {
    func updateNowPlaying(_ session: PlaybackSession) async throws
    func enqueueScrobble(_ session: PlaybackSession) async
}

protocol ScrobbleSubmitting: Sendable {
    func scrobble(title: String, artist: String, album: String?, duration: Double, startedAt: Date) async throws
}

extension String {
    fileprivate var normalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
