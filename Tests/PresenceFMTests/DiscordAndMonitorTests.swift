import Foundation
import Testing
@testable import PresenceFM

@Suite("Discord customization")
struct DiscordCustomizationTests {
    @Test @MainActor func factoryBuildsCountdownImagesHoverTextAndActivityStyle() throws {
        let defaults = try #require(UserDefaults(suiteName: "PresenceFMTests.discord-customization.\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults)
        preferences.discordActivityType = .watching
        preferences.discordActivityName = "On {platform}"
        preferences.discordLineOne = .custom
        preferences.discordCustomLineOne = "{title} • {position}/{duration}"
        preferences.discordLineTwo = .custom
        preferences.discordCustomLineTwo = "{artist} — {album}"
        preferences.discordTimerStyle = .remaining
        preferences.discordLargeImage = .playbackPlatform
        preferences.discordSmallImage = .presenceFM
        preferences.discordLargeImageText = "{album} on {platform}"
        preferences.discordSmallImageText = "Shared by PresenceFM"

        let now = Date(timeIntervalSince1970: 2_000)
        let track = TrackMetadata(
            identity: .init(persistentID: "discord-custom"), title: "Midnight Drive",
            artist: "The Satellites", album: "Afterglow", duration: 224,
            source: .appleMusicCatalog, appleMusicURL: URL(string: "https://example.com/listen"),
            artworkReference: nil, platform: .spotify
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: now.addingTimeInterval(-82),
            accumulatedPlayTime: 82, lastPosition: 82, eligibility: .listening, outcome: .active
        )
        let snapshot = PlaybackSnapshot(
            track: track, state: .playing, position: 82, observedAt: now, confidence: .high
        )

        let presence = DiscordPresenceFactory.make(
            session: session, snapshot: snapshot, preferences: preferences,
            artworkURL: URL(string: "https://example.com/art.jpg"), now: now
        )
        #expect(presence.title == "Midnight Drive • 1:22/3:44")
        #expect(presence.state == "The Satellites — Afterglow")
        #expect(presence.activityName == "On Spotify")
        #expect(presence.startedAt == nil)
        #expect(presence.endsAt == now.addingTimeInterval(142))

        let payload = DiscordPresenceClient.activityPayload(for: presence)
        #expect(payload["type"] as? Int == 3)
        #expect(payload["name"] as? String == "On Spotify")
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["large_image"] == PlaybackPlatform.spotify.discordSmallImageURL)
        #expect(assets["large_text"] == "Afterglow on Spotify")
        #expect(assets["small_text"] == "Shared by PresenceFM")
        let timestamps = try #require(payload["timestamps"] as? [String: Int])
        #expect(timestamps["start"] == nil)
        #expect(timestamps["end"] == Int(2_142.0 * 1_000))
    }

    @Test @MainActor func pausedPresenceUsesPausedTemplateAndNeverShowsTimer() throws {
        let defaults = try #require(UserDefaults(suiteName: "PresenceFMTests.discord-paused.\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults)
        preferences.discordPausedText = "{state} at {position}"
        preferences.discordTimerStyle = .elapsed
        let track = TrackMetadata(
            identity: .init(persistentID: "paused"), title: "Track", artist: "Artist",
            album: nil, duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 45,
            lastPosition: 45, eligibility: .listening, outcome: .active
        )
        let snapshot = PlaybackSnapshot(track: track, state: .paused, position: 45, observedAt: .now, confidence: .high)
        let presence = DiscordPresenceFactory.make(
            session: session, snapshot: snapshot, preferences: preferences, artworkURL: nil, now: .now
        )
        #expect(presence.state == "Paused at 0:45")
        #expect(presence.startedAt == nil)
        #expect(presence.endsAt == nil)
    }
}

@Suite("Playback monitor reporting")
struct PlaybackMonitorReportingTests {
    @Test func updateIncludesPerProviderHealthAndTiming() async throws {
        let now = Date()
        let track = TrackMetadata(
            identity: .init(persistentID: "health"), title: "Track", artist: "Artist",
            album: nil, duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let playback = PlaybackSnapshot(track: track, state: .playing, position: 1, observedAt: now, confidence: .high)
        let provider = StubPlaybackProvider(
            id: .appleMusic,
            value: ProviderSnapshot(provider: .appleMusic, playback: playback, health: .available, observedAt: now)
        )
        let monitor = PlaybackMonitor(credentials: CredentialStore(), providers: [.appleMusic: provider])
        await monitor.setEnabledProviders([.appleMusic])
        let stream = await monitor.snapshots()
        var iterator = stream.makeAsyncIterator()
        let update = try #require(await iterator.next())
        await monitor.stop()

        #expect(update.playback.track?.identity == track.identity)
        #expect(update.providerHealth[.appleMusic] == .available)
        #expect(update.providerHealth[.spotify] == .disabled)
        #expect(update.providerHealth[.youtubeMusic] == .disabled)
        #expect(update.providerHealth[.tidal] == .disabled)
        #expect(update.metrics.providerDurations[.appleMusic] != nil)
    }
}

private struct StubPlaybackProvider: PlaybackProvider {
    let id: PlaybackProviderID
    let value: ProviderSnapshot
    func snapshot() async -> ProviderSnapshot { value }
}
