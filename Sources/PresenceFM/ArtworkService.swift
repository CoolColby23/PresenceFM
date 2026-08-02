import AppKit
import CryptoKit
import Foundation

actor ArtworkService {
    private let memoryLimit: Int
    private let diskLimit: Int
    private let directory: URL
    private let clock: any AppClock
    private var memory: [String: Data] = [:]
    private var accessOrder: [String] = []
    private var catalogURLs: [String: URL] = [:]
    private var catalogMisses: Set<String> = []

    init(
        memoryLimit: Int = IntegrationPolicy.artworkMemoryEntries,
        diskLimit: Int = IntegrationPolicy.artworkDiskEntries,
        directory: URL? = nil,
        clock: any AppClock = SystemAppClock()
    ) {
        self.memoryLimit = max(1, memoryLimit)
        self.diskLimit = max(1, diskLimit)
        self.directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("PresenceFM-Artwork", isDirectory: true)
        self.clock = clock
    }

    func artwork(for track: TrackMetadata) async -> Data? {
        let key = cacheKey(for: track.identity)
        if let data = memory[key] {
            touch(key)
            return data
        }
        let url = directory.appendingPathComponent(key).appendingPathExtension("artwork")
        if let data = try? Data(contentsOf: url), Self.isImage(data) {
            insert(data, key: key)
            return data
        }
        if case .file(let sourceURL) = track.artworkReference,
           sourceURL.isFileURL, let data = try? Data(contentsOf: sourceURL), Self.isImage(data) {
            cache(data, for: track.identity)
            return data
        }
        var currentArtwork: Data?
        for attempt in 0..<4 {
            if let data = Self.readCurrentMusicArtwork(expectedPersistentID: track.identity.persistentID), Self.isImage(data) {
                currentArtwork = data
                break
            }
            if attempt < 3 { try? await clock.sleep(until: clock.now.addingTimeInterval(0.15)) }
        }
        guard let data = currentArtwork else { return nil }
        insert(data, key: key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        trimDisk()
        return data
    }

    func cachedArtwork(for identity: TrackIdentity) -> Data? {
        let key = cacheKey(for: identity)
        if let data = memory[key] { touch(key); return data }
        let url = directory.appendingPathComponent(key).appendingPathExtension("artwork")
        guard let data = try? Data(contentsOf: url), Self.isImage(data) else { return nil }
        insert(data, key: key)
        return data
    }

    @discardableResult
    func cache(_ data: Data, for identity: TrackIdentity) -> Bool {
        guard Self.isImage(data) else { return false }
        let key = cacheKey(for: identity)
        insert(data, key: key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key).appendingPathExtension("artwork"), options: .atomic)
        trimDisk()
        return true
    }

    var memoryEntryCount: Int { memory.count }

    var cacheMetrics: ArtworkCacheMetrics {
        let diskEntries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).count) ?? 0
        return ArtworkCacheMetrics(memoryEntries: memory.count, diskEntries: diskEntries)
    }

    /// Finds a public Apple-hosted cover URL suitable for Discord's external asset field.
    /// Local artwork bytes never leave the Mac.
    func publicArtworkURL(for track: TrackMetadata) async -> URL? {
        let key = cacheKey(for: track.identity)
        if let cached = catalogURLs[key] { return cached }
        if catalogMisses.contains(key) { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.title) \(track.artist) \(track.album ?? "")"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url else { catalogMisses.insert(key); return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = IntegrationPolicy.artworkTimeout
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let payload = try? JSONDecoder().decode(CatalogSearchResponse.self, from: data) else { return nil }
            let match = payload.results.max { matchScore($0, track: track) < matchScore($1, track: track) }
            guard let match, matchScore(match, track: track) >= 4,
                  let result = upgradedArtworkURL(match.artworkUrl100) else {
                catalogMisses.insert(key)
                return nil
            }
            catalogURLs[key] = result
            return result
        } catch { return nil }
    }

    func downloadedArtwork(from url: URL, for identity: TrackIdentity) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = IntegrationPolicy.artworkTimeout
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= IntegrationPolicy.artworkDownloadLimit, Self.isImage(data) else { return nil }
            return cache(data, for: identity) ? data : nil
        } catch {
            return nil
        }
    }

    private func insert(_ data: Data, key: String) {
        memory[key] = data
        touch(key)
        while accessOrder.count > memoryLimit, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            memory.removeValue(forKey: oldest)
        }
    }

    private func touch(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func cacheKey(for identity: TrackIdentity) -> String {
        SHA256.hash(data: Data(identity.persistentID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func trimDisk() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ), urls.count > diskLimit else { return }
        let sorted = urls.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs < rhs
        }
        for url in sorted.prefix(urls.count - diskLimit) { try? FileManager.default.removeItem(at: url) }
    }

    static func isImage(_ data: Data) -> Bool { NSImage(data: data) != nil }

    nonisolated private static func readCurrentMusicArtwork(expectedPersistentID: String) -> Data? {
        let script = """
        tell application "Music"
          if player state is stopped then return missing value
          try
            if (persistent ID of current track as text) is not "(expectedPersistentID.appleScriptEscaped)" then return missing value
            return data of artwork 1 of current track
          on error
            return missing value
          end try
        end tell
        """
        var error: NSDictionary?
        return NSAppleScript(source: script)?.executeAndReturnError(&error).data
    }
}

private extension String {
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct CatalogSearchResponse: Decodable {
    let results: [CatalogTrack]
}

private struct CatalogTrack: Decodable {
    let trackName: String
    let artistName: String
    let collectionName: String?
    let artworkUrl100: String
}

private func matchScore(_ candidate: CatalogTrack, track: TrackMetadata) -> Int {
    var score = 0
    if candidate.trackName.catalogNormalized == track.title.catalogNormalized { score += 3 }
    if candidate.artistName.catalogNormalized == track.artist.catalogNormalized { score += 3 }
    if let album = track.album, candidate.collectionName?.catalogNormalized == album.catalogNormalized { score += 2 }
    return score
}

private func upgradedArtworkURL(_ value: String) -> URL? {
    let upgraded = value.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    guard let url = URL(string: upgraded), url.scheme == "https" else { return nil }
    return url
}

private extension String {
    var catalogNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
    }
}
