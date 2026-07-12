import CryptoKit
import Foundation

enum LastFMError: LocalizedError {
    case missingCredentials, unauthenticated, invalidResponse, api(Int, String), transport(String)
    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Enter a Last.fm API key and shared secret."
        case .unauthenticated: "Connect your Last.fm account."
        case .invalidResponse: "Last.fm returned an invalid response."
        case .api(_, let message), .transport(let message): message
        }
    }
}

actor LastFMClient: Scrobbling, ScrobbleSubmitting {
    private let keychain: KeychainStore
    private let session: URLSession
    private var earliestRequestAt = Date.distantPast

    init(keychain: KeychainStore, session: URLSession = .shared) {
        self.keychain = keychain; self.session = session
    }

    func beginAuthorization() async throws -> URL {
        let credentials = try await credentials(requireSession: false)
        let response = try await call(method: "auth.getToken", parameters: [:], signed: true, sessionKey: nil, credentials: credentials)
        guard let token = response["token"] as? String,
              let url = URL(string: "https://www.last.fm/api/auth/?api_key=\(credentials.key)&token=\(token)") else {
            throw LastFMError.invalidResponse
        }
        try await keychain.set(token, for: .lastFMSessionKey)
        return url
    }

    func completeAuthorization() async throws -> String {
        let credentials = try await credentials(requireSession: false)
        guard let token = await keychain.value(for: .lastFMSessionKey) else { throw LastFMError.unauthenticated }
        let response = try await call(method: "auth.getSession", parameters: ["token": token], signed: true, sessionKey: nil, credentials: credentials)
        guard let sessionObject = response["session"] as? [String: Any],
              let key = sessionObject["key"] as? String, let name = sessionObject["name"] as? String else {
            throw LastFMError.invalidResponse
        }
        try await keychain.set(key, for: .lastFMSessionKey)
        try await keychain.set(name, for: .lastFMUsername)
        return name
    }

    func updateNowPlaying(_ playback: PlaybackSession) async throws {
        let credentials = try await credentials(requireSession: true)
        var values = trackParameters(playback)
        values["duration"] = String(Int(playback.track.duration))
        _ = try await call(method: "track.updateNowPlaying", parameters: values, signed: true,
                           sessionKey: credentials.sessionKey, credentials: credentials)
    }

    func enqueueScrobble(_ session: PlaybackSession) async { }

    func scrobble(title: String, artist: String, album: String?, duration: Double, startedAt: Date) async throws {
        let credentials = try await credentials(requireSession: true)
        var values = ["track": title, "artist": artist, "duration": String(Int(duration)),
                      "timestamp": String(Int(startedAt.timeIntervalSince1970))]
        if let album, !album.isEmpty { values["album"] = album }
        _ = try await call(method: "track.scrobble", parameters: values, signed: true,
                           sessionKey: credentials.sessionKey, credentials: credentials)
    }

    private struct Credentials { let key: String; let secret: String; let sessionKey: String? }

    private func credentials(requireSession: Bool) async throws -> Credentials {
        guard let key = await keychain.value(for: .lastFMAPIKey), !key.isEmpty,
              let secret = await keychain.value(for: .lastFMSecret), !secret.isEmpty else {
            throw LastFMError.missingCredentials
        }
        let sessionKey = await keychain.value(for: .lastFMSessionKey)
        if requireSession && (sessionKey?.isEmpty != false) { throw LastFMError.unauthenticated }
        return Credentials(key: key, secret: secret, sessionKey: sessionKey)
    }

    private func trackParameters(_ session: PlaybackSession) -> [String: String] {
        var values = ["track": session.track.title, "artist": session.track.artist]
        if let album = session.track.album { values["album"] = album }
        return values
    }

    private func call(method: String, parameters: [String: String], signed: Bool, sessionKey: String?, credentials: Credentials) async throws -> [String: Any] {
        while earliestRequestAt.timeIntervalSinceNow > 0 {
            try await Task.sleep(for: .seconds(earliestRequestAt.timeIntervalSinceNow))
        }
        earliestRequestAt = Date().addingTimeInterval(0.35)
        var values = parameters
        values["method"] = method; values["api_key"] = credentials.key
        if let sessionKey { values["sk"] = sessionKey }
        if signed { values["api_sig"] = Self.signature(values, secret: credentials.secret) }
        values["format"] = "json"
        var request = URLRequest(url: URL(string: "https://ws.audioscrobbler.com/2.0/")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values.sorted { $0.key < $1.key }.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                let retryAfter = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
                earliestRequestAt = Date().addingTimeInterval(max(5, retryAfter))
                throw LastFMError.api(29, "Last.fm is busy. PresenceFM will retry automatically.")
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw LastFMError.transport("Last.fm returned HTTP \(http.statusCode).")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LastFMError.invalidResponse }
            if let code = object["error"] as? Int {
                if code == 29 { earliestRequestAt = Date().addingTimeInterval(30) }
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
}

private extension String {
    var formEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? self }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics; set.insert(charactersIn: "-._~"); return set
    }()
}
