import Foundation

struct TrackIdentity: Sendable, Hashable, Codable {
    let persistentID: String
}

enum TrackSource: String, Sendable, Codable, CaseIterable {
    case appleMusicCatalog, matchedOrUploaded, localFile, radioStream, unsupportedStream
}

enum PlaybackPlatform: String, Sendable, Codable, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    case tidal = "TIDAL"

    var id: Self { self }
    var discordSmallImageURL: String {
        let icon: String
        switch self {
        case .appleMusic: icon = "applemusic/FA243C"
        case .spotify: icon = "spotify/1ED760"
        case .youtubeMusic: icon = "youtubemusic/FF0033"
        case .tidal: icon = "tidal/000000"
        }
        return "https://wsrv.nl/?url=cdn.simpleicons.org/\(icon)&output=png&w=512&h=512"
    }
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
    let platform: PlaybackPlatform

    init(
        identity: TrackIdentity, title: String, artist: String, album: String?,
        duration: TimeInterval, source: TrackSource, appleMusicURL: URL?,
        artworkReference: ArtworkReference?, platform: PlaybackPlatform = .appleMusic
    ) {
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.source = source
        self.appleMusicURL = appleMusicURL
        self.artworkReference = artworkReference
        self.platform = platform
    }

    private enum CodingKeys: String, CodingKey {
        case identity, title, artist, album, duration, source, appleMusicURL, artworkReference, platform
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identity = try values.decode(TrackIdentity.self, forKey: .identity)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decode(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        source = try values.decode(TrackSource.self, forKey: .source)
        appleMusicURL = try values.decodeIfPresent(URL.self, forKey: .appleMusicURL)
        artworkReference = try values.decodeIfPresent(ArtworkReference.self, forKey: .artworkReference)
        platform = try values.decodeIfPresent(PlaybackPlatform.self, forKey: .platform) ?? .appleMusic
    }

    var isScrobbleable: Bool {
        duration > 30 && !isStream &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isStream: Bool { source == .radioStream || source == .unsupportedStream }
    var supportsFiniteProgress: Bool { duration > 0 && !isStream }
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
enum SessionOutcome: String, Sendable, Codable {
    case active, played, listened, skipped, interrupted, queued, submitted, failed
}

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

enum ScrobblePresentationState: Sendable, Equatable {
    case ineligible(String)
    case listening(progress: Double, remaining: TimeInterval)
    case ready
    case queued
    case submitted

    var label: String {
        switch self {
        case .ineligible: "Not eligible"
        case .listening: "Listening"
        case .ready: "Ready to scrobble"
        case .queued: "Queued"
        case .submitted: "Scrobbled"
        }
    }
}

extension PlaybackSession {
    var scrobbleThreshold: TimeInterval { min(track.duration * 0.5, 240) }

    var scrobblePresentation: ScrobblePresentationState {
        guard track.isScrobbleable else {
            if track.isStream { return .ineligible("Radio is shown in PresenceFM but is not scrobbled.") }
            if track.duration <= 30 { return .ineligible("Tracks must be longer than 30 seconds.") }
            return .ineligible("Complete title and artist metadata are required.")
        }
        switch outcome {
        case .queued: return .queued
        case .submitted: return .submitted
        default: break
        }
        if eligibility == .eligible { return .ready }
        let threshold = scrobbleThreshold
        return .listening(
            progress: threshold > 0 ? min(1, accumulatedPlayTime / threshold) : 0,
            remaining: max(0, threshold - accumulatedPlayTime)
        )
    }
}

struct DiscordPresence: Sendable, Equatable {
    let title: String
    let state: String
    let startedAt: Date?
    let endsAt: Date?
    let appleMusicURL: URL?
    let artworkURL: URL?
    let buttonLabel: String
    let platform: PlaybackPlatform
    let smallImage: DiscordSmallImage

    init(
        title: String, state: String, startedAt: Date?, endsAt: Date? = nil,
        appleMusicURL: URL?, artworkURL: URL?,
        buttonLabel: String, platform: PlaybackPlatform = .appleMusic,
        smallImage: DiscordSmallImage = .presenceFM
    ) {
        self.title = title
        self.state = state
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.appleMusicURL = appleMusicURL
        self.artworkURL = artworkURL
        self.buttonLabel = buttonLabel
        self.platform = platform
        self.smallImage = smallImage
    }
}

enum DiscordSmallImage: String, Sendable, CaseIterable, Identifiable {
    case presenceFM = "PresenceFM logo"
    case playbackPlatform = "Music platform logo"
    case none = "None"
    var id: Self { self }
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

extension ServiceStatus {
    var integrationState: IntegrationState {
        switch self {
        case .disabled: .disabled
        case .awaitingPermission: .permissionRequired
        case .connecting: .connecting
        case .connected: .connected
        case .offline: .offline
        case .authorizationExpired: .authorizationExpired
        case .failed: .failed
        }
    }
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
