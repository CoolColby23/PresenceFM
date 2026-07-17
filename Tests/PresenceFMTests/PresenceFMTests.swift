import Foundation
import AppKit
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

    @Test func eligibleTrackRemainsActiveUntilPlaybackStops() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 0, observedAt: start, confidence: .high))

        let thresholdEvents = await tracker.ingest(.init(track: track, state: .playing, position: 50, observedAt: start.addingTimeInterval(50), confidence: .high))

        #expect(thresholdEvents.contains { if case .eligible = $0 { true } else { false } })
        #expect(!thresholdEvents.contains { if case .finalized = $0 { true } else { false } })
        #expect(await tracker.active?.outcome == .active)
    }

    @Test func stoppingAfterEligibilityFinalizesTrackAsPlayed() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 0, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 50, observedAt: start.addingTimeInterval(50), confidence: .high))

        let events = await tracker.ingest(.init(track: nil, state: .stopped, position: 0, observedAt: start.addingTimeInterval(51), confidence: .high))
        let finalized = events.compactMap { event -> PlaybackSession? in
            guard case .finalized(let session) = event else { return nil }
            return session
        }.first

        #expect(finalized?.outcome == .played)
        #expect(await tracker.active == nil)
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

    @Test func listeningPresentationReportsProgressAndRemainingTime() {
        var session = PlaybackSession(id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 25, lastPosition: 25, eligibility: .listening, outcome: .active)
        guard case .listening(let progress, let remaining) = session.scrobblePresentation else {
            Issue.record("Expected listening presentation")
            return
        }
        #expect(progress == 0.5)
        #expect(remaining == 25)
        session.accumulatedPlayTime = 50
        session.eligibility = .eligible
        #expect(session.scrobblePresentation == .ready)
    }

    @Test func ineligiblePresentationExplainsStreams() {
        let stream = TrackMetadata(identity: .init(persistentID: "radio"), title: "Station", artist: "Host", album: nil, duration: 3_600, source: .unsupportedStream, appleMusicURL: nil, artworkReference: nil)
        let session = PlaybackSession(id: UUID(), track: stream, startedAt: .now, accumulatedPlayTime: 0, lastPosition: 0, eligibility: .ineligible, outcome: .active)
        #expect(session.scrobblePresentation == .ineligible("Radio streams are not scrobbled."))
    }
}

@Suite("Artwork")
struct ArtworkTests {
    @Test @MainActor func finalizedArtworkIsPersistedWithHistory() throws {
        let store = try PersistenceStore(inMemory: true)
        let artworkData = try #require(Self.imageData())
        let track = TrackMetadata(
            identity: .init(persistentID: "history-artwork"), title: "Track", artist: "Artist",
            album: "Album", duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 100,
            lastPosition: 100, eligibility: .eligible, outcome: .played
        )

        store.record(session, artworkData: artworkData)

        let record = try #require(store.context.fetch(FetchDescriptor<ActivityRecord>()).first)
        #expect(record.artworkData == artworkData)
    }

    @Test @MainActor func replayedTrackBackfillsMissingHistoryArtwork() throws {
        let store = try PersistenceStore(inMemory: true)
        let artworkData = try #require(Self.imageData())
        let track = TrackMetadata(
            identity: .init(persistentID: "replayed-track"), title: "Track", artist: "Artist",
            album: "Album", duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 100,
            lastPosition: 100, eligibility: .eligible, outcome: .played
        )
        store.record(session)

        store.backfillArtwork(for: track.identity.persistentID, artworkData: artworkData)

        let record = try #require(store.context.fetch(FetchDescriptor<ActivityRecord>()).first)
        #expect(record.artworkData == artworkData)
    }

    @Test func usesAValidFileArtworkReferenceBeforePlayerLookup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("cover.png")
        let imageData = try #require(Self.imageData())
        try imageData.write(to: source)
        let track = TrackMetadata(
            identity: .init(persistentID: "file-artwork"), title: "Track", artist: "Artist",
            album: "Album", duration: 180, source: .localFile, appleMusicURL: nil,
            artworkReference: .file(source)
        )
        let service = ArtworkService(directory: directory.appendingPathComponent("cache"))
        #expect(await service.artwork(for: track) == imageData)
        #expect(await service.cachedArtwork(for: track.identity) == imageData)
    }

    @Test func rejectsCorruptArtworkAndBoundsMemoryCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ArtworkService(memoryLimit: 2, diskLimit: 2, directory: directory)
        #expect(await !service.cache(Data("not an image".utf8), for: .init(persistentID: "bad")))
        let imageData = try #require(Self.imageData())
        #expect(await service.cache(imageData, for: .init(persistentID: "1")))
        #expect(await service.cache(imageData, for: .init(persistentID: "2")))
        #expect(await service.cache(imageData, for: .init(persistentID: "3")))
        #expect(await service.memoryEntryCount == 2)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
    }

    private static func imageData() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

@Suite("Discord presence")
struct DiscordPresenceTests {
    @Test func externalArtworkURLIsSentAsLargeImage() throws {
        let artworkURL = try #require(URL(string: "https://example.com/album.jpg"))
        let presence = DiscordPresence(
            title: "Track", state: "Artist • Album", startedAt: nil,
            appleMusicURL: nil, artworkURL: artworkURL, buttonLabel: "Listen"
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["large_image"] == artworkURL.absoluteString)
        #expect(assets["large_text"] == nil)
        #expect(assets["small_image"] == "presencefm")
    }

    @Test func platformLogoCanBeUsedAsSmallImage() throws {
        let presence = DiscordPresence(
            title: "Track", state: "Artist", startedAt: nil, appleMusicURL: nil,
            artworkURL: nil, buttonLabel: "Listen", platform: .spotify,
            smallImage: .playbackPlatform
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["small_image"] == "spotify")
        #expect(assets["small_text"] == "Playing on Spotify")
    }

    @Test func discordCanHideSmallImageTimerAndLink() throws {
        let presence = DiscordPresence(
            title: "Track", state: "Artist", startedAt: nil, appleMusicURL: nil,
            artworkURL: nil, buttonLabel: "", platform: .tidal, smallImage: .none
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["small_image"] == nil)
        #expect(payload["timestamps"] == nil)
        #expect(payload["buttons"] == nil)
    }

    @Test func emptyButtonLabelUsesCurrentPlatform() throws {
        let url = try #require(URL(string: "https://open.spotify.com/track/abc"))
        let presence = DiscordPresence(
            title: "Track", state: "Artist", startedAt: nil, appleMusicURL: url,
            artworkURL: nil, buttonLabel: "", platform: .spotify
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let buttons = try #require(payload["buttons"] as? [[String: String]])
        #expect(buttons.first?["label"] == "Listen on Spotify")
    }

    @Test func lineFormatsHandleHiddenAlbum() {
        #expect(DiscordLineFormat.album.value(title: "Track", artist: "Artist", album: "") == "Artist")
        #expect(DiscordLineFormat.artistAndAlbum.value(title: "Track", artist: "Artist", album: "") == "Artist")
        #expect(DiscordLineFormat.artistAndAlbum.value(title: "Track", artist: "Artist", album: "Album") == "Artist • Album")
    }

    @Test func customTemplatesRenderMetadataAndCleanMissingAlbumSeparator() {
        #expect(DiscordTemplate.render("Listening to {artist}", title: "Track", artist: "Artist", album: "Album", platform: .spotify) == "Listening to Artist")
        #expect(DiscordTemplate.render("{title} • {album}", title: "Track", artist: "Artist", album: "", platform: .spotify) == "Track")
        #expect(DiscordTemplate.render("On {platform}", title: "Track", artist: "Artist", album: "Album", platform: .spotify) == "On Spotify")
    }

    @Test func discordPresenceIncludesTrackProgressWithoutRepeatingArtworkContext() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(180)
        let artworkURL = try #require(URL(string: "https://example.com/art.jpg"))
        let presence = DiscordPresence(
            title: "Track", state: "Artist • Album", startedAt: start, endsAt: end,
            appleMusicURL: nil, artworkURL: artworkURL,
            buttonLabel: "", platform: .spotify, smallImage: .playbackPlatform
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let timestamps = try #require(payload["timestamps"] as? [String: Int])
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(timestamps["start"] == 1_000_000)
        #expect(timestamps["end"] == 1_180_000)
        #expect(assets["large_text"] == nil)
        #expect(assets["small_image"] == "spotify")
    }

    @Test func discordTextIsTrimmedBoundedAndNeverBlank() throws {
        let presence = DiscordPresence(
            title: String(repeating: "T", count: 200), state: "   ", startedAt: nil,
            appleMusicURL: nil, artworkURL: nil, buttonLabel: "", platform: .tidal
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let details = try #require(payload["details"] as? String)
        let state = try #require(payload["state"] as? String)
        #expect(details.count == 128)
        #expect(state == "TIDAL")
    }

    @Test func bundledAssetIsUsedUntilArtworkArrives() throws {
        let presence = DiscordPresence(
            title: "Track", state: "Artist", startedAt: nil,
            appleMusicURL: nil, artworkURL: nil, buttonLabel: "Listen"
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["large_image"] == "presencefm")
    }
}

@Suite("Additional playback platforms")
struct AdditionalPlaybackPlatformTests {
    private let separator = String(UnicodeScalar(30)!)

    @Test func parsesSpotifyPlayingAndPausedStates() throws {
        let playing = ["playing", "Track", "Artist", "Album", "180000", "42.5", "spotify:track:abc", "spotify:track:abc"].joined(separator: separator)
        let paused = ["paused", "Track", "Artist", "Album", "180000", "43", "spotify:track:abc", "spotify:track:abc"].joined(separator: separator)
        let playingSnapshot = try #require(PlaybackMonitor.parseSpotify(playing))
        let pausedSnapshot = try #require(PlaybackMonitor.parseSpotify(paused))
        #expect(playingSnapshot.state == .playing)
        #expect(pausedSnapshot.state == .paused)
        #expect(playingSnapshot.track?.duration == 180)
        #expect(playingSnapshot.track?.platform == .spotify)
    }

    @Test func rejectsStoppedAndMalformedSpotifyState() {
        #expect(PlaybackMonitor.parseSpotify("stopped") == nil)
        #expect(PlaybackMonitor.parseSpotify("playing\(separator)Incomplete") == nil)
    }

    @Test func sourceSelectionPrefersPlayingAndRecoversAfterProviderLoss() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let stopped = PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .high)
        let spotifyValue = ["playing", "Track", "Artist", "Album", "180000", "10", "spotify:track:abc", "spotify:track:abc"].joined(separator: separator)
        let spotify = try #require(PlaybackMonitor.parseSpotify(spotifyValue, observedAt: now))
        let youtubeData = Data(#"{"player":{"trackState":1,"videoProgress":4},"video":{"author":"YT Artist","title":"YT Track","durationSeconds":200,"id":"yt","isLive":false}}"#.utf8)
        let parsedYouTube = try YTMDesktopClient.parseSnapshot(youtubeData, observedAt: now)
        let youtube = try #require(parsedYouTube)

        #expect(PlaybackSourceSelector.select(music: stopped, spotify: spotify, youtube: youtube, tidal: nil).track?.platform == .spotify)
        #expect(PlaybackSourceSelector.select(music: stopped, spotify: nil, youtube: youtube, tidal: nil).track?.platform == .youtubeMusic)
        #expect(PlaybackSourceSelector.select(music: stopped, spotify: nil, youtube: nil, tidal: nil).state == .stopped)
    }

    @Test func permissionFailureDoesNotMaskAnotherPlayingProvider() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let deniedMusic = PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .low)
        let spotifyValue = ["playing", "Track", "Artist", "Album", "180000", "10", "spotify:track:abc", "spotify:track:abc"].joined(separator: separator)
        let spotify = try #require(PlaybackMonitor.parseSpotify(spotifyValue, observedAt: now))
        #expect(PlaybackSourceSelector.select(music: deniedMusic, spotify: spotify, youtube: nil, tidal: nil).track?.platform == .spotify)
    }

    @Test func parsesYTMDesktopCompanionState() throws {
        let data = Data(#"{"player":{"trackState":1,"videoProgress":42.5},"video":{"author":"Artist","title":"Track","album":"Album","durationSeconds":180,"id":"abc123","isLive":false}}"#.utf8)
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let parsed = try YTMDesktopClient.parseSnapshot(data, observedAt: observedAt)
        let snapshot = try #require(parsed)
        #expect(snapshot.state == .playing)
        #expect(snapshot.position == 42.5)
        #expect(snapshot.observedAt == observedAt)
        #expect(snapshot.track?.platform == .youtubeMusic)
        #expect(snapshot.track?.appleMusicURL?.absoluteString == "https://music.youtube.com/watch?v=abc123")
    }

    @Test func liveYTMDesktopVideoIsNotScrobbleable() throws {
        let data = Data(#"{"player":{"trackState":1,"videoProgress":4},"video":{"author":"Station","title":"Live","durationSeconds":3600,"id":"live","isLive":true}}"#.utf8)
        let parsed = try YTMDesktopClient.parseSnapshot(data)
        let snapshot = try #require(parsed)
        #expect(snapshot.track?.source == .unsupportedStream)
        #expect(snapshot.track?.isScrobbleable == false)
    }
}

@Suite("Last.fm transport", .serialized)
struct LastFMTransportTests {
    @Test func beginningAuthorizationDoesNotReplaceExistingSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CredentialStore(baseDirectory: directory)
        try await store.set("key", for: .lastFMAPIKey)
        try await store.set("secret", for: .lastFMSecret)
        try await store.set("working-session", for: .lastFMSessionKey)
        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"token":"temporary-token"}"#.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let client = LastFMClient(credentials: store, session: URLSession(configuration: configuration))
        _ = try await client.beginAuthorization()
        #expect(await store.value(for: .lastFMSessionKey) == "working-session")
        #expect(await store.value(for: .lastFMAuthToken) == "temporary-token")
    }

    @Test func scrobbleSendsRequiredSignedFields() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CredentialStore(baseDirectory: directory)
        try await store.set("key", for: .lastFMAPIKey)
        try await store.set("secret", for: .lastFMSecret)
        try await store.set("session", for: .lastFMSessionKey)
        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"scrobbles":{"@attr":{"accepted":"1","ignored":"0"}}}"#.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let client = LastFMClient(credentials: store, session: URLSession(configuration: configuration))
        try await client.scrobble(title: "A & B", artist: "Artist", album: "Album", duration: 180, startedAt: Date(timeIntervalSince1970: 1_000))
        let values = LastFMClient.requestValues(
            method: "track.scrobble",
            parameters: ["track": "A & B", "artist": "Artist", "album": "Album", "duration": "180", "timestamp": "1000"],
            apiKey: "key", secret: "secret", sessionKey: "session", signed: true
        )
        let body = String(data: LastFMClient.encodedBody(values), encoding: .utf8) ?? ""
        #expect(body.contains("method=track.scrobble"))
        #expect(body.contains("track=A%20%26%20B"))
        #expect(body.contains("timestamp=1000"))
        #expect(body.contains("sk=session"))
        #expect(body.contains("api_sig="))
    }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task {
            do {
                guard let handler = Self.handler else { throw URLError(.badServerResponse) }
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}

@MainActor
@Suite("Preferences and notifications")
struct PreferencesAndNotificationTests {
    @Test func enabledIntegrationsStartInConnectingState() throws {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "discordEnabled")
        defaults.set(true, forKey: "lastFMEnabled")
        let model = AppModel(
            store: try PersistenceStore(inMemory: true),
            preferences: Preferences(defaults: defaults),
            notifications: NotificationCoordinator(delivery: FakeNotificationDelivery())
        )
        #expect(model.discordStatus == .connecting)
        #expect(model.lastFMStatus == .connecting)
    }

    @Test func preferencesPersistAndRemainObservableState() {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.showAlbum = false
        preferences.discordApplicationID = "public-id"
        preferences.privateUntil = Date(timeIntervalSince1970: 123)
        let reloaded = Preferences(defaults: defaults)
        #expect(!reloaded.showAlbum)
        #expect(reloaded.discordApplicationID == "public-id")
        #expect(reloaded.privateUntil == Date(timeIntervalSince1970: 123))
    }

    @Test func notificationsAreDeduplicatedAndResettable() async {
        let delivery = FakeNotificationDelivery()
        let coordinator = NotificationCoordinator(delivery: delivery)
        await coordinator.notifyOnce(key: "permission", title: "Title", body: "Body", section: .diagnostics)
        await coordinator.notifyOnce(key: "permission", title: "Title", body: "Body", section: .diagnostics)
        #expect(delivery.sections == [.diagnostics])
        coordinator.reset("permission")
        await coordinator.notifyOnce(key: "permission", title: "Title", body: "Body", section: .settings)
        #expect(delivery.sections == [.diagnostics, .settings])
    }

    @Test func timedPrivacyExpiresWithoutAViewRead() async throws {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let now = Date(timeIntervalSince1970: 20_000)
        let clock = ImmediateTestClock(now: now)
        preferences.privateMode = true
        preferences.privateUntil = now.addingTimeInterval(60)
        let store = try PersistenceStore(inMemory: true)
        let model = AppModel(
            store: store,
            preferences: preferences,
            notifications: NotificationCoordinator(delivery: FakeNotificationDelivery()),
            clock: clock
        )
        await model.waitForPendingPrivacyExpiration()
        #expect(!preferences.privateMode)
        #expect(preferences.privateUntil == nil)
        #expect(!model.isPrivate)
    }
}

@MainActor
private final class FakeNotificationDelivery: NotificationDelivering {
    var sections: [DashboardSection] = []
    func requestAuthorization() async -> Bool { true }
    func deliver(identifier: String, title: String, body: String, section: DashboardSection) async { sections.append(section) }
}

@Suite("Security")
struct SecurityTests {
    @Test func credentialsPersistInOwnerOnlyFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CredentialStore(baseDirectory: directory)
        try await store.set("secret-value", for: .lastFMSecret)

        let reloaded = CredentialStore(baseDirectory: directory)
        #expect(await reloaded.value(for: .lastFMSecret) == "secret-value")
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("credentials.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func redactsSecretsAndUserPaths() {
        let output = Redactor.redact("api_key=abc123 /Users/colby/file token xyz Authorization: Bearer bearer-value")
        #expect(!output.contains("abc123")); #expect(!output.contains("colby")); #expect(!output.contains("xyz")); #expect(!output.contains("bearer-value"))
    }

    @MainActor
    @Test func supportReportRedactsLogs() {
        let record = DiagnosticRecord(category: "network", message: "token=abc /Users/person/private")
        let report = DiagnosticReport.make(
            appVersion: "0.4.0", osVersion: "macOS Test", playbackPlatform: "Spotify",
            musicStatus: .connected, discordStatus: .offline, lastFMStatus: .authorizationExpired,
            ytmDesktopStatus: .disabled, records: [record]
        )
        #expect(report.contains("token=<redacted>"))
        #expect(report.contains("/Users/<redacted>"))
        #expect(!report.contains("token=abc"))
        #expect(!report.contains("person"))
    }

    @Test func signatureIsDeterministic() {
        let values = ["method": "auth.getToken", "api_key": "key", "format": "json"]
        #expect(LastFMClient.signature(values, secret: "secret") == LastFMClient.signature(values, secret: "secret"))
        #expect(LastFMClient.signature(values, secret: "secret").count == 32)
    }


    @Test func lastFMAcceptedScrobbleIsValidated() throws {
        try LastFMClient.validateScrobbleResponse(["scrobbles": ["@attr": ["accepted": "1", "ignored": "0"]]])
    }

    @Test func lastFMIgnoredScrobbleIsReported() {
        #expect(throws: LastFMError.self) {
            try LastFMClient.validateScrobbleResponse([
                "scrobbles": [
                    "@attr": ["accepted": "0", "ignored": "1"],
                    "scrobble": ["ignoredMessage": ["#text": "Timestamp too old"]]
                ]
            ])
        }
    }

    @Test func malformedLastFMScrobbleResponseIsRejected() {
        #expect(throws: LastFMError.self) {
            try LastFMClient.validateScrobbleResponse(["unexpected": true])
        }
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

    @Test func healthHistoryDeduplicatesPerIntegrationAndKeepsLastSuccess() throws {
        let store = try PersistenceStore(inMemory: true)
        let first = Date(timeIntervalSince1970: 1_000)
        let second = first.addingTimeInterval(10)
        store.recordHealth(.discord, state: .connected, at: first)
        store.recordHealth(.lastFM, state: .connected, at: second)
        store.recordHealth(.discord, state: .connected, at: second)
        #expect(try store.context.fetchCount(FetchDescriptor<IntegrationHealthEvent>()) == 2)
        #expect(store.lastSuccessfulIntegrationDate(.discord) == first)
        #expect(store.lastSuccessfulIntegrationDate(.lastFM) == second)
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

    @Test func overlappingQueueDrainsSubmitARecordOnlyOnce() async throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(session())
        let submitter = SuspendedSubmitter()
        let queue = ScrobbleQueue(store: store, client: submitter)

        async let first: Void = queue.process()
        await submitter.waitUntilStarted()
        async let second: Void = queue.process()
        await second
        await submitter.resume()
        await first

        #expect(await submitter.submissionCount == 1)
        let record = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
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

private actor SuspendedSubmitter: ScrobbleSubmitting {
    private(set) var submissionCount = 0
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func scrobble(title: String, artist: String, album: String?, duration: Double, startedAt: Date) async throws {
        submissionCount += 1
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { resumeContinuation = $0 }
    }

    func waitUntilStarted() async {
        if submissionCount > 0 { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

@MainActor
@Suite("Listening insights")
struct ListeningInsightsTests {
    @Test func summaryCountsListensMinutesArtistsAndDays() throws {
        let store = try PersistenceStore(inMemory: true)
        let now = Date.now
        store.record(session(title: "One", artist: "Artist A", startedAt: now.addingTimeInterval(-3_600), listened: 120, outcome: .played))
        store.record(session(title: "Two", artist: "Artist A", startedAt: now.addingTimeInterval(-1_800), listened: 180, outcome: .played))
        store.record(session(title: "Skip", artist: "Artist B", startedAt: now, listened: 10, outcome: .skipped))
        let records = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        let summary = ListeningSummary(records: records, now: now)
        #expect(summary.total == 3)
        #expect(summary.played == 2)
        #expect(summary.skipped == 1)
        #expect(summary.listeningMinutes == 5)
        #expect(summary.topArtists.first == ArtistPlayCount(artist: "Artist A", plays: 2))
        #expect(summary.dailyCounts.reduce(0) { $0 + $1.plays } == 2)
    }

    @Test func csvEscapesMetadataAndClearHistoryDoesNotTouchQueue() throws {
        let store = try PersistenceStore(inMemory: true)
        let value = session(title: "A, \"Quoted\" Song", artist: "Artist", startedAt: .now, listened: 60, outcome: .played)
        store.record(value)
        store.enqueue(value)
        let records = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        let csv = HistoryCSVExporter.csv(records: records)
        #expect(csv.contains("\"A, \"\"Quoted\"\" Song\""))
        store.clearActivity()
        #expect(try store.context.fetchCount(FetchDescriptor<ActivityRecord>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 1)
    }

    @Test func discordApplicationIDIsBundled() {
        #expect(ReleaseConfiguration.discordApplicationID == "1525555974390153346")
    }

    @Test func sourceBuildUsesCurrentReleaseVersion() {
        #expect(ReleaseConfiguration.version == "1.0.0")
        #expect(ReleaseConfiguration.build == "1")
    }

    private func session(
        title: String,
        artist: String,
        startedAt: Date,
        listened: TimeInterval,
        outcome: SessionOutcome
    ) -> PlaybackSession {
        let track = TrackMetadata(
            identity: .init(persistentID: UUID().uuidString), title: title, artist: artist,
            album: "Album", duration: 240, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        return PlaybackSession(
            id: UUID(), track: track, startedAt: startedAt, accumulatedPlayTime: listened,
            lastPosition: listened, eligibility: outcome == .played ? .eligible : .listening, outcome: outcome
        )
    }
}

@Suite("Playback coordination")
struct PlaybackCoordinationTests {
    @Test func keepsActivePlayingProviderThenSwitchesDeterministically() async {
        let coordinator = PlaybackCoordinator()
        let now = Date(timeIntervalSince1970: 10_000)
        let spotify = playback(platform: .spotify, state: .playing, at: now)
        let music = playback(platform: .appleMusic, state: .playing, at: now)
        let first = await coordinator.select([
            ProviderSnapshot(provider: .spotify, playback: spotify, health: .available, observedAt: now)
        ], now: now)
        #expect(first.track?.platform == .spotify)

        let retained = await coordinator.select([
            ProviderSnapshot(provider: .appleMusic, playback: music, health: .available, observedAt: now),
            ProviderSnapshot(provider: .spotify, playback: spotify, health: .available, observedAt: now)
        ], now: now)
        #expect(retained.track?.platform == .spotify)

        let pausedSpotify = playback(platform: .spotify, state: .paused, at: now)
        let switched = await coordinator.select([
            ProviderSnapshot(provider: .appleMusic, playback: music, health: .available, observedAt: now),
            ProviderSnapshot(provider: .spotify, playback: pausedSpotify, health: .available, observedAt: now)
        ], now: now)
        #expect(switched.track?.platform == .appleMusic)
    }

    @Test func providerFailureDoesNotHideAnotherValidProvider() async {
        let coordinator = PlaybackCoordinator()
        let now = Date(timeIntervalSince1970: 10_000)
        let spotify = playback(platform: .spotify, state: .playing, at: now)
        let selected = await coordinator.select([
            ProviderSnapshot(provider: .appleMusic, playback: nil, health: .permissionRequired, observedAt: now),
            ProviderSnapshot(provider: .spotify, playback: spotify, health: .available, observedAt: now)
        ], now: now)
        #expect(selected.track?.platform == .spotify)
        #expect(selected.confidence == .high)
    }

    private func playback(platform: PlaybackPlatform, state: PlaybackState, at date: Date) -> PlaybackSnapshot {
        let track = TrackMetadata(
            identity: .init(persistentID: platform.rawValue), title: "Track", artist: "Artist",
            album: "Album", duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil, platform: platform
        )
        return PlaybackSnapshot(track: track, state: state, position: 10, observedAt: date, confidence: .high)
    }
}

@MainActor
@Suite("Backup and extended insights")
struct BackupAndExtendedInsightsTests {
    @Test func backupRoundTripRestoresDataAndExcludesSecrets() throws {
        let source = try PersistenceStore(inMemory: true)
        let sourceDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = Preferences(defaults: sourceDefaults)
        let value = session(title: "Café, \"Night\" 🎵", startedAt: .now, platform: .spotify)
        source.record(value)
        source.enqueue(value)

        let backup = try BackupService.make(store: source, preferences: preferences)
        let data = try BackupService.encode(backup)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.localizedCaseInsensitiveContains("api_key"))
        #expect(!json.localizedCaseInsensitiveContains("session_key"))
        #expect(!json.localizedCaseInsensitiveContains("ytmdesktopToken"))

        let decoded = try BackupService.decode(data)
        let target = try PersistenceStore(inMemory: true)
        let targetPreferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try BackupService.restore(decoded, store: target, preferences: targetPreferences)
        let restored = try #require(target.context.fetch(FetchDescriptor<ActivityRecord>()).first)
        #expect(restored.title == value.track.title)
        #expect(restored.platformRaw == PlaybackPlatform.spotify.rawValue)
        #expect(try target.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 1)
        #expect(!targetPreferences.lastFMEnabled)
    }

    @Test func comparisonsIgnoreSearchAndUsePrecedingEqualPeriod() throws {
        let store = try PersistenceStore(inMemory: true)
        let now = Date.now
        store.record(session(title: "Current", startedAt: now.addingTimeInterval(-86_400), platform: .appleMusic))
        store.record(session(title: "Previous", startedAt: now.addingTimeInterval(-8 * 86_400), platform: .spotify))
        let records = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        let insights = ExtendedListeningInsights(records: records, period: .week, now: now)
        #expect(insights.comparison.current.listens == 1)
        #expect(insights.comparison.previous?.listens == 1)
        #expect(insights.platformCounts == [PlatformListenCount(platform: PlaybackPlatform.appleMusic.rawValue, plays: 1)])
    }

    @Test func csvV1HasFrozenColumnsAndUnicode() throws {
        let store = try PersistenceStore(inMemory: true)
        store.record(session(title: "夜, \"Song\" 🎵", startedAt: .now, platform: .youtubeMusic))
        let csv = HistoryCSVExporter.csv(records: try store.context.fetch(FetchDescriptor<ActivityRecord>()))
        #expect(csv.hasPrefix("schema_version,id,started_at,finalized_at,title,artist,album,platform,outcome,duration_seconds,listening_seconds,persistent_id\n"))
        #expect(csv.contains("\"夜, \"\"Song\"\" 🎵\""))
        #expect(csv.contains("YouTube Music"))
    }

    private func session(title: String, startedAt: Date, platform: PlaybackPlatform) -> PlaybackSession {
        let track = TrackMetadata(
            identity: .init(persistentID: UUID().uuidString), title: title, artist: "Artist",
            album: "Album", duration: 240, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil, platform: platform
        )
        return PlaybackSession(
            id: UUID(), track: track, startedAt: startedAt, accumulatedPlayTime: 180,
            lastPosition: 180, eligibility: .eligible, outcome: .played
        )
    }
}

@Suite("Persistence recovery")
struct PersistenceRecoveryTests {
    @MainActor
    @Test func migratesVersionZeroFixtureAndPreservesOlderOptionalData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("PresenceFM.store")

        try autoreleasepool {
            let schema = Schema(versionedSchema: PresenceFMSchemaV0.self)
            let configuration = ModelConfiguration("PresenceFM-v0", schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            context.insert(PresenceFMSchemaV0.ActivityRecord(
                id: UUID(), title: "Legacy Track", artist: "Legacy Artist", album: nil,
                startedAt: .now, outcomeRaw: SessionOutcome.played.rawValue,
                persistentID: "legacy-id", duration: 180, listenedTime: 100
            ))
            try context.save()
        }

        let migrated = try PersistenceStore(storeURL: url, legacyStoreURL: nil)
        let record = try #require(migrated.context.fetch(FetchDescriptor<ActivityRecord>()).first)
        #expect(record.title == "Legacy Track")
        #expect(record.persistentID == "legacy-id")
        #expect(record.trackDuration == nil)
        #expect(record.finalizedAt == nil)
        #expect(record.platformRaw == nil)
    }

    @Test func importsLegacyStoreBacksUpAndRestoresWithoutDeletingOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("default.store")
        let store = root.appendingPathComponent("PresenceFM/PresenceFM.store")
        try Data("legacy-main".utf8).write(to: legacy)
        try Data("legacy-wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))

        let preparation = try PersistenceRecovery.prepare(storeURL: store, legacyStoreURL: legacy)
        #expect(preparation.importedLegacyStore)
        #expect(preparation.backupURL != nil)
        #expect(try String(contentsOf: store, encoding: .utf8) == "legacy-main")
        #expect(try String(contentsOf: legacy, encoding: .utf8) == "legacy-main")

        try PersistenceRecovery.markMigrationSuccessful(storeURL: store)
        let second = try PersistenceRecovery.prepare(storeURL: store, legacyStoreURL: legacy)
        #expect(!second.importedLegacyStore)
        #expect(second.backupURL == nil)

        try Data("damaged".utf8).write(to: store)
        try PersistenceRecovery.restoreLatestBackup(storeURL: store)
        #expect(try String(contentsOf: store, encoding: .utf8) == "legacy-main")
        let failedRoot = store.deletingLastPathComponent().appendingPathComponent("FailedStores")
        #expect(try FileManager.default.contentsOfDirectory(atPath: failedRoot.path).count == 1)
    }

    @Test func freshStorePreservesFailedDataAndNeverReimportsLegacy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("default.store")
        let store = root.appendingPathComponent("PresenceFM/PresenceFM.store")
        try Data("legacy".utf8).write(to: legacy)
        _ = try PersistenceRecovery.prepare(storeURL: store, legacyStoreURL: legacy)

        try PersistenceRecovery.prepareFreshStore(storeURL: store)
        #expect(!FileManager.default.fileExists(atPath: store.path))
        let next = try PersistenceRecovery.prepare(storeURL: store, legacyStoreURL: legacy)
        #expect(!next.importedLegacyStore)
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test func onlyTwoPhysicalMigrationBackupsAreRetained() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("PresenceFM.store")
        try Data("store".utf8).write(to: store)
        for version in 1...4 {
            _ = try PersistenceRecovery.prepare(storeURL: store, legacyStoreURL: nil, schemaVersion: version)
        }
        let backups = root.appendingPathComponent("StoreBackups")
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).count == 2)
    }
}

@MainActor
@Suite("Injected clock scheduling")
struct InjectedClockSchedulingTests {
    @Test func queueUsesInjectedTimeForAdmissionRetryAndBackoff() async throws {
        let now = Date(timeIntervalSince1970: 50_000)
        let clock = ImmediateTestClock(now: now)
        let store = try PersistenceStore(inMemory: true)
        let queue = ScrobbleQueue(
            store: store,
            client: FailingSubmitter(error: .transport("Offline")),
            clock: clock
        )
        let track = TrackMetadata(
            identity: .init(persistentID: "clock"), title: "Clock", artist: "Artist",
            album: nil, duration: 120, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let playback = PlaybackSession(
            id: UUID(), track: track, startedAt: now, accumulatedPlayTime: 60,
            lastPosition: 60, eligibility: .eligible, outcome: .queued
        )
        queue.enqueue(playback)
        await queue.process()

        let record = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
        #expect(record.attempts == 1)
        #expect(record.nextAttemptAt == now.addingTimeInterval(10))

        clock.advance(by: 100)
        record.state = .permanentlyFailed
        store.save()
        queue.retry(id: record.id)
        #expect(record.nextAttemptAt == now.addingTimeInterval(100))
    }
}

@Suite("Demo playback")
struct DemoPlaybackTests {
    private let start = Date(timeIntervalSince1970: 100_000)

    @Test func beginsWithAPlayingScrobbleableTrack() throws {
        let snapshot = DemoPlaybackSequence.snapshot(at: start, startedAt: start)
        let track = try #require(snapshot.track)

        #expect(snapshot.state == .playing)
        #expect(snapshot.position == 0)
        #expect(track.title == "Midnight Signal")
        #expect(track.duration == DemoPlaybackSequence.trackDuration)
        #expect(track.isScrobbleable)
    }

    @Test func insertsASafeGapAndAdvancesTracks() throws {
        let gap = DemoPlaybackSequence.snapshot(
            at: start.addingTimeInterval(DemoPlaybackSequence.trackDuration + 1),
            startedAt: start
        )
        #expect(gap.state == .stopped)
        #expect(gap.track == nil)

        let next = DemoPlaybackSequence.snapshot(
            at: start.addingTimeInterval(DemoPlaybackSequence.cycleDuration),
            startedAt: start
        )
        #expect(try #require(next.track).title == "Electric Morning")
        #expect(next.position == 0)
    }

    @Test func negativeElapsedTimeClampsToTheFirstTrack() throws {
        let snapshot = DemoPlaybackSequence.snapshot(
            at: start.addingTimeInterval(-5), startedAt: start
        )
        #expect(try #require(snapshot.track).title == "Midnight Signal")
        #expect(snapshot.position == 0)
    }

    @Test func sequenceExercisesEligibilityAndFinalization() async {
        let tracker = PlaybackSessionTracker()
        _ = await tracker.ingest(DemoPlaybackSequence.snapshot(at: start, startedAt: start))
        let threshold = await tracker.ingest(DemoPlaybackSequence.snapshot(
            at: start.addingTimeInterval(16), startedAt: start
        ))
        #expect(threshold.contains { if case .eligible = $0 { true } else { false } })

        let stopped = await tracker.ingest(DemoPlaybackSequence.snapshot(
            at: start.addingTimeInterval(DemoPlaybackSequence.trackDuration + 1),
            startedAt: start
        ))
        let outcome = stopped.compactMap { event -> SessionOutcome? in
            guard case .finalized(let session) = event else { return nil }
            return session.outcome
        }.first
        #expect(outcome == .played)
    }

    @MainActor
    @Test func launchModeSkipsOnboardingWithoutPersistingCompletion() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = Preferences(defaults: defaults)
        let model = AppModel(
            store: try PersistenceStore(inMemory: true),
            preferences: preferences,
            notifications: NotificationCoordinator(delivery: FakeNotificationDelivery()),
            launchInDemoMode: true
        )

        #expect(model.demoModeEnabled)
        #expect(!model.onboardingPresented)
        #expect(!preferences.onboardingComplete)
        #expect(!model.allowsExternalPublishing)

        preferences.privateMode = false
        #expect(!model.allowsExternalPublishing)

        model.setDemoModeEnabled(false)
        #expect(model.allowsExternalPublishing)

        preferences.privateMode = true
        #expect(!model.allowsExternalPublishing)
    }
}

private final class ImmediateTestClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) { value = now }

    var now: Date { lock.withLock { value } }
    func sleep(until deadline: Date) async throws { lock.withLock { value = max(value, deadline) } }
    func advance(by interval: TimeInterval) { lock.withLock { value = value.addingTimeInterval(interval) } }
}
