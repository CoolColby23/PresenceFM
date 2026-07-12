import AppKit
import Foundation

actor PlaybackMonitor: PlaybackProviding {
    private var continuation: AsyncStream<PlaybackSnapshot>.Continuation?
    private var monitoringTask: Task<Void, Never>?

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

    private func poll() async {
        while !Task.isCancelled {
            let snapshot = Self.readMusic()
            continuation?.yield(snapshot)
            // Music does not expose a reliable public callback for every playback change.
            // Keep the fallback poll quick enough that track transitions feel immediate.
            let interval: Duration = snapshot.state == .playing ? .milliseconds(500) : .seconds(2)
            try? await Task.sleep(for: interval)
        }
    }

    nonisolated private static func readMusic() -> PlaybackSnapshot {
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
          return s & sep & (name of t as text) & sep & (artist of t as text) & sep & (album of t as text) & sep & (duration of t as text) & sep & (player position as text) & sep & (persistent ID of t as text) & sep & (class of t as text)
        end tell
        """
        var error: NSDictionary?
        guard let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else {
            return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .low)
        }
        if value == "stopped" { return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .high) }
        let fields = value.components(separatedBy: CharacterSet(charactersIn: String(UnicodeScalar(30)!)))
        guard fields.count >= 8, let duration = Double(fields[4]), let position = Double(fields[5]) else {
            return PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: now, confidence: .low)
        }
        let state: PlaybackState = fields[0] == "playing" ? .playing : .paused
        let kind = fields[7].lowercased()
        let trackSource: TrackSource = kind.contains("url") ? .unsupportedStream : (kind.contains("file") ? .localFile : .appleMusicCatalog)
        let searchTerms = "\(fields[1]) \(fields[2])"
        let searchQuery = searchTerms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let appleMusicURL = trackSource == .unsupportedStream ? nil : URL(string: "https://music.apple.com/us/search?term=\(searchQuery)")
        let track = TrackMetadata(
            identity: TrackIdentity(persistentID: fields[6]), title: fields[1], artist: fields[2],
            album: fields[3].isEmpty ? nil : fields[3], duration: duration, source: trackSource,
            appleMusicURL: appleMusicURL, artworkReference: nil
        )
        let hasUsableMetadata = duration > 0 && !fields[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !fields[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return PlaybackSnapshot(track: track, state: state, position: position, observedAt: now,
                                confidence: hasUsableMetadata ? .high : .low)
    }
}
