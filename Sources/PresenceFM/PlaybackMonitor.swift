import AppKit
import CryptoKit
import Foundation

enum PlaybackSourceSelector {
    static func select(
        music: PlaybackSnapshot, spotify: PlaybackSnapshot?, youtube: PlaybackSnapshot?,
        tidal: PlaybackSnapshot?
    ) -> PlaybackSnapshot {
        let candidates = [Optional(music), spotify, youtube, tidal].compactMap { $0 }
        if let playing = candidates.first(where: { $0.state == .playing }) { return playing }
        if music.confidence == .low { return music }
        if let paused = candidates.first(where: { $0.state == .paused }) { return paused }
        return music
    }
}

actor PlaybackMonitor: PlaybackProviding {
    private let clock: any AppClock
    private let providers: [PlaybackProviderID: any PlaybackProvider]
    private let coordinator = PlaybackCoordinator()
    private var continuation: AsyncStream<PlaybackSnapshot>.Continuation?
    private var monitoringTask: Task<Void, Never>?
    private var enabledProviders = Set(PlaybackProviderID.allCases)
    private var demoStartedAt: Date?

    init(
        credentials: CredentialStore,
        clock: any AppClock = SystemAppClock(),
        providers: [PlaybackProviderID: any PlaybackProvider]? = nil
    ) {
        self.clock = clock
        self.providers = providers ?? [
            .appleMusic: AppleMusicPlaybackProvider(),
            .spotify: SpotifyPlaybackProvider(),
            .youtubeMusic: YTMDesktopPlaybackProvider(credentials: credentials, clock: clock),
            .tidal: TidalPlaybackProvider()
        ]
    }

    func snapshots() -> AsyncStream<PlaybackSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            monitoringTask?.cancel()
            monitoringTask = Task { await poll() }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        continuation?.finish()
    }

    func setEnabledProviders(_ providers: Set<PlaybackProviderID>) {
        enabledProviders = providers
    }

    func setDemoModeEnabled(_ enabled: Bool) {
        demoStartedAt = enabled ? clock.now : nil
        if let demoStartedAt {
            continuation?.yield(DemoPlaybackSequence.snapshot(at: clock.now, startedAt: demoStartedAt))
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            let snapshot = await readPlayback()
            continuation?.yield(snapshot)
            // Music does not expose a reliable public callback for every playback change.
            // Keep the fallback poll quick enough that track transitions feel immediate.
            let interval = snapshot.state == .playing
                ? IntegrationPolicy.playingPollInterval
                : IntegrationPolicy.idlePollInterval
            try? await clock.sleep(until: clock.now.addingTimeInterval(interval))
        }
    }

    private func readPlayback() async -> PlaybackSnapshot {
        if let demoStartedAt {
            return DemoPlaybackSequence.snapshot(at: clock.now, startedAt: demoStartedAt)
        }
        var snapshots: [ProviderSnapshot] = []
        for id in [PlaybackProviderID.appleMusic, .spotify] where enabledProviders.contains(id) {
            if let provider = providers[id] { snapshots.append(await provider.snapshot()) }
        }
        let preliminary = await coordinator.select(snapshots, now: clock.now)
        if preliminary.state == .playing { return preliminary }
        if enabledProviders.contains(.youtubeMusic), let provider = providers[.youtubeMusic] {
            snapshots.append(await provider.snapshot())
            let withYouTube = await coordinator.select(snapshots, now: clock.now)
            if withYouTube.state == .playing { return withYouTube }
        }
        if enabledProviders.contains(.tidal), let provider = providers[.tidal] {
            snapshots.append(await provider.snapshot())
        }
        return await coordinator.select(snapshots, now: clock.now)
    }

    nonisolated static func readMusic() -> PlaybackSnapshot {
        let now = Date()
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty == false else {
            return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .high)
        }
        let source = """
        tell application "Music"
          set s to player state as text
          if s is "stopped" then return "stopped"
          set t to current track
          set sep to ASCII character 30
          set trackName to ""
          set trackArtist to ""
          set trackAlbum to ""
          set trackDuration to "0"
          set trackPosition to "0"
          set trackID to ""
          set trackClass to ""
          set trackAddress to ""
          try
            set trackName to name of t as text
          end try
          try
            set trackArtist to artist of t as text
          end try
          try
            set trackAlbum to album of t as text
          end try
          try
            set trackDuration to duration of t as text
          end try
          try
            set trackPosition to player position as text
          end try
          try
            set trackID to persistent ID of t as text
          end try
          try
            set trackClass to class of t as text
          end try
          try
            if class of t is URL track then set trackAddress to address of t as text
          end try
          return s & sep & trackName & sep & trackArtist & sep & trackAlbum & sep & trackDuration & sep & trackPosition & sep & trackID & sep & trackClass & sep & trackAddress
        end tell
        """
        var error: NSDictionary?
        guard let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else {
            return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .low)
        }
        return parseMusic(value, observedAt: now)
    }

    nonisolated static func parseMusic(_ value: String, observedAt: Date = .now) -> PlaybackSnapshot {
        if value == "stopped" { return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: observedAt, confidence: .high) }
        let fields = value.components(separatedBy: CharacterSet(charactersIn: String(UnicodeScalar(30)!)))
        guard fields.count >= 8 else {
            return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: observedAt, confidence: .low)
        }
        let duration = Double(fields[4]) ?? 0
        let position = Double(fields[5]) ?? 0
        let state: PlaybackState = fields[0] == "playing" ? .playing : .paused
        let kind = fields[7].lowercased()
        let isRadio = kind.contains("url")
        let trackSource: TrackSource = isRadio ? .radioStream : (kind.contains("file") ? .localFile : .appleMusicCatalog)
        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawArtist = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.isEmpty && isRadio ? (album.isEmpty ? "Apple Music Radio" : album) : rawArtist
        let address = fields.count > 8 ? fields[8].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let addressFingerprint = SHA256.hash(data: Data(address.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let identity = isRadio
            ? "apple-radio:\(addressFingerprint)|\(artist)|\(title)"
            : (fields[6].isEmpty ? "apple:\(artist)|\(title)|\(album)" : fields[6])
        let searchTerms = "\(title) \(artist)"
        let searchQuery = searchTerms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var streamComponents = URLComponents(string: address)
        streamComponents?.query = nil
        streamComponents?.fragment = nil
        let streamURL = streamComponents?.url
        let appleMusicURL = isRadio
            ? (streamURL?.host?.hasSuffix("music.apple.com") == true ? streamURL : nil)
            : URL(string: "https://music.apple.com/us/search?term=\(searchQuery)")
        let track = TrackMetadata(
            identity: TrackIdentity(persistentID: identity), title: title, artist: artist,
            album: album.isEmpty ? nil : album, duration: duration, source: trackSource,
            appleMusicURL: appleMusicURL, artworkReference: nil
        )
        let hasUsableMetadata = !title.isEmpty && (isRadio || (duration > 0 && !artist.isEmpty))
        return PlaybackSnapshot(track: track, state: state, position: position, observedAt: observedAt,
                                confidence: hasUsableMetadata ? .high : .low)
    }

    nonisolated static func readSpotify() -> PlaybackSnapshot? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else { return nil }
        let now = Date()
        let source = """
        tell application "Spotify"
          set s to player state as text
          if s is "stopped" then return "stopped"
          set t to current track
          set sep to ASCII character 30
          return s & sep & (name of t as text) & sep & (artist of t as text) & sep & (album of t as text) & sep & (duration of t as text) & sep & (player position as text) & sep & (id of t as text) & sep & (spotify url of t as text)
        end tell
        """
        var error: NSDictionary?
        guard let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else {
            return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .low)
        }
        return parseSpotify(value, observedAt: now)
    }

    nonisolated static func parseSpotify(_ value: String, observedAt: Date = .now) -> PlaybackSnapshot? {
        if value == "stopped" { return nil }
        let fields = value.components(separatedBy: CharacterSet(charactersIn: String(UnicodeScalar(30)!)))
        guard fields.count >= 8, let durationMilliseconds = Double(fields[4]), let position = Double(fields[5]) else { return nil }
        let link = URL(string: fields[7])
        let track = TrackMetadata(
            identity: .init(persistentID: "spotify:\(fields[6])"), title: fields[1], artist: fields[2],
            album: fields[3].isEmpty ? nil : fields[3], duration: durationMilliseconds / 1_000,
            source: .appleMusicCatalog, appleMusicURL: link, artworkReference: nil, platform: .spotify
        )
        return PlaybackSnapshot(
            track: track, state: fields[0] == "playing" ? .playing : .paused,
            position: position, observedAt: observedAt, confidence: .high
        )
    }
}
