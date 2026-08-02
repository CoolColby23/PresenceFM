import Foundation

struct DiscordPresenceProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var activityType: String
    var activityName: String
    var lineOne: String
    var lineTwo: String
    var customLineOne: String
    var customLineTwo: String
    var showAlbum: Bool
    var timerStyle: String
    var sharePaused: Bool
    var pausedText: String
    var largeImage: String
    var largeImageText: String
    var smallImage: String
    var smallImageText: String
    var showLink: Bool
    var buttonLabel: String

    static let balanced = DiscordPresenceProfile(
        id: UUID(uuidString: "BA1A0000-0000-4000-8000-000000000001")!,
        name: "Balanced", activityType: DiscordActivityType.listening.rawValue,
        activityName: "PresenceFM", lineOne: DiscordLineFormat.title.rawValue,
        lineTwo: DiscordLineFormat.artistAndAlbum.rawValue,
        customLineOne: "Listening to {artist}", customLineTwo: "{title} • {album}",
        showAlbum: true, timerStyle: DiscordTimerStyle.remaining.rawValue,
        sharePaused: false, pausedText: "Paused • {artist}",
        largeImage: DiscordLargeImage.artwork.rawValue, largeImageText: "{album}",
        smallImage: DiscordSmallImage.playbackPlatform.rawValue,
        smallImageText: "Playing on {platform}", showLink: true, buttonLabel: ""
    )

    static let minimal = DiscordPresenceProfile(
        id: UUID(uuidString: "BA1A0000-0000-4000-8000-000000000002")!,
        name: "Minimal", activityType: DiscordActivityType.listening.rawValue,
        activityName: "PresenceFM", lineOne: DiscordLineFormat.title.rawValue,
        lineTwo: DiscordLineFormat.artist.rawValue,
        customLineOne: "{title}", customLineTwo: "{artist}", showAlbum: false,
        timerStyle: DiscordTimerStyle.hidden.rawValue, sharePaused: false,
        pausedText: "Paused", largeImage: DiscordLargeImage.artwork.rawValue,
        largeImageText: "", smallImage: DiscordSmallImage.none.rawValue,
        smallImageText: "", showLink: false, buttonLabel: ""
    )

    static let detailed = DiscordPresenceProfile(
        id: UUID(uuidString: "BA1A0000-0000-4000-8000-000000000003")!,
        name: "Detailed", activityType: DiscordActivityType.listening.rawValue,
        activityName: "PresenceFM", lineOne: DiscordLineFormat.custom.rawValue,
        lineTwo: DiscordLineFormat.custom.rawValue,
        customLineOne: "{title} • {position}/{duration}",
        customLineTwo: "{artist} — {album}", showAlbum: true,
        timerStyle: DiscordTimerStyle.remaining.rawValue, sharePaused: true,
        pausedText: "Paused • {artist}", largeImage: DiscordLargeImage.artwork.rawValue,
        largeImageText: "{album}", smallImage: DiscordSmallImage.playbackPlatform.rawValue,
        smallImageText: "Playing on {platform}", showLink: true, buttonLabel: ""
    )

    static let builtIns = [balanced, minimal, detailed]

    @MainActor
    static func capture(name: String, preferences: Preferences, id: UUID = UUID()) -> Self {
        Self(
            id: id, name: name, activityType: preferences.discordActivityType.rawValue,
            activityName: preferences.discordActivityName,
            lineOne: preferences.discordLineOne.rawValue,
            lineTwo: preferences.discordLineTwo.rawValue,
            customLineOne: preferences.discordCustomLineOne,
            customLineTwo: preferences.discordCustomLineTwo,
            showAlbum: preferences.showAlbum, timerStyle: preferences.discordTimerStyle.rawValue,
            sharePaused: preferences.discordSharePaused, pausedText: preferences.discordPausedText,
            largeImage: preferences.discordLargeImage.rawValue,
            largeImageText: preferences.discordLargeImageText,
            smallImage: preferences.discordSmallImage.rawValue,
            smallImageText: preferences.discordSmallImageText,
            showLink: preferences.showLink, buttonLabel: preferences.discordButtonLabel
        )
    }

    @MainActor
    func apply(to preferences: Preferences) {
        preferences.discordActivityType = DiscordActivityType(rawValue: activityType) ?? .listening
        preferences.discordActivityName = activityName
        preferences.discordLineOne = DiscordLineFormat(rawValue: lineOne) ?? .title
        preferences.discordLineTwo = DiscordLineFormat(rawValue: lineTwo) ?? .artistAndAlbum
        preferences.discordCustomLineOne = customLineOne
        preferences.discordCustomLineTwo = customLineTwo
        preferences.showAlbum = showAlbum
        preferences.discordTimerStyle = DiscordTimerStyle(rawValue: timerStyle) ?? .remaining
        preferences.discordSharePaused = sharePaused
        preferences.discordPausedText = pausedText
        preferences.discordLargeImage = DiscordLargeImage(rawValue: largeImage) ?? .artwork
        preferences.discordLargeImageText = largeImageText
        preferences.discordSmallImage = DiscordSmallImage(rawValue: smallImage) ?? .playbackPlatform
        preferences.discordSmallImageText = smallImageText
        preferences.showLink = showLink
        preferences.discordButtonLabel = buttonLabel
    }
}

struct ScrobbleExclusionRules: Equatable {
    let artists: [String]
    let albums: [String]
    let titleTerms: [String]
    let platforms: Set<PlaybackPlatform>

    init(
        artistsText: String, albumsText: String, titleTermsText: String,
        platforms: Set<PlaybackPlatform>
    ) {
        artists = Self.values(in: artistsText)
        albums = Self.values(in: albumsText)
        titleTerms = Self.values(in: titleTermsText)
        self.platforms = platforms
    }

    func reason(for track: TrackMetadata) -> String? {
        if platforms.contains(track.platform) {
            return "Scrobbling is disabled for \(track.platform.rawValue)."
        }
        let artist = normalized(track.artist)
        if artists.contains(where: { normalized($0) == artist }) {
            return "This artist is excluded from scrobbling."
        }
        if let album = track.album.map(normalized),
            albums.contains(where: { normalized($0) == album })
        {
            return "This album is excluded from scrobbling."
        }
        let title = normalized(track.title)
        if titleTerms.contains(where: { title.contains(normalized($0)) }) {
            return "This track matches an excluded title term."
        }
        return nil
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func values(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

extension Preferences {
    var availableDiscordProfiles: [DiscordPresenceProfile] {
        DiscordPresenceProfile.builtIns + discordPresenceProfiles
    }

    var scrobbleExclusionRules: ScrobbleExclusionRules {
        ScrobbleExclusionRules(
            artistsText: excludedScrobbleArtists,
            albumsText: excludedScrobbleAlbums,
            titleTermsText: excludedScrobbleTitleTerms,
            platforms: excludedScrobblePlatforms
        )
    }
}
