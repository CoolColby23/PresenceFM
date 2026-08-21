import AppKit
import Darwin
import Foundation

struct AppleMusicPlaybackProvider: PlaybackProvider {
    let id = PlaybackProviderID.appleMusic
    func snapshot() async -> ProviderSnapshot {
        let playback = PlaybackMonitor.readMusic()
        let health: ProviderHealth = playback.confidence == .low
            ? .permissionRequired
            : (playback.track == nil ? .inactive : .available)
        return ProviderSnapshot(
            provider: id, playback: playback.track == nil ? nil : playback,
            health: health, observedAt: playback.observedAt
        )
    }
}

struct SpotifyPlaybackProvider: PlaybackProvider {
    let id = PlaybackProviderID.spotify
    func snapshot() async -> ProviderSnapshot {
        let playback = PlaybackMonitor.readSpotify()
        return ProviderSnapshot(
            provider: id, playback: playback,
            health: playback == nil ? .inactive : .available,
            observedAt: playback?.observedAt ?? .now
        )
    }
}

actor YTMDesktopPlaybackProvider: PlaybackProvider {
    let id = PlaybackProviderID.youtubeMusic
    private let credentials: CredentialStore
    private let client: YTMDesktopClient
    private let clock: any AppClock
    private var lastSnapshot: PlaybackSnapshot?
    private var lastPoll = Date.distantPast

    init(credentials: CredentialStore, client: YTMDesktopClient = YTMDesktopClient(), clock: any AppClock = SystemAppClock()) {
        self.credentials = credentials; self.client = client; self.clock = clock
    }

    func snapshot() async -> ProviderSnapshot {
        guard let token = await credentials.value(for: .ytmDesktopToken) else {
            lastSnapshot = nil
            return ProviderSnapshot(provider: id, playback: nil, health: .inactive, observedAt: clock.now)
        }
        if clock.now.timeIntervalSince(lastPoll) < IntegrationPolicy.youtubePollInterval {
            return ProviderSnapshot(provider: id, playback: extrapolated(lastSnapshot), health: .available, observedAt: clock.now)
        }
        lastPoll = clock.now
        do {
            lastSnapshot = try await client.snapshot(token: token)
            return ProviderSnapshot(
                provider: id, playback: extrapolated(lastSnapshot),
                health: lastSnapshot == nil ? .inactive : .available, observedAt: clock.now
            )
        } catch {
            return ProviderSnapshot(
                provider: id, playback: extrapolated(lastSnapshot),
                health: .unavailable(error.localizedDescription), observedAt: clock.now
            )
        }
    }

    private func extrapolated(_ snapshot: PlaybackSnapshot?) -> PlaybackSnapshot? {
        guard let snapshot, snapshot.state == .playing else { return snapshot }
        return PlaybackSnapshot(
            track: snapshot.track, state: snapshot.state,
            position: snapshot.position + clock.now.timeIntervalSince(snapshot.observedAt),
            observedAt: clock.now, confidence: snapshot.confidence
        )
    }
}

struct TidalPlaybackProvider: PlaybackProvider {
    let id = PlaybackProviderID.tidal
    func snapshot() async -> ProviderSnapshot {
        let playback = await TidalNowPlayingProvider.snapshot()
        return ProviderSnapshot(
            provider: id, playback: playback,
            health: playback == nil ? .inactive : .available,
            observedAt: playback?.observedAt ?? .now
        )
    }
}

enum YTMDesktopError: LocalizedError {
    case unavailable, authorizationDisabled, authorizationDenied, invalidResponse, unauthorized

    var errorDescription: String? {
        switch self {
        case .unavailable: "YTMDesktop Companion Server is unavailable. Enable it in YTMDesktop settings."
        case .authorizationDisabled: "Enable companion authorization in YTMDesktop, then try again."
        case .authorizationDenied: "YTMDesktop authorization was denied or timed out."
        case .invalidResponse: "YTMDesktop returned an invalid response."
        case .unauthorized: "Reconnect YTMDesktop in PresenceFM settings."
        }
    }
}

actor YTMDesktopClient {
    private let baseURL = URL(string: "http://127.0.0.1:9863/api/v1/")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func authorize() async throws -> String {
        let codeResponse = try await post(
            "auth/requestcode",
            body: ["appId": "presencefm", "appName": "PresenceFM", "appVersion": ReleaseConfiguration.version]
        )
        guard let code = codeResponse["code"] as? String else { throw YTMDesktopError.invalidResponse }
        let tokenResponse = try await post("auth/request", body: ["appId": "presencefm", "code": code], timeout: 35)
        guard let token = tokenResponse["token"] as? String, !token.isEmpty else { throw YTMDesktopError.authorizationDenied }
        return token
    }

    func snapshot(token: String) async throws -> PlaybackSnapshot? {
        var request = URLRequest(url: baseURL.appendingPathComponent("state"))
        request.timeoutInterval = 2
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YTMDesktopError.invalidResponse }
        if http.statusCode == 401 { throw YTMDesktopError.unauthorized }
        guard (200...299).contains(http.statusCode) else { return nil }
        return try Self.parseSnapshot(data)
    }

    nonisolated static func parseSnapshot(_ data: Data, observedAt: Date = .now) throws -> PlaybackSnapshot? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let player = object["player"] as? [String: Any],
              let video = object["video"] as? [String: Any] else { return nil }
        let state = player["trackState"] as? Int ?? -1
        guard state == 0 || state == 1 || state == 2 else { return nil }
        guard let title = video["title"] as? String, let artist = video["author"] as? String,
              let duration = (video["durationSeconds"] as? NSNumber)?.doubleValue,
              let id = video["id"] as? String else { throw YTMDesktopError.invalidResponse }
        let position = (player["videoProgress"] as? NSNumber)?.doubleValue ?? 0
        let isLive = video["isLive"] as? Bool ?? false
        let thumbnailURL = Self.bestThumbnailURL(from: video)
        let track = TrackMetadata(
            identity: .init(persistentID: "youtube:\(id)"), title: title, artist: artist,
            album: video["album"] as? String, duration: duration,
            source: isLive ? .radioStream : .appleMusicCatalog,
            appleMusicURL: URL(string: "https://music.youtube.com/watch?v=\(id)"),
            artworkReference: thumbnailURL.map(ArtworkReference.remote), platform: .youtubeMusic
        )
        return PlaybackSnapshot(
            track: track, state: state == 1 ? .playing : .paused, position: position,
            observedAt: observedAt, confidence: .high
        )
    }

    nonisolated private static func bestThumbnailURL(from video: [String: Any]) -> URL? {
        if let thumbnails = video["thumbnails"] as? [[String: Any]] {
            return thumbnails.reversed().compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.first
        }
        if let thumbnail = video["thumbnail"] as? String { return URL(string: thumbnail) }
        if let thumbnail = video["thumbnail"] as? [String: Any], let value = thumbnail["url"] as? String {
            return URL(string: value)
        }
        return nil
    }

    private func post(_ path: String, body: [String: String], timeout: TimeInterval = 4) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw YTMDesktopError.invalidResponse }
            if http.statusCode == 403 { throw YTMDesktopError.authorizationDisabled }
            guard (200...299).contains(http.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw YTMDesktopError.authorizationDenied
            }
            return object
        } catch let error as YTMDesktopError { throw error }
        catch { throw YTMDesktopError.unavailable }
    }
}

/// TIDAL does not expose an AppleScript dictionary. macOS's system Now Playing
/// service is the only local metadata surface its desktop app participates in.
/// This adapter dynamically loads that service so PresenceFM still launches if
/// Apple changes or removes the private symbols in a future macOS release.
enum TidalNowPlayingProvider {
    private struct UnsafeInfo: @unchecked Sendable { let value: [String: Any]? }
    private typealias InfoCallback = @convention(block) (CFDictionary?) -> Void
    private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping InfoCallback) -> Void
    private typealias PIDCallback = @convention(block) (Int32) -> Void
    private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void

    static func snapshot() async -> PlaybackSnapshot? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
              let pidSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") else { return nil }
        let infoFunction = unsafeBitCast(infoSymbol, to: InfoFunction.self)
        let pidFunction = unsafeBitCast(pidSymbol, to: PIDFunction.self)
        let pid: Int32 = await withCheckedContinuation { continuation in
            pidFunction(.main) { continuation.resume(returning: $0) }
        }
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier?.localizedCaseInsensitiveContains("tidal") == true else { return nil }
        let boxedInfo: UnsafeInfo = await withCheckedContinuation { continuation in
            infoFunction(.main) { continuation.resume(returning: UnsafeInfo(value: $0 as? [String: Any])) }
        }
        let info = boxedInfo.value
        guard let info,
              let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
              let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
              let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue else { return nil }
        let position = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
        let identifier = info["kMRMediaRemoteNowPlayingInfoUniqueIdentifier"] as? String ?? "\(artist)|\(title)|\(duration)"
        let artworkReference = (info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).map(ArtworkReference.embedded)
        let track = TrackMetadata(
            identity: .init(persistentID: "tidal:\(identifier)"), title: title, artist: artist,
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String, duration: duration,
            source: .appleMusicCatalog,
            appleMusicURL: URL(string: "https://listen.tidal.com/search?q=\("\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"),
            artworkReference: artworkReference, platform: .tidal
        )
        return PlaybackSnapshot(track: track, state: rate > 0 ? .playing : .paused, position: position, observedAt: .now, confidence: .high)
    }
}
