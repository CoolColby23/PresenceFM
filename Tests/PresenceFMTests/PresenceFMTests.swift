import Foundation
import AppKit
import SwiftData
import SwiftUI
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
        #expect(await tracker.active?.accumulatedPlayTime == 10)
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

    @Test func startingMidTrackUsesObservedPlaybackPosition() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(
            track: track, state: .playing, position: 60,
            observedAt: start, confidence: .high
        ))

        #expect(await tracker.active?.accumulatedPlayTime == 60)
        #expect(await tracker.active?.eligibility == .eligible)
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

    @Test func transientStoppedSnapshotDoesNotCreateFalseSkip() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 10, observedAt: start, confidence: .high))
        let stopped = await tracker.ingest(.init(track: nil, state: .stopped, position: 0, observedAt: start.addingTimeInterval(1), confidence: .high))
        let resumed = await tracker.ingest(.init(track: track, state: .playing, position: 12, observedAt: start.addingTimeInterval(2), confidence: .high))

        #expect(!stopped.contains { if case .finalized = $0 { true } else { false } })
        #expect(!resumed.contains { if case .started = $0 { true } else { false } })
        #expect(await tracker.active != nil)
    }

    @Test func earlyStopIsInterruptedRatherThanSkippedAfterGracePeriod() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 5, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: nil, state: .stopped, position: 0, observedAt: start.addingTimeInterval(1), confidence: .high))
        let events = await tracker.ingest(.init(track: nil, state: .stopped, position: 0, observedAt: start.addingTimeInterval(3), confidence: .high))
        let outcome = events.compactMap { event -> SessionOutcome? in
            guard case .finalized(let session) = event else { return nil }
            return session.outcome
        }.first

        #expect(outcome == .interrupted)
    }

    @Test func playingTrackReplacementBeforeThresholdIsSkipped() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        let next = TrackMetadata(identity: .init(persistentID: "next"), title: "Next", artist: "Artist", album: nil, duration: 100, source: .appleMusicCatalog, appleMusicURL: nil, artworkReference: nil)
        _ = await tracker.ingest(.init(track: track, state: .playing, position: 5, observedAt: start, confidence: .high))
        let events = await tracker.ingest(.init(track: next, state: .playing, position: 0, observedAt: start.addingTimeInterval(1), confidence: .high))
        let outcome = events.compactMap { event -> SessionOutcome? in
            guard case .finalized(let session) = event else { return nil }
            return session.outcome
        }.first

        #expect(outcome == .skipped)
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

    @Test func unsupportedLiveStreamIsNeverEligible() async {
        let stream = TrackMetadata(identity: .init(persistentID: "live"), title: "Station", artist: "Host", album: nil, duration: 3_600, source: .radioStream, appleMusicURL: nil, artworkReference: nil, platform: .youtubeMusic)
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = await tracker.ingest(.init(track: stream, state: .playing, position: 0, observedAt: start, confidence: .high))
        _ = await tracker.ingest(.init(track: stream, state: .playing, position: 300, observedAt: start.addingTimeInterval(300), confidence: .high))
        #expect(await tracker.active?.eligibility == .ineligible)
    }

    @Test func appleMusicRadioQualifiesAfterObservedListeningAndFinalizesPlayed() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        let radio = TrackMetadata(identity: .init(persistentID: "radio:one"), title: "One", artist: "DJ", album: "Station", duration: 0, source: .radioStream, appleMusicURL: nil, artworkReference: nil)
        let next = TrackMetadata(identity: .init(persistentID: "radio:two"), title: "Two", artist: "DJ", album: "Station", duration: 0, source: .radioStream, appleMusicURL: nil, artworkReference: nil)
        _ = await tracker.ingest(.init(track: radio, state: .playing, position: 0, observedAt: start, confidence: .high))
        for second in 1...30 {
            _ = await tracker.ingest(.init(track: radio, state: .playing, position: 0, observedAt: start.addingTimeInterval(Double(second)), confidence: .high))
        }
        #expect(await tracker.active?.eligibility == .eligible)

        let events = await tracker.ingest(.init(track: next, state: .playing, position: 0, observedAt: start.addingTimeInterval(31), confidence: .high))
        let finalized = events.compactMap { event -> PlaybackSession? in
            guard case .finalized(let session) = event else { return nil }
            return session
        }.first
        #expect(finalized?.outcome == .played)
    }

    @Test func radioTransitionIsListenedRatherThanSkipped() async {
        let tracker = PlaybackSessionTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        let first = TrackMetadata(identity: .init(persistentID: "radio:one"), title: "One", artist: "DJ", album: "Station", duration: 0, source: .radioStream, appleMusicURL: nil, artworkReference: nil)
        let second = TrackMetadata(identity: .init(persistentID: "radio:two"), title: "Two", artist: "DJ", album: "Station", duration: 0, source: .radioStream, appleMusicURL: nil, artworkReference: nil)
        _ = await tracker.ingest(.init(track: first, state: .playing, position: 0, observedAt: start, confidence: .high))
        let events = await tracker.ingest(.init(track: second, state: .playing, position: 0, observedAt: start.addingTimeInterval(30), confidence: .high))
        let outcome = events.compactMap { event -> SessionOutcome? in
            guard case .finalized(let session) = event else { return nil }
            return session.outcome
        }.first

        #expect(outcome == .listened)
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
        let stream = TrackMetadata(identity: .init(persistentID: "live"), title: "Station", artist: "Host", album: nil, duration: 3_600, source: .radioStream, appleMusicURL: nil, artworkReference: nil, platform: .youtubeMusic)
        let session = PlaybackSession(id: UUID(), track: stream, startedAt: .now, accumulatedPlayTime: 0, lastPosition: 0, eligibility: .ineligible, outcome: .active)
        #expect(session.scrobblePresentation == .ineligible("This live stream does not provide reliable scrobble metadata."))
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
        let result = await service.artworkResult(for: track)
        #expect(result?.data == imageData)
        #expect(result?.source == .localFile)
        #expect(await service.artworkResult(for: track)?.source == .memoryCache)
        #expect(await service.cachedArtwork(for: track.identity) == imageData)
        await service.invalidateArtwork(for: track.identity)
        #expect(await service.artworkResult(for: track)?.source == .localFile)
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

    @Test func exactRemoteArtworkIsPreferredForDiscord() async throws {
        let artworkURL = try #require(URL(string: "https://i.scdn.co/image/exact-cover"))
        let track = TrackMetadata(
            identity: .init(persistentID: "remote-artwork"), title: "Track", artist: "Artist",
            album: "Album", duration: 180, source: .unsupportedStream,
            appleMusicURL: nil, artworkReference: .remote(artworkURL), platform: .spotify
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ArtworkService(directory: directory)

        #expect(await service.publicArtworkURL(for: track) == artworkURL)
        #expect(ArtworkService.directPublicArtworkURL(for: track) == artworkURL)
    }

    @Test func insecureRemoteArtworkIsUpgradedToHTTPSForDiscord() throws {
        let artworkURL = try #require(URL(string: "http://example.com/cover.jpg"))
        let track = TrackMetadata(
            identity: .init(persistentID: "insecure-artwork"), title: "Track", artist: "Artist",
            album: "Album", duration: 180, source: .unsupportedStream,
            appleMusicURL: nil, artworkReference: .remote(artworkURL), platform: .spotify
        )
        #expect(ArtworkService.directPublicArtworkURL(for: track)?.absoluteString == "https://example.com/cover.jpg")
    }

    @Test func catalogArtworkRejectsAReleaseWithTheWrongAlbum() {
        let track = TrackMetadata(
            identity: .init(persistentID: "album-match"), title: "Track", artist: "Artist",
            album: "Original Album", duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let wrongRelease = CatalogTrack(
            trackName: "Track", artistName: "Artist", collectionName: "Different Album",
            artworkUrl100: "https://example.com/100x100bb.jpg"
        )
        let misleadingSubstring = CatalogTrack(
            trackName: "Track", artistName: "Artist", collectionName: "Different Original Album",
            artworkUrl100: "https://example.com/100x100bb.jpg"
        )
        let deluxeRelease = CatalogTrack(
            trackName: "Track", artistName: "Artist", collectionName: "Original Album (Deluxe Edition)",
            artworkUrl100: "https://example.com/100x100bb.jpg"
        )

        #expect(!ArtworkCatalogMatcher.isReliable(wrongRelease, track: track))
        #expect(!ArtworkCatalogMatcher.isReliable(misleadingSubstring, track: track))
        #expect(ArtworkCatalogMatcher.isReliable(deluxeRelease, track: track))
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
    @Test func staleSocketFileDoesNotMakeDiscordAppearAvailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("stale".utf8).write(to: directory.appendingPathComponent("discord-ipc-0"))
        let client = DiscordPresenceClient(applicationID: "test", runtimeRoots: [directory.path])

        #expect(!(await client.probeAvailability()))
    }

    @Test func externalArtworkURLIsSentAsLargeImage() throws {
        let artworkURL = try #require(URL(string: "https://example.com/album.jpg"))
        let presence = DiscordPresence(
            title: "Track", state: "Artist • Album", startedAt: nil,
            appleMusicURL: nil, artworkURL: artworkURL, buttonLabel: "Listen"
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        let largeImage = try #require(assets["large_image"])
        #expect(largeImage.contains("wsrv.nl"))
        #expect(largeImage.contains("example.com/album.jpg"))
        #expect(assets["large_text"] == nil)
        #expect(assets["small_image"] == ReleaseConfiguration.discordApplicationIconURL)
    }

    @Test func platformLogoCanBeUsedAsSmallImage() throws {
        let presence = DiscordPresence(
            title: "Track", state: "Artist", startedAt: nil, appleMusicURL: nil,
            artworkURL: nil, buttonLabel: "Listen", platform: .spotify,
            smallImage: .playbackPlatform
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["small_image"] == PlaybackPlatform.spotify.discordSmallImageURL)
        #expect(assets["small_text"] == "Playing on Spotify")
    }

    @Test func everyPlatformSmallImageUsesAWebImageInsteadOfAnUploadedAssetKey() throws {
        for platform in PlaybackPlatform.allCases {
            let presence = DiscordPresence(
                title: "Track", state: "Artist", startedAt: nil, appleMusicURL: nil,
                artworkURL: nil, buttonLabel: "", platform: platform,
                smallImage: .playbackPlatform
            )
            let payload = DiscordPresenceClient.activityPayload(for: presence)
            let assets = try #require(payload["assets"] as? [String: String])
            let smallImage = try #require(assets["small_image"])
            #expect(URL(string: smallImage)?.scheme == "https")
            #expect(smallImage.contains("coolcolby23.github.io/PresenceFM/assets/external-logos/"))
            #expect(smallImage.hasSuffix(".png"))
        }
    }

    @Test func appleMusicPlatformBadgeUsesUpdatedHostedLogo() {
        #expect(PlaybackPlatform.appleMusic.discordSmallImageURL.hasSuffix("/apple-music.png"))
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
        #expect(assets["small_image"] == PlaybackPlatform.spotify.discordSmallImageURL)
        #expect(assets["large_image"]?.contains("wsrv.nl") == true)
    }

    @Test func httpArtworkIsUpgradedAndProxiedForDiscord() throws {
        let artworkURL = try #require(URL(string: "http://is1.mzstatic.com/image/thumb/cover/100x100bb.jpg"))
        let presence = DiscordPresence(
            title: "Track", state: "Artist", startedAt: nil,
            appleMusicURL: nil, artworkURL: artworkURL, buttonLabel: "Listen"
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        let largeImage = try #require(assets["large_image"])
        #expect(largeImage.contains("wsrv.nl"))
        #expect(largeImage.contains("https://is1.mzstatic.com"))
        #expect(!largeImage.contains("http://is1.mzstatic.com"))
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

    @Test func publicApplicationIconIsUsedUntilArtworkArrives() throws {
        let presence = DiscordPresence(
            title: "Track", state: "Artist", startedAt: nil,
            appleMusicURL: nil, artworkURL: nil, buttonLabel: "Listen"
        )
        let payload = DiscordPresenceClient.activityPayload(for: presence)
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["large_image"] == ReleaseConfiguration.discordApplicationIconURL)
    }
}

@Suite("Additional playback platforms")
struct AdditionalPlaybackPlatformTests {
    private let separator = String(UnicodeScalar(30)!)

    @Test func playbackControlsAreOnlyShownForScriptablePlayers() {
        #expect(SystemPlaybackController.supports(.appleMusic))
        #expect(SystemPlaybackController.supports(.spotify))
        #expect(!SystemPlaybackController.supports(.youtubeMusic))
        #expect(!SystemPlaybackController.supports(.tidal))
        #expect(!SystemPlaybackController.supports(nil))
    }

    @Test func parsesSpotifyPlayingAndPausedStates() throws {
        let playing = ["playing", "Track", "Artist", "Album", "180000", "42.5", "spotify:track:abc", "spotify:track:abc", "https://i.scdn.co/image/cover"].joined(separator: separator)
        let paused = ["paused", "Track", "Artist", "Album", "180000", "43", "spotify:track:abc", "spotify:track:abc"].joined(separator: separator)
        let playingSnapshot = try #require(PlaybackMonitor.parseSpotify(playing))
        let pausedSnapshot = try #require(PlaybackMonitor.parseSpotify(paused))
        #expect(playingSnapshot.state == .playing)
        #expect(pausedSnapshot.state == .paused)
        #expect(playingSnapshot.track?.duration == 180)
        if case .remote(let url)? = playingSnapshot.track?.artworkReference {
            #expect(url.absoluteString == "https://i.scdn.co/image/cover")
        } else {
            Issue.record("Spotify artwork URL was not retained")
        }
        #expect(playingSnapshot.track?.platform == .spotify)
    }

    @Test func parsesAppleMusicRadioWithPartialStreamMetadata() throws {
        let value = [
            "playing", "Live Session", "", "Apple Music 1", "", "12", "",
            "URL track", "https://music.apple.com/us/station/apple-music-1/ra.978194965?token=private"
        ].joined(separator: separator)
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = PlaybackMonitor.parseMusic(value, observedAt: observedAt)
        let track = try #require(snapshot.track)

        #expect(snapshot.confidence == .high)
        #expect(snapshot.observedAt == observedAt)
        #expect(track.source == .radioStream)
        #expect(track.artist == "Apple Music 1")
        #expect(track.isScrobbleable)
        #expect(track.supportsFiniteProgress == false)
        #expect(track.appleMusicURL?.host == "music.apple.com")
        #expect(track.appleMusicURL?.query == nil)
        #expect(!track.identity.persistentID.contains("private"))
        #expect(track.identity.persistentID.contains("Live Session"))
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
        let data = Data(#"{"player":{"trackState":1,"videoProgress":42.5},"video":{"author":"Artist","title":"Track","album":"Album","durationSeconds":180,"id":"abc123","isLive":false,"thumbnails":[{"url":"https://example.com/small.jpg"},{"url":"https://example.com/large.jpg"}]}}"#.utf8)
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let parsed = try YTMDesktopClient.parseSnapshot(data, observedAt: observedAt)
        let snapshot = try #require(parsed)
        #expect(snapshot.state == .playing)
        #expect(snapshot.position == 42.5)
        #expect(snapshot.observedAt == observedAt)
        #expect(snapshot.track?.platform == .youtubeMusic)
        #expect(snapshot.track?.appleMusicURL?.absoluteString == "https://music.youtube.com/watch?v=abc123")
        if case .remote(let url)? = snapshot.track?.artworkReference {
            #expect(url.absoluteString == "https://example.com/large.jpg")
        } else {
            Issue.record("YouTube Music thumbnail was not retained")
        }
    }

    @Test func liveYTMDesktopVideoIsNotScrobbleable() throws {
        let data = Data(#"{"player":{"trackState":1,"videoProgress":4},"video":{"author":"Station","title":"Live","durationSeconds":3600,"id":"live","isLive":true}}"#.utf8)
        let parsed = try YTMDesktopClient.parseSnapshot(data)
        let snapshot = try #require(parsed)
        #expect(snapshot.track?.source == .radioStream)
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

    @Test func radioScrobbleOmitsUnknownDurationAndMarksTrackAsNotChosen() {
        let parameters = LastFMClient.scrobbleParameters(
            title: "Radio Track", artist: "Radio Artist", album: "Station",
            duration: 0, startedAt: Date(timeIntervalSince1970: 1_000)
        )
        #expect(parameters["duration"] == nil)
        #expect(parameters["chosenByUser"] == "0")
        #expect(parameters["timestamp"] == "1000")
    }

    @Test func recentTracksParserReadsScrobblesAndNowPlaying() throws {
        let payload: [String: Any] = [
            "recenttracks": [
                "track": [
                    [
                        "name": "Now Song",
                        "artist": ["#text": "Live Artist"],
                        "album": ["#text": "Live Album"],
                        "url": "https://www.last.fm/music/Live+Artist/_/Now+Song",
                        "image": [
                            ["size": "small", "#text": "https://example.com/small.jpg"],
                            ["size": "extralarge", "#text": "https://example.com/large.jpg"],
                        ],
                        "@attr": ["nowplaying": "true"],
                    ],
                    [
                        "name": "Past Song",
                        "artist": ["#text": "Studio Artist"],
                        "album": ["#text": "Studio Album"],
                        "date": ["uts": "1700000000", "#text": "14 Nov 2023, 22:13"],
                        "image": [
                            ["size": "large", "#text": "https://example.com/past.jpg"],
                        ],
                    ],
                ] as [[String: Any]],
            ] as [String: Any],
        ]
        let tracks = try LastFMClient.parseRecentTracks(payload)
        #expect(tracks.count == 2)
        #expect(tracks[0].title == "Now Song")
        #expect(tracks[0].isNowPlaying)
        #expect(tracks[0].listenedAt == nil)
        #expect(tracks[0].imageURL?.absoluteString == "https://example.com/large.jpg")
        #expect(tracks[1].title == "Past Song")
        #expect(tracks[1].artist == "Studio Artist")
        #expect(tracks[1].listenedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!tracks[1].isNowPlaying)
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
    @Test func enabledIntegrationsStartInHonestIdleStates() throws {
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
        #expect(model.discordStatus == .inactive)
        #expect(model.lastFMStatus == .connecting)
    }

    @Test func preferencesPersistAndRemainObservableState() {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.showAlbum = false
        preferences.discordActivityName = "My music"
        preferences.discordApplicationID = "public-id"
        preferences.privateUntil = Date(timeIntervalSince1970: 123)
        preferences.playbackProviderOrder = [.spotify, .appleMusic, .tidal, .youtubeMusic]
        preferences.appearanceMode = .dark
        preferences.lightThemeID = "rose"
        preferences.darkThemeID = "grove"
        preferences.menuBarExpanded = false
        preferences.toggleDashboardSection(.queue)
        preferences.toggleDashboardSection(.nowPlaying)
        let reloaded = Preferences(defaults: defaults)
        #expect(!reloaded.showAlbum)
        #expect(reloaded.discordActivityName == "My music")
        #expect(reloaded.discordApplicationID == "public-id")
        #expect(reloaded.privateUntil == Date(timeIntervalSince1970: 123))
        #expect(reloaded.playbackProviderOrder == [.spotify, .appleMusic, .tidal, .youtubeMusic])
        #expect(reloaded.appearanceMode == .dark)
        #expect(reloaded.lightThemeID == "rose")
        #expect(reloaded.darkThemeID == "grove")
        #expect(!reloaded.menuBarExpanded)
        #expect(!reloaded.isDashboardSectionVisible(.queue))
        #expect(reloaded.isDashboardSectionVisible(.nowPlaying))
        #expect(reloaded.theme(for: .dark).id == "grove")
    }

    @Test func themeLibraryIsCuratedAndRejectsUnknownIDs() {
        #expect(AppTheme.presets.count >= 16)
        #expect(Set(AppTheme.presets.map(\.id)).count == AppTheme.presets.count)
        #expect(AppTheme.validatedID("not-installed") == AppTheme.defaultID)
        #expect(AppTheme.presets.allSatisfy { Color(hex: $0.primaryHex) != nil && Color(hex: $0.secondaryHex) != nil })
    }

    @Test func everyThemeProvidesReadableSemanticAccentColors() {
        for theme in AppTheme.presets {
            #expect(theme.readablePrimary(for: .light).contrastRatio(with: theme.lightBackground) >= 4.5)
            #expect(theme.readablePrimary(for: .dark).contrastRatio(with: theme.darkBackground) >= 4.5)
            #expect(theme.onPrimaryColor.contrastRatio(with: theme.primaryColor) >= 4.5)
        }
    }

    @Test func discordProfilesCaptureApplyAndPersist() throws {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.discordActivityName = "My {artist} profile"
        preferences.discordTimerStyle = .hidden
        let profile = DiscordPresenceProfile.capture(name: "Focus", preferences: preferences)
        preferences.discordPresenceProfiles = [profile]
        preferences.discordActivityName = "Changed"
        preferences.discordTimerStyle = .remaining

        profile.apply(to: preferences)
        #expect(preferences.discordActivityName == "My {artist} profile")
        #expect(preferences.discordTimerStyle == .hidden)
        #expect(Preferences(defaults: defaults).discordPresenceProfiles == [profile])
    }

    @Test func scrobbleExclusionsMatchNormalizedMetadataAndPlatform() {
        let rules = ScrobbleExclusionRules(
            artistsText: "Beyoncé\nAnother Artist",
            albumsText: "Private Album",
            titleTermsText: "demo, voice memo",
            platforms: [.youtubeMusic]
        )
        let track = TrackMetadata(
            identity: .init(persistentID: "excluded"), title: "Late Night Demo", artist: "Different Artist",
            album: "Public Album", duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil, platform: .spotify
        )
        #expect(rules.reason(for: track) == "This track matches an excluded title term.")
        let platformTrack = TrackMetadata(
            identity: .init(persistentID: "platform"), title: "Song", artist: "Artist",
            album: nil, duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil, platform: .youtubeMusic
        )
        #expect(rules.reason(for: platformTrack) == "Scrobbling is disabled for YouTube Music.")
    }

    @Test func providerOrderRepairsDuplicatesAndMissingPlayers() {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["spotify", "spotify", "tidal"], forKey: "playbackProviderOrder")

        let preferences = Preferences(defaults: defaults)

        #expect(preferences.playbackProviderOrder == [.spotify, .tidal, .appleMusic, .youtubeMusic])
    }

    @Test func privateModeIntentActionsPreserveNoStaleExpiration() {
        let name = "PresenceFMTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.privateUntil = Date(timeIntervalSince1970: 123)

        PrivateModeIntentAction.start.apply(to: preferences)
        #expect(preferences.privateMode)
        #expect(preferences.privateUntil == nil)

        PrivateModeIntentAction.end.apply(to: preferences)
        #expect(!preferences.privateMode)
        #expect(preferences.privateUntil == nil)
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
    @Test func encryptedBackupRoundTripsAndRejectsWrongPassphrase() throws {
        let original = Data("private backup contents".utf8)
        let encrypted = try SecureBackupService.encrypt(
            original,
            passphrase: "correct horse battery staple"
        )
        #expect(encrypted != original)
        #expect(try SecureBackupService.decrypt(
            encrypted,
            passphrase: "correct horse battery staple"
        ) == original)
        #expect(throws: SecureBackupError.self) {
            try SecureBackupService.decrypt(encrypted, passphrase: "incorrect passphrase")
        }
    }

    @MainActor
    @Test func verificationReportContainsOperationalCountsWithoutListeningMetadata() async throws {
        let store = try PersistenceStore(inMemory: true)
        let model = AppModel(
            store: store,
            notifications: NotificationCoordinator(delivery: FakeNotificationDelivery())
        )
        let track = TrackMetadata(
            identity: .init(persistentID: "secret-track-id"),
            title: "Private Song",
            artist: "Private Artist",
            album: "Private Album",
            duration: 240,
            source: .appleMusicCatalog,
            appleMusicURL: nil,
            artworkReference: nil
        )
        store.enqueue(PlaybackSession(
            id: UUID(),
            track: track,
            startedAt: Date(timeIntervalSince1970: 1_000),
            accumulatedPlayTime: 120,
            lastPosition: 120,
            eligibility: .eligible,
            outcome: .queued
        ))

        let data = try await model.makeVerificationReport(now: Date(timeIntervalSince1970: 2_000)).encoded()
        let value = try #require(String(data: data, encoding: .utf8))

        #expect(value.contains("queuedScrobbles"))
        #expect(value.contains("providerPriority"))
        #expect(!value.contains("Private Song"))
        #expect(!value.contains("Private Artist"))
        #expect(!value.contains("secret-track-id"))
    }

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

    @Test func clearingDemoActivityPreservesRealHistory() throws {
        let store = try PersistenceStore(inMemory: true)
        let demoTrack = TrackMetadata(
            identity: .init(persistentID: "\(DemoPlaybackSequence.persistentIDPrefix)42"),
            title: "Demo Track", artist: "Demo Artist", album: nil, duration: 32,
            source: .localFile, appleMusicURL: nil, artworkReference: nil
        )
        let demoSession = PlaybackSession(
            id: UUID(), track: demoTrack, startedAt: .now, accumulatedPlayTime: 32,
            lastPosition: 32, eligibility: .eligible, outcome: .played
        )
        let persisted = session()
        let realSession = PlaybackSession(
            id: persisted.id, track: persisted.track, startedAt: .now,
            accumulatedPlayTime: persisted.accumulatedPlayTime,
            lastPosition: persisted.lastPosition, eligibility: persisted.eligibility,
            outcome: persisted.outcome
        )
        store.record(demoSession)
        store.record(realSession)

        #expect(store.clearDemoActivity() == 1)
        let remaining = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.persistentID == "persisted")
    }

    @Test func appleMusicRadioQueuePreservesUnknownDurationSignal() throws {
        let store = try PersistenceStore(inMemory: true)
        let track = TrackMetadata(
            identity: .init(persistentID: "radio:queued"), title: "Radio Track",
            artist: "Radio Artist", album: "Station", duration: 0,
            source: .radioStream, appleMusicURL: nil, artworkReference: nil
        )
        let value = PlaybackSession(
            id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 30,
            lastPosition: 0, eligibility: .eligible, outcome: .played
        )
        store.enqueue(value)
        let record = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
        #expect(record.duration == 0)
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

    @Test func healthHistoryTrimsOnlyOverflowRecords() throws {
        let store = try PersistenceStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 10_000)
        let overflow = 5

        for index in 0..<(IntegrationPolicy.healthEventLimit + overflow) {
            store.recordHealth(
                .discord,
                state: index.isMultiple(of: 2) ? .connected : .offline,
                at: start.addingTimeInterval(TimeInterval(index))
            )
        }

        let descriptor = FetchDescriptor<IntegrationHealthEvent>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let records = try store.context.fetch(descriptor)
        #expect(records.count == IntegrationPolicy.healthEventLimit)
        #expect(records.first?.timestamp == start.addingTimeInterval(TimeInterval(overflow)))
        #expect(
            records.last?.timestamp
                == start.addingTimeInterval(TimeInterval(IntegrationPolicy.healthEventLimit + overflow - 1))
        )
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

    @Test func correctionRequiresValidMetadataAndResetsARejectedScrobble() throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(session())
        let record = try #require(store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first)
        record.state = .permanentlyFailed
        record.attempts = 4
        record.lastError = "Rejected metadata"
        store.save()

        #expect(!store.correctScrobble(id: record.id, title: " ", artist: "Artist", album: nil))
        #expect(store.correctScrobble(
            id: record.id,
            title: " Corrected Title ",
            artist: " Corrected Artist ",
            album: " "
        ))
        #expect(record.title == "Corrected Title")
        #expect(record.artist == "Corrected Artist")
        #expect(record.album == nil)
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

    @Test func pendingQueueRejectsNewWorkAtHardLimit() throws {
        let limit = 5
        let store = try PersistenceStore(
            inMemory: true,
            queueLimits: .init(pendingWarning: 4, pendingLimit: limit, permanentWarning: 4, permanentLimit: 5)
        )
        for index in 0..<limit {
            let track = TrackMetadata(
                identity: .init(persistentID: "pending-\(index)"), title: "T\(index)",
                artist: "A", album: nil, duration: 100, source: .appleMusicCatalog,
                appleMusicURL: nil, artworkReference: nil
            )
            let value = PlaybackSession(
                id: UUID(), track: track, startedAt: Date(timeIntervalSince1970: Double(index)),
                accumulatedPlayTime: 50, lastPosition: 50, eligibility: .eligible, outcome: .queued
            )
            switch store.enqueue(value) {
            case .accepted, .warning, .duplicate:
                break
            case .rejected:
                Issue.record("expected pending queue admission before hard limit")
                return
            }
        }
        guard case .rejected(let message) = store.enqueue(session(id: UUID())) else {
            Issue.record("expected pending queue rejection at hard limit")
            return
        }
        #expect(message.contains("queue is full"))
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == limit)
    }

    @Test func permanentQueueRejectsNewWorkAtHardLimit() throws {
        let limit = 5
        let store = try PersistenceStore(
            inMemory: true,
            queueLimits: .init(pendingWarning: 4, pendingLimit: 5, permanentWarning: 4, permanentLimit: limit)
        )
        for index in 0..<limit {
            let track = TrackMetadata(
                identity: .init(persistentID: "failed-\(index)"), title: "F\(index)",
                artist: "A", album: nil, duration: 100, source: .appleMusicCatalog,
                appleMusicURL: nil, artworkReference: nil
            )
            let value = PlaybackSession(
                id: UUID(), track: track, startedAt: Date(timeIntervalSince1970: Double(index)),
                accumulatedPlayTime: 50, lastPosition: 50, eligibility: .eligible, outcome: .queued
            )
            let admission = store.enqueue(value)
            #expect(admission == .accepted || admission == .warning("The failed scrobble queue is approaching its 500-item limit."))
            let title = "F\(index)"
            let record = try #require(
                store.context.fetch(FetchDescriptor<ScrobbleRecord>()).first(where: { $0.title == title })
            )
            record.state = .permanentlyFailed
        }
        store.save()
        guard case .rejected(let message) = store.enqueue(session(id: UUID())) else {
            Issue.record("expected permanent queue rejection at hard limit")
            return
        }
        #expect(message.contains("need attention"))
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == limit)
    }

    @Test func submittedScrobblesAreRemovedOnTheNextDrain() async throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(session())
        let queue = ScrobbleQueue(store: store, client: SuccessfulSubmitter())
        await queue.process()
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 1)
        await queue.process()
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 0)
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
        store.record(session(title: "Radio", artist: "Station", startedAt: now.addingTimeInterval(-900), listened: 60, outcome: .listened))
        store.record(session(title: "Skip", artist: "Artist B", startedAt: now, listened: 10, outcome: .skipped))
        let records = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        let summary = ListeningSummary(records: records, now: now)
        #expect(summary.total == 4)
        #expect(summary.played == 3)
        #expect(summary.skipped == 1)
        #expect(summary.listeningMinutes == 6)
        #expect(summary.topArtists.first == ArtistPlayCount(artist: "Artist A", plays: 2))
        #expect(summary.dailyCounts.reduce(0) { $0 + $1.plays } == 3)
    }

    @Test func weeklyRecapSummarizesOnlyTheRecentSevenDays() throws {
        let store = try PersistenceStore(inMemory: true)
        let now = Date.now
        store.record(session(title: "Current", artist: "Artist A", startedAt: now, listened: 180, outcome: .played))
        store.record(session(title: "Recent", artist: "Artist A", startedAt: now.addingTimeInterval(-86_400), listened: 120, outcome: .played))
        store.record(session(title: "Old", artist: "Artist B", startedAt: now.addingTimeInterval(-8 * 86_400), listened: 600, outcome: .played))
        let recap = WeeklyListeningRecap(
            records: try store.context.fetch(FetchDescriptor<ActivityRecord>()),
            now: now
        )
        #expect(recap.listens == 2)
        #expect(recap.minutes == 5)
        #expect(recap.uniqueArtists == 1)
        #expect(recap.topArtist == "Artist A")
        #expect(recap.shareText.contains("2 listens"))
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
    @Test func playbackProgressAdvancesLocallyClampsAndThrottlesAnnouncements() {
        let observedAt = Date(timeIntervalSince1970: 10_000)
        let playing = PlaybackSnapshot(
            track: nil,
            state: .playing,
            position: 42,
            observedAt: observedAt,
            confidence: .high
        )
        #expect(PlaybackProgressPresentation.position(
            for: playing,
            at: observedAt.addingTimeInterval(3),
            duration: 240
        ) == 45)
        #expect(PlaybackProgressPresentation.position(
            for: playing,
            at: observedAt.addingTimeInterval(500),
            duration: 240
        ) == 240)
        #expect(
            PlaybackProgressPresentation.accessibilityValue(position: 31, duration: 240)
                == PlaybackProgressPresentation.accessibilityValue(position: 44, duration: 240)
        )
        #expect(
            PlaybackProgressPresentation.accessibilityValue(position: 44, duration: 240)
                != PlaybackProgressPresentation.accessibilityValue(position: 45, duration: 240)
        )
    }

    @Test func dashboardMinimumSupportsNarrowResponsiveLayout() {
        #expect(DashboardLayout.minimumWidth >= 640)
        #expect(DashboardLayout.minimumHeight >= 520)
    }

    @Test func providerReorderActionsExposeConcreteAccessibleNames() {
        #expect(PlaybackProviderID.spotify.moveEarlierAccessibilityLabel == "Move Spotify earlier")
        #expect(PlaybackProviderID.youtubeMusic.moveLaterAccessibilityLabel == "Move YouTube Music later")
    }

    @Test func configuredPrioritySelectsThePreferredSimultaneousPlayer() async {
        let coordinator = PlaybackCoordinator()
        let now = Date(timeIntervalSince1970: 9_000)
        let selected = await coordinator.select(
            [
                ProviderSnapshot(
                    provider: .appleMusic,
                    playback: playback(platform: .appleMusic, state: .playing, at: now),
                    health: .available,
                    observedAt: now
                ),
                ProviderSnapshot(
                    provider: .spotify,
                    playback: playback(platform: .spotify, state: .playing, at: now),
                    health: .available,
                    observedAt: now
                ),
            ],
            priority: [.spotify, .appleMusic, .youtubeMusic, .tidal],
            now: now
        )

        #expect(selected.track?.platform == .spotify)
    }

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
        preferences.discordActivityName = "Tunes with {artist}"
        preferences.discordPresenceProfiles = [
            DiscordPresenceProfile.capture(name: "Backup Profile", preferences: preferences)
        ]
        preferences.excludedScrobbleArtists = "Private Artist"
        preferences.excludedScrobblePlatforms = [.youtubeMusic]
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
        #expect(targetPreferences.discordActivityName == "Tunes with {artist}")
        #expect(targetPreferences.discordPresenceProfiles.first?.name == "Backup Profile")
        #expect(targetPreferences.excludedScrobbleArtists == "Private Artist")
        #expect(targetPreferences.excludedScrobblePlatforms == [.youtubeMusic])
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

    @Test func comparisonOmitsAnEmptyPriorPeriod() throws {
        let store = try PersistenceStore(inMemory: true)
        let now = Date.now
        store.record(session(title: "Current", startedAt: now.addingTimeInterval(-86_400), platform: .appleMusic))
        let records = try store.context.fetch(FetchDescriptor<ActivityRecord>())
        let insights = ExtendedListeningInsights(records: records, period: .week, now: now)

        #expect(insights.comparison.current.listens == 1)
        #expect(insights.comparison.previous == nil)
        #expect(insights.comparison.listenDelta == nil)
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

@Suite("Service status copy")
struct ServiceStatusCopyTests {
    @Test func failedStatusUsesConsistentPresentationCopy() {
        let status = ServiceStatus.failed("Permission denied")
        #expect(status.presentationLabel == "Needs attention")
        #expect(status.detailLabel == "Permission denied")
        #expect(IntegrationID.appleMusic.recoveryTitle == "Open Settings")
        #expect(IntegrationID.discord.recoveryTitle == "Reconnect")
        #expect(IntegrationID.lastFM.recoveryTitle == "Reconnect")
    }

    @Test func everyStatusHasOneCanonicalPresentationName() {
        #expect(ServiceStatus.disabled.presentationLabel == "Disabled")
        #expect(ServiceStatus.inactive.presentationLabel == "Not active")
        #expect(ServiceStatus.awaitingPermission.presentationLabel == "Permission required")
        #expect(ServiceStatus.connecting.presentationLabel == "Connecting")
        #expect(ServiceStatus.connected.presentationLabel == "Connected")
        #expect(ServiceStatus.offline.presentationLabel == "Offline")
        #expect(ServiceStatus.authorizationExpired.presentationLabel == "Authorization expired")
        #expect(ServiceStatus.failed("transport timeout").presentationLabel == "Needs attention")
        #expect(ServiceStatus.failed("transport timeout").detailLabel == "transport timeout")
        #expect(IntegrationID.youtubeMusic.recoveryTitle == "Reconnect")
        #expect(IntegrationID.spotify.recoveryTitle == nil)
        #expect(IntegrationID.tidal.recoveryTitle == nil)
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
        let store = try PersistenceStore(inMemory: true)
        let model = AppModel(
            store: store,
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

        let demoSnapshot = DemoPlaybackSequence.snapshot(at: Date(), startedAt: Date())
        let demoTrack = try #require(demoSnapshot.track)
        store.record(PlaybackSession(
            id: UUID(), track: demoTrack, startedAt: .now, accumulatedPlayTime: 32,
            lastPosition: 32, eligibility: .eligible, outcome: .played
        ))
        #expect(try store.context.fetchCount(FetchDescriptor<ActivityRecord>()) == 1)

        model.snapshot = demoSnapshot
        model.setDemoModeEnabled(false)
        #expect(model.allowsExternalPublishing)
        #expect(model.snapshot.track == nil)
        #expect(model.snapshot.state == .stopped)
        #expect(model.musicStatus == .connecting)
        #expect(try store.context.fetchCount(FetchDescriptor<ActivityRecord>()) == 0)

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
