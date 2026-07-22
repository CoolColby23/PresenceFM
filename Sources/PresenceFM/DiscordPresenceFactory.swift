import Foundation

enum DiscordPresenceFactory {
    @MainActor
    static func make(
        session: PlaybackSession,
        snapshot: PlaybackSnapshot,
        preferences: Preferences,
        artworkURL: URL?,
        now: Date
    ) -> DiscordPresence {
        let album = preferences.showAlbum ? (session.track.album ?? "") : ""
        let lineOne = template(
            format: preferences.discordLineOne,
            custom: preferences.discordCustomLineOne,
            track: session.track,
            album: album
        )
        let lineTwo = template(
            format: preferences.discordLineTwo,
            custom: preferences.discordCustomLineTwo,
            track: session.track,
            album: album
        )
        let playbackState = snapshot.state == .paused ? "Paused" : "Playing"
        let stateTemplate = snapshot.state == .paused ? preferences.discordPausedText : lineTwo
        let render: (String) -> String = { value in
            DiscordTemplate.render(
                value, title: session.track.title, artist: session.track.artist,
                album: album, platform: session.track.platform,
                playbackState: playbackState, position: snapshot.position,
                duration: session.track.duration
            )
        }
        let supportsTimer = snapshot.state == .playing && session.track.supportsFiniteProgress
        let startedAt =
            supportsTimer && preferences.discordTimerStyle == .elapsed
            ? now.addingTimeInterval(-snapshot.position) : nil
        let endsAt =
            supportsTimer && preferences.discordTimerStyle == .remaining
            ? now.addingTimeInterval(max(0, session.track.duration - snapshot.position)) : nil

        return DiscordPresence(
            title: render(lineOne), state: render(stateTemplate),
            startedAt: startedAt, endsAt: endsAt,
            appleMusicURL: preferences.showLink ? session.track.appleMusicURL : nil,
            artworkURL: artworkURL, buttonLabel: preferences.discordButtonLabel,
            platform: session.track.platform, smallImage: preferences.discordSmallImage,
            largeImage: preferences.discordLargeImage, activityType: preferences.discordActivityType,
            activityName: render(preferences.discordActivityName),
            largeImageText: render(preferences.discordLargeImageText),
            smallImageText: render(preferences.discordSmallImageText)
        )
    }

    private static func template(
        format: DiscordLineFormat,
        custom: String,
        track: TrackMetadata,
        album: String
    ) -> String {
        format == .custom
            ? custom
            : format.value(title: track.title, artist: track.artist, album: album)
    }
}
