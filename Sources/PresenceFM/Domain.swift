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

    /// Stable HTTPS PNG hosted on the project site so Discord always has a
    /// fetchable platform badge (Simple Icons SVGs are not reliable there).
    var discordSmallImageURL: String {
        let fileName: String
        switch self {
        case .appleMusic: fileName = "apple-music.png"
        case .spotify: fileName = "spotify.png"
        case .youtubeMusic: fileName = "youtubemusic.png"
        case .tidal: fileName = "tidal.png"
        }
        return "https://coolcolby23.github.io/PresenceFM/assets/external-logos/\(fileName)"
    }
}

enum ArtworkReference: Sendable, Hashable, Codable {
    case file(URL)
    case remote(URL)
    case embedded(Data)
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
        let hasMetadata = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isAppleMusicRadio { return hasMetadata }
        return duration > 30 && !isStream && hasMetadata
    }

    var isStream: Bool { source == .radioStream || source == .unsupportedStream }
    var isAppleMusicRadio: Bool { source == .radioStream && platform == .appleMusic }
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
    var scrobbleThreshold: TimeInterval {
        if track.isAppleMusicRadio, track.duration <= 30 { return 30 }
        return min(track.duration * 0.5, 240)
    }

    var scrobblePresentation: ScrobblePresentationState {
        guard track.isScrobbleable else {
            if track.isStream { return .ineligible("This live stream does not provide reliable scrobble metadata.") }
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
    let largeImage: DiscordLargeImage
    let activityType: DiscordActivityType
    let activityName: String
    let largeImageText: String
    let smallImageText: String

    init(
        title: String, state: String, startedAt: Date?, endsAt: Date? = nil,
        appleMusicURL: URL?, artworkURL: URL?,
        buttonLabel: String, platform: PlaybackPlatform = .appleMusic,
        smallImage: DiscordSmallImage = .presenceFM,
        largeImage: DiscordLargeImage = .artwork,
        activityType: DiscordActivityType = .listening,
        activityName: String = "PresenceFM",
        largeImageText: String = "",
        smallImageText: String = ""
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
        self.largeImage = largeImage
        self.activityType = activityType
        self.activityName = activityName
        self.largeImageText = largeImageText
        self.smallImageText = smallImageText
    }
}

enum DiscordActivityType: String, Sendable, CaseIterable, Identifiable {
    case listening = "Listening to"
    case playing = "Playing"
    case watching = "Watching"
    var id: Self { self }

    var payloadValue: Int {
        switch self {
        case .playing: 0
        case .listening: 2
        case .watching: 3
        }
    }
}

enum DiscordTimerStyle: String, Sendable, CaseIterable, Identifiable {
    case elapsed = "Elapsed time"
    case remaining = "Time remaining"
    case hidden = "Hidden"
    var id: Self { self }
}

enum DiscordLargeImage: String, Sendable, CaseIterable, Identifiable {
    case artwork = "Album artwork"
    case playbackPlatform = "Music platform logo"
    case presenceFM = "PresenceFM logo"
    var id: Self { self }
}

enum DiscordSmallImage: String, Sendable, CaseIterable, Identifiable {
    case presenceFM = "PresenceFM logo"
    case playbackPlatform = "Music platform logo"
    case none = "None"
    var id: Self { self }
}

/// A scrobble fetched from Last.fm (`user.getRecentTracks`), including listens from other devices.
struct LastFMRemoteTrack: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let listenedAt: Date?
    let isNowPlaying: Bool
    let imageURL: URL?
    let url: URL?

    init?(json: [String: Any]) {
        let title = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist: String = {
            if let value = json["artist"] as? String { return value }
            if let object = json["artist"] as? [String: Any] {
                return (object["#text"] as? String) ?? (object["name"] as? String) ?? ""
            }
            return ""
        }().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        let album: String? = {
            if let value = json["album"] as? String { return value.isEmpty ? nil : value }
            if let object = json["album"] as? [String: Any] {
                let text = (object["#text"] as? String) ?? ""
                return text.isEmpty ? nil : text
            }
            return nil
        }()

        let attributes = json["@attr"] as? [String: Any]
        let isNowPlaying = (attributes?["nowplaying"] as? String) == "true"
            || (attributes?["nowplaying"] as? Bool) == true

        let listenedAt: Date? = {
            guard let dateObject = json["date"] as? [String: Any] else { return nil }
            if let uts = dateObject["uts"] as? String, let seconds = TimeInterval(uts) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let uts = dateObject["uts"] as? Int {
                return Date(timeIntervalSince1970: TimeInterval(uts))
            }
            return nil
        }()

        let imageURL = Self.bestImageURL(from: json["image"])
        let url = (json["url"] as? String).flatMap(URL.init(string:))
        let idSeed = [
            title,
            artist,
            album ?? "",
            listenedAt.map { String(Int($0.timeIntervalSince1970)) } ?? (isNowPlaying ? "now" : "unknown"),
        ].joined(separator: "|")

        self.id = idSeed
        self.title = title
        self.artist = artist
        self.album = album
        self.listenedAt = listenedAt
        self.isNowPlaying = isNowPlaying
        self.imageURL = imageURL
        self.url = url
    }

    private static func bestImageURL(from value: Any?) -> URL? {
        guard let images = value as? [[String: Any]] else { return nil }
        let preferredSizes = ["extralarge", "large", "medium", "small"]
        for size in preferredSizes {
            if let match = images.first(where: { ($0["size"] as? String) == size }),
               let text = match["#text"] as? String,
               !text.isEmpty,
               let url = URL(string: text)
            {
                return url
            }
        }
        if let last = images.last,
           let text = last["#text"] as? String,
           !text.isEmpty
        {
            return URL(string: text)
        }
        return nil
    }
}

enum ServiceStatus: Sendable, Equatable {
    case disabled
    case inactive
    case awaitingPermission
    case connecting
    case connected
    case offline
    case authorizationExpired
    case failed(String)

    var label: String {
        switch self {
        case .disabled: "Disabled"
        case .inactive: "Not active"
        case .awaitingPermission: "Permission required"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .offline: "Offline"
        case .authorizationExpired: "Authorization expired"
        case .failed(let message): message
        }
    }

    var presentationLabel: String {
        switch self {
        case .failed: "Needs attention"
        default: label
        }
    }

    var detailLabel: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }

    var isConnected: Bool { self == .connected }
}

extension ServiceStatus {
    var integrationState: IntegrationState {
        switch self {
        case .disabled: .disabled
        case .inactive: .inactive
        case .awaitingPermission: .permissionRequired
        case .connecting: .connecting
        case .connected: .connected
        case .offline: .offline
        case .authorizationExpired: .authorizationExpired
        case .failed: .failed
        }
    }
}

protocol PlaybackProviding: Sendable { func snapshots() async -> AsyncStream<PlaybackMonitorUpdate> }
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
