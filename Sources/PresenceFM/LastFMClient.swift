import CryptoKit
import Foundation

enum LastFMError: LocalizedError {
    case missingCredentials, unauthenticated, invalidResponse, rejected(String), api(Int, String), transport(String)
    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Enter a Last.fm API key and shared secret."
        case .unauthenticated: "Connect your Last.fm account."
        case .invalidResponse: "Last.fm returned an invalid response."
        case .rejected(let message), .api(_, let message), .transport(let message): message
        }
    }
}

actor LastFMClient: Scrobbling, ScrobbleSubmitting {
    private let credentialsStore: CredentialStore
    private let session: URLSession
    private let clock: any AppClock
    private var earliestRequestAt = Date.distantPast

    init(credentials: CredentialStore, session: URLSession = .shared, clock: any AppClock = SystemAppClock()) {
        self.credentialsStore = credentials; self.session = session; self.clock = clock
    }

    func beginAuthorization() async throws -> URL {
        let credentials = try await credentials(requireSession: false)
        let response = try await call(method: "auth.getToken", parameters: [:], signed: true, sessionKey: nil, credentials: credentials)
        guard let token = response["token"] as? String,
              let url = URL(string: "https://www.last.fm/api/auth/?api_key=\(credentials.key)&token=\(token)") else {
            throw LastFMError.invalidResponse
        }
        // The short-lived authorization token is not a session key. Keeping the
        // values separate prevents reconnecting from destroying a working session.
        try await credentialsStore.set(token, for: .lastFMAuthToken)
        return url
    }

    func completeAuthorization() async throws -> String {
        let credentials = try await credentials(requireSession: false)
        guard let token = await credentialsStore.value(for: .lastFMAuthToken) else { throw LastFMError.unauthenticated }
        let response = try await call(method: "auth.getSession", parameters: ["token": token], signed: true, sessionKey: nil, credentials: credentials)
        guard let sessionObject = response["session"] as? [String: Any],
              let key = sessionObject["key"] as? String, let name = sessionObject["name"] as? String else {
            throw LastFMError.invalidResponse
        }
        try await credentialsStore.set(key, for: .lastFMSessionKey)
        try await credentialsStore.set(name, for: .lastFMUsername)
        try await credentialsStore.remove(.lastFMAuthToken)
        return name
    }

    func updateNowPlaying(_ playback: PlaybackSession) async throws {
        let credentials = try await credentials(requireSession: true)
        var values = trackParameters(playback)
        if playback.track.duration > 0 { values["duration"] = String(Int(playback.track.duration)) }
        _ = try await call(method: "track.updateNowPlaying", parameters: values, signed: true,
                           sessionKey: credentials.sessionKey, credentials: credentials)
    }

    func enqueueScrobble(_ session: PlaybackSession) async { }

    func scrobble(title: String, artist: String, album: String?, duration: Double, startedAt: Date) async throws {
        let credentials = try await credentials(requireSession: true)
        let values = Self.scrobbleParameters(
            title: title, artist: artist, album: album, duration: duration, startedAt: startedAt
        )
        let response = try await call(method: "track.scrobble", parameters: values, signed: true,
                                      sessionKey: credentials.sessionKey, credentials: credentials)
        try Self.validateScrobbleResponse(response)
    }

    /// Fetches recent scrobbles from the connected Last.fm account, including listens
    /// recorded on other devices. Requires an authorized session and username.
    func recentTracks(limit: Int = 50) async throws -> [LastFMRemoteTrack] {
        let credentials = try await credentials(requireSession: true)
        guard let username = await credentialsStore.value(for: .lastFMUsername), !username.isEmpty else {
            throw LastFMError.unauthenticated
        }
        let response = try await call(
            method: "user.getRecentTracks",
            parameters: [
                "user": username,
                "limit": String(min(max(limit, 1), 200)),
                "extended": "1",
            ],
            signed: false,
            sessionKey: nil,
            credentials: credentials
        )
        return try Self.parseRecentTracks(response)
    }

    nonisolated static func parseRecentTracks(_ response: [String: Any]) throws -> [LastFMRemoteTrack] {
        guard let recent = response["recenttracks"] as? [String: Any] else {
            throw LastFMError.invalidResponse
        }
        let rawTracks: [[String: Any]]
        if let array = recent["track"] as? [[String: Any]] {
            rawTracks = array
        } else if let single = recent["track"] as? [String: Any] {
            rawTracks = [single]
        } else {
            return []
        }
        return rawTracks.compactMap(LastFMRemoteTrack.init(json:))
    }

    private struct Credentials { let key: String; let secret: String; let sessionKey: String? }

    nonisolated static func scrobbleParameters(
        title: String, artist: String, album: String?, duration: Double, startedAt: Date
    ) -> [String: String] {
        var values = ["track": title, "artist": artist,
                      "timestamp": String(Int(startedAt.timeIntervalSince1970))]
        if duration > 0 { values["duration"] = String(Int(duration)) }
        else { values["chosenByUser"] = "0" }
        if let album, !album.isEmpty { values["album"] = album }
        return values
    }

    private func credentials(requireSession: Bool) async throws -> Credentials {
        guard let key = await credentialsStore.value(for: .lastFMAPIKey), !key.isEmpty,
              let secret = await credentialsStore.value(for: .lastFMSecret), !secret.isEmpty else {
            throw LastFMError.missingCredentials
        }
        let sessionKey = await credentialsStore.value(for: .lastFMSessionKey)
        if requireSession && (sessionKey?.isEmpty != false) { throw LastFMError.unauthenticated }
        return Credentials(key: key, secret: secret, sessionKey: sessionKey)
    }

    private func trackParameters(_ session: PlaybackSession) -> [String: String] {
        var values = ["track": session.track.title, "artist": session.track.artist]
        if let album = session.track.album { values["album"] = album }
        return values
    }

    private func call(method: String, parameters: [String: String], signed: Bool, sessionKey: String?, credentials: Credentials) async throws -> [String: Any] {
        // Reserve the request slot before suspending. Actors are reentrant, so merely
        // sleeping until earliestRequestAt lets every waiting call wake together and
        // send a burst that Last.fm rejects with error 29.
        let now = clock.now
        let requestAt = max(now, earliestRequestAt)
        earliestRequestAt = requestAt.addingTimeInterval(0.35)
        let delay = requestAt.timeIntervalSince(now)
        if delay > 0 { try await clock.sleep(until: requestAt) }
        let values = Self.requestValues(
            method: method, parameters: parameters, apiKey: credentials.key,
            secret: credentials.secret, sessionKey: sessionKey, signed: signed
        )
        var request = URLRequest(url: URL(string: "https://ws.audioscrobbler.com/2.0/")!)
        request.httpMethod = "POST"; request.timeoutInterval = IntegrationPolicy.lastFMTimeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.encodedBody(values)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                let retryAfter = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
                earliestRequestAt = clock.now.addingTimeInterval(max(5, retryAfter))
                throw LastFMError.api(29, "Last.fm is busy. PresenceFM will retry automatically.")
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw LastFMError.transport("Last.fm returned HTTP \(http.statusCode).")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LastFMError.invalidResponse }
            let code = (object["error"] as? Int) ?? (object["error"] as? String).flatMap(Int.init)
            if let code {
                if code == 29 { earliestRequestAt = clock.now.addingTimeInterval(30) }
                throw LastFMError.api(code, object["message"] as? String ?? "Last.fm error \(code)")
            }
            return object
        } catch let error as LastFMError { throw error }
        catch { throw LastFMError.transport(error.localizedDescription) }
    }

    static func signature(_ parameters: [String: String], secret: String) -> String {
        let material = parameters.filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }.map { $0.key + $0.value }.joined() + secret
        return Insecure.MD5.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func requestValues(
        method: String, parameters: [String: String], apiKey: String, secret: String,
        sessionKey: String?, signed: Bool
    ) -> [String: String] {
        var values = parameters
        values["method"] = method
        values["api_key"] = apiKey
        if let sessionKey { values["sk"] = sessionKey }
        if signed { values["api_sig"] = signature(values, secret: secret) }
        values["format"] = "json"
        return values
    }

    static func encodedBody(_ values: [String: String]) -> Data {
        values.sorted { $0.key < $1.key }
            .map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }
            .joined(separator: "&").data(using: .utf8) ?? Data()
    }

    static func validateScrobbleResponse(_ response: [String: Any]) throws {
        guard let scrobbles = response["scrobbles"] as? [String: Any],
              let attributes = scrobbles["@attr"] as? [String: Any] else {
            throw LastFMError.invalidResponse
        }
        let accepted: Int? = {
            if let value = attributes["accepted"] as? String { return Int(value) }
            return attributes["accepted"] as? Int
        }()
        guard accepted == 1 else {
            let ignoredMessage = ((scrobbles["scrobble"] as? [String: Any])?["ignoredMessage"] as? [String: Any])?["#text"] as? String
            throw LastFMError.rejected(ignoredMessage?.isEmpty == false ? ignoredMessage! : "Last.fm did not accept the scrobble.")
        }
    }
}

private extension String {
    var formEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? self }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics; set.insert(charactersIn: "-._~"); return set
    }()
}
