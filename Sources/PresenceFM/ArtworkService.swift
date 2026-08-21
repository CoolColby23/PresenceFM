import AppKit
import CryptoKit
import Foundation

enum ArtworkSource: String, Sendable, Equatable {
    case memoryCache, diskCache, playerURL, localFile, embedded, appleMusic, appleCatalog, generatedPlaceholder

    var label: String {
        switch self {
        case .memoryCache: "Memory cache"
        case .diskCache: "Disk cache"
        case .playerURL: "Playback app"
        case .localFile: "Local file"
        case .embedded: "Embedded artwork"
        case .appleMusic: "Apple Music"
        case .appleCatalog: "Apple catalog"
        case .generatedPlaceholder: "Designed placeholder"
        }
    }
}

struct ArtworkLoadResult: Sendable, Equatable {
    let data: Data
    let source: ArtworkSource
}

enum ArtworkLoadState: Sendable, Equatable {
    case idle, loading, available(ArtworkSource), unavailable
}

actor ArtworkService {
    private let memoryLimit: Int
    private let diskLimit: Int
    private let directory: URL
    private let clock: any AppClock
    private var memory: [String: Data] = [:]
    private var accessOrder: [String] = []
    private var catalogURLs: [String: URL] = [:]
    private var catalogMisses: [String: Date] = [:]
    private let catalogMissRetryInterval: TimeInterval = 5 * 60

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
        await artworkResult(for: track)?.data
    }

    func artworkResult(for track: TrackMetadata) async -> ArtworkLoadResult? {
        let key = cacheKey(for: track.identity)
        if let data = memory[key] {
            touch(key)
            return ArtworkLoadResult(data: data, source: .memoryCache)
        }
        let url = directory.appendingPathComponent(key).appendingPathExtension("artwork")
        if let data = try? Data(contentsOf: url), let cleaned = Self.extractImageBytes(data) {
            insert(cleaned, key: key)
            return ArtworkLoadResult(data: cleaned, source: .diskCache)
        }
        switch track.artworkReference {
        case .file(let sourceURL) where sourceURL.isFileURL:
            if let data = try? Data(contentsOf: sourceURL), let cleaned = Self.extractImageBytes(data) {
                cache(cleaned, for: track.identity)
                return ArtworkLoadResult(data: cleaned, source: .localFile)
            }
        case .remote(let sourceURL):
            if let downloaded = await downloadedArtwork(from: sourceURL, for: track.identity) {
                return ArtworkLoadResult(data: downloaded, source: .playerURL)
            }
        case .embedded(let data):
            if let cleaned = Self.extractImageBytes(data) {
                cache(cleaned, for: track.identity)
                return ArtworkLoadResult(data: cleaned, source: .embedded)
            }
        case nil, .file:
            break
        }
        var currentArtwork: Data?
        if track.platform == .appleMusic {
            for attempt in 0..<4 {
                if let data = Self.readCurrentMusicArtwork(expectedPersistentID: track.identity.persistentID), let cleaned = Self.extractImageBytes(data) {
                    currentArtwork = cleaned
                    break
                }
                if attempt < 3 { try? await clock.sleep(until: clock.now.addingTimeInterval(0.15)) }
            }
        }
        if let data = currentArtwork {
            insert(data, key: key)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            trimDisk()
            return ArtworkLoadResult(data: data, source: .appleMusic)
        }

        // Automatic fallback: fetch catalog artwork URL and download
        if let publicURL = await publicArtworkURL(for: track),
           let downloaded = await downloadedArtwork(from: publicURL, for: track.identity) {
            let source: ArtworkSource = Self.directPublicArtworkURL(for: track) == publicURL ? .playerURL : .appleCatalog
            return ArtworkLoadResult(data: downloaded, source: source)
        }
        return nil
    }

    func cachedArtwork(for identity: TrackIdentity) -> Data? {
        let key = cacheKey(for: identity)
        if let data = memory[key] { touch(key); return data }
        let url = directory.appendingPathComponent(key).appendingPathExtension("artwork")
        guard let data = try? Data(contentsOf: url), let cleaned = Self.extractImageBytes(data) else { return nil }
        insert(cleaned, key: key)
        return cleaned
    }

    @discardableResult
    func cache(_ data: Data, for identity: TrackIdentity) -> Bool {
        guard let cleaned = Self.extractImageBytes(data) else { return false }
        let key = cacheKey(for: identity)
        insert(cleaned, key: key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? cleaned.write(to: directory.appendingPathComponent(key).appendingPathExtension("artwork"), options: .atomic)
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

    /// Finds a public cover URL suitable for Discord's external asset field.
    /// Local artwork bytes never leave the Mac.
    func publicArtworkURL(for track: TrackMetadata) async -> URL? {
        let key = cacheKey(for: track.identity)
        if let directURL = Self.directPublicArtworkURL(for: track) {
            catalogURLs[key] = directURL
            return directURL
        }
        if let cached = catalogURLs[key] { return cached }
        if let missedAt = catalogMisses[key],
           clock.now.timeIntervalSince(missedAt) < catalogMissRetryInterval {
            return nil
        }
        catalogMisses.removeValue(forKey: key)

        let queries = catalogSearchTerms(for: track)
        for term in queries {
            if let result = await catalogArtworkURL(term: term, track: track) {
                catalogURLs[key] = result
                return result
            }
        }
        catalogMisses[key] = clock.now
        return nil
    }

    /// Player-provided HTTPS artwork is tied to the exact playing item and is
    /// therefore more trustworthy than a title/artist catalog search.
    nonisolated static func directPublicArtworkURL(for track: TrackMetadata?) -> URL? {
        guard case .remote(let url)? = track?.artworkReference else { return nil }
        return DiscordMediaURL.normalizedHTTPSArtworkURL(url)
    }

    private func catalogSearchTerms(for track: TrackMetadata) -> [String] {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var terms: [String] = []
        if !album.isEmpty { terms.append("\(title) \(artist) \(album)") }
        terms.append("\(title) \(artist)")
        if title.contains("(") || title.contains("[") {
            let stripped = title
                .replacingOccurrences(of: #"[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.count >= 2 { terms.append("\(stripped) \(artist)") }
        }
        var seen = Set<String>()
        return terms.filter { seen.insert($0.lowercased()).inserted && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func catalogArtworkURL(term: String, track: TrackMetadata) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = components.url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = IntegrationPolicy.artworkTimeout
            request.setValue("PresenceFM/1", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let payload = try? JSONDecoder().decode(CatalogSearchResponse.self, from: data),
                  !payload.results.isEmpty else { return nil }
            let ranked = payload.results.sorted {
                ArtworkCatalogMatcher.score($0, track: track) > ArtworkCatalogMatcher.score($1, track: track)
            }
            // Prefer the exact release, but do not discard an exact song and
            // artist merely because Music reports a single/EP album while the
            // catalog has since folded the song into a full album.
            let match = ranked.first { ArtworkCatalogMatcher.isReliable($0, track: track) }
                ?? ranked.first { ArtworkCatalogMatcher.isTrackAndArtistMatch($0, track: track) }
            guard let match,
                  let result = upgradedArtworkURL(match.artworkUrl100) else { return nil }
            return result
        } catch {
            return nil
        }
    }

    func invalidatePublicArtworkLookup(for identity: TrackIdentity) {
        let key = cacheKey(for: identity)
        catalogURLs.removeValue(forKey: key)
        catalogMisses.removeValue(forKey: key)
    }

    func invalidateArtwork(for identity: TrackIdentity) {
        let key = cacheKey(for: identity)
        memory.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(key).appendingPathExtension("artwork")
        )
        catalogURLs.removeValue(forKey: key)
        catalogMisses.removeValue(forKey: key)
    }

    func downloadedArtwork(from url: URL, for identity: TrackIdentity) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = IntegrationPolicy.artworkTimeout
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= IntegrationPolicy.artworkDownloadLimit, let cleaned = Self.extractImageBytes(data) else { return nil }
            return cache(cleaned, for: identity) ? cleaned : nil
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
        // Versioning prevents artwork selected by older, looser matching rules
        // from poisoning the corrected cache after an app update.
        SHA256.hash(data: Data("v2|\(identity.persistentID)".utf8)).map { String(format: "%02x", $0) }.joined()
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

    static func isImage(_ data: Data) -> Bool { extractImageBytes(data) != nil }

    static func extractImageBytes(_ data: Data) -> Data? {
        if NSImage(data: data) != nil { return data }
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47])
        if let range = data.range(of: pngHeader) {
            let candidate = data.subdata(in: range.lowerBound..<data.count)
            if NSImage(data: candidate) != nil { return candidate }
        }
        let jpegHeader = Data([0xFF, 0xD8, 0xFF])
        if let range = data.range(of: jpegHeader) {
            let candidate = data.subdata(in: range.lowerBound..<data.count)
            if NSImage(data: candidate) != nil { return candidate }
        }
        return nil
    }

    nonisolated private static func readCurrentMusicArtwork(expectedPersistentID: String) -> Data? {
        let script = """
        tell application "Music"
          if player state is stopped then return missing value
          try
            if (persistent ID of current track as text) is not "\(expectedPersistentID.appleScriptEscaped)" then return missing value
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

struct CatalogTrack: Decodable {
    let trackName: String
    let artistName: String
    let collectionName: String?
    let artworkUrl100: String
}

enum ArtworkCatalogMatcher {
    static func score(_ candidate: CatalogTrack, track: TrackMetadata) -> Int {
        var score = 0
        if normalizedFieldsMatch(candidate.trackName, track.title) { score += 4 }
        if normalizedFieldsMatch(candidate.artistName, track.artist) { score += 4 }
        if let album = track.album, let candidateAlbum = candidate.collectionName,
           normalizedFieldsMatch(candidateAlbum, album) { score += 2 }
        return score
    }

    static func isReliable(_ candidate: CatalogTrack, track: TrackMetadata) -> Bool {
        guard isTrackAndArtistMatch(candidate, track: track) else { return false }
        if let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines),
           !album.isEmpty,
           let candidateAlbum = candidate.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidateAlbum.isEmpty {
            // Missing artwork is preferable to publishing the cover from a
            // different release with the same song and artist.
            return normalizedAlbumMatch(candidateAlbum, album)
        }
        return true
    }

    static func isTrackAndArtistMatch(_ candidate: CatalogTrack, track: TrackMetadata) -> Bool {
        normalizedFieldsMatch(candidate.trackName, track.title)
            && normalizedFieldsMatch(candidate.artistName, track.artist)
    }

    private static func normalizedFieldsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = lhs.catalogNormalized
        let rhs = rhs.catalogNormalized
        guard lhs.count >= 2, rhs.count >= 2 else { return lhs == rhs }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    private static func normalizedAlbumMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = lhs.catalogNormalized
        let rhs = rhs.catalogNormalized
        guard lhs != rhs else { return true }
        let editionTerms = ["deluxe", "edition", "expanded", "remaster", "anniversary", "bonus", "special"]
        func isDecoratedVersion(_ longer: String, of shorter: String) -> Bool {
            guard longer.hasPrefix(shorter) else { return false }
            let suffix = String(longer.dropFirst(shorter.count))
            return editionTerms.contains { suffix.contains($0) }
        }
        return isDecoratedVersion(lhs, of: rhs) || isDecoratedVersion(rhs, of: lhs)
    }
}

private func upgradedArtworkURL(_ value: String) -> URL? {
    var upgraded = value
    let replacements = [
        "100x100bb": "600x600bb",
        "60x60bb": "600x600bb",
        "30x30bb": "600x600bb",
        "100x100bf": "600x600bb",
        "60x60bf": "600x600bb"
    ]
    for (from, to) in replacements where upgraded.contains(from) {
        upgraded = upgraded.replacingOccurrences(of: from, with: to)
        break
    }
    if upgraded.hasPrefix("http://") {
        upgraded = "https://" + upgraded.dropFirst("http://".count)
    }
    guard let url = URL(string: upgraded), url.scheme?.lowercased() == "https" else { return nil }
    return url
}

enum DiscordMediaURL {
    /// Discord accepts public image URLs directly. Keeping the provider URL
    /// avoids an extra proxy failure point and preserves signed CDN queries.
    static func externalImage(_ url: URL?, fallback: String) -> String {
        guard let url, let normalized = normalizedHTTPSArtworkURL(url) else { return fallback }
        return normalized.absoluteString
    }

    static func normalizedHTTPSArtworkURL(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.scheme?.lowercased() == "http" {
            components?.scheme = "https"
        }
        guard let normalized = components?.url ?? url as URL?,
              normalized.scheme?.lowercased() == "https" else { return nil }
        guard normalized.absoluteString.count <= 2_048 else { return nil }
        return normalized
    }
}

private extension String {
    var catalogNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
    }
}
