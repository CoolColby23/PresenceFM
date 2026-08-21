import AuthenticationServices
import Foundation
import PresenceFMCore
import UIKit

enum CompanionLastFMError: LocalizedError {
    case configuration, unauthorized, invalidResponse, api(String)
    var errorDescription: String? {
        switch self {
        case .configuration: "Add Last.fm credentials to Config/Local.xcconfig."
        case .unauthorized: "Connect Last.fm in Settings."
        case .invalidResponse: "Last.fm returned an invalid response."
        case .api(let message): message
        }
    }
}

actor CompanionLastFMClient {
    private let configuration: CompanionBuildConfiguration
    private let keychain: CompanionKeychain
    private let session: URLSession
    private var earliestRequest = Date.distantPast

    init(configuration: CompanionBuildConfiguration, keychain: CompanionKeychain, session: URLSession = .shared) {
        self.configuration = configuration; self.keychain = keychain; self.session = session
    }

    func authorizationURL() async throws -> URL {
        let response = try await call(method: "auth.getToken", parameters: [:], sessionKey: nil)
        guard let token = response["token"] as? String,
            var components = URLComponents(string: "https://www.last.fm/api/auth/")
        else { throw CompanionLastFMError.invalidResponse }
        components.queryItems = [
            .init(name: "api_key", value: configuration.apiKey), .init(name: "token", value: token),
            .init(name: "cb", value: "presencefm://lastfm-auth"),
        ]
        guard let url = components.url else { throw CompanionLastFMError.invalidResponse }
        UserDefaults.standard.set(token, forKey: "PresenceFMLastFMAuthToken")
        return url
    }

    func completeAuthorization() async throws -> String {
        guard let token = UserDefaults.standard.string(forKey: "PresenceFMLastFMAuthToken") else { throw CompanionLastFMError.unauthorized }
        let response = try await call(method: "auth.getSession", parameters: ["token": token], sessionKey: nil)
        guard let sessionObject = response["session"] as? [String: Any],
            let key = sessionObject["key"] as? String, let username = sessionObject["name"] as? String
        else {
            throw CompanionLastFMError.invalidResponse
        }
        try await keychain.set(key, for: .lastFMSession); try await keychain.set(username, for: .lastFMUsername)
        UserDefaults.standard.removeObject(forKey: "PresenceFMLastFMAuthToken")
        return username
    }

    func username() async -> String? { await keychain.value(for: .lastFMUsername) }

    func disconnect() async throws {
        try await keychain.set(nil, for: .lastFMSession); try await keychain.set(nil, for: .lastFMUsername)
    }

    func updateNowPlaying(_ metadata: ScrobbleMetadata) async throws {
        let sessionKey = try await requiredSession()
        var parameters = ["track": metadata.title, "artist": metadata.artist]
        if let album = metadata.album { parameters["album"] = album }
        if let duration = metadata.duration { parameters["duration"] = String(Int(duration)) }
        _ = try await call(method: "track.updateNowPlaying", parameters: parameters, sessionKey: sessionKey)
    }

    func scrobble(_ metadata: ScrobbleMetadata) async throws {
        guard let startedAt = metadata.startedAt else { throw CompanionLastFMError.invalidResponse }
        let sessionKey = try await requiredSession()
        var parameters = [
            "track": metadata.title, "artist": metadata.artist,
            "timestamp": String(Int(startedAt.timeIntervalSince1970)),
        ]
        if let album = metadata.album { parameters["album"] = album }
        if let duration = metadata.duration { parameters["duration"] = String(Int(duration)) }
        let response = try await call(method: "track.scrobble", parameters: parameters, sessionKey: sessionKey)
        guard let scrobbles = response["scrobbles"] as? [String: Any],
            let attributes = scrobbles["@attr"] as? [String: Any],
            String(describing: attributes["accepted"] ?? "0") == "1"
        else { throw CompanionLastFMError.api("Last.fm did not accept the scrobble.") }
    }

    private func requiredSession() async throws -> String {
        guard let value = await keychain.value(for: .lastFMSession), !value.isEmpty else { throw CompanionLastFMError.unauthorized }
        return value
    }

    private func call(method: String, parameters: [String: String], sessionKey: String?) async throws -> [String: Any] {
        guard configuration.isLastFMConfigured else { throw CompanionLastFMError.configuration }
        let delay = earliestRequest.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        earliestRequest = Date().addingTimeInterval(0.35)
        let values = LastFMRequestBuilder.values(
            method: method, parameters: parameters, apiKey: configuration.apiKey, secret: configuration.sharedSecret, sessionKey: sessionKey)
        var request = URLRequest(url: URL(string: "https://ws.audioscrobbler.com/2.0/")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = LastFMRequestBuilder.body(values)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CompanionLastFMError.invalidResponse }
        if let message = object["message"] as? String { throw CompanionLastFMError.api(message) }
        return object
    }
}
