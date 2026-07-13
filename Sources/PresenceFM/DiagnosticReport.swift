import Foundation

enum DiagnosticReport {
    static func make(
        appVersion: String, osVersion: String, playbackPlatform: String,
        musicStatus: ServiceStatus, discordStatus: ServiceStatus, lastFMStatus: ServiceStatus,
        ytmDesktopStatus: ServiceStatus, records: [DiagnosticRecord]
    ) -> String {
        let header = [
            "PresenceFM diagnostics",
            "App: \(appVersion)",
            "macOS: \(osVersion)",
            "Playback platform: \(playbackPlatform)",
            "Playback: \(musicStatus.label)",
            "Discord: \(discordStatus.label)",
            "Last.fm: \(lastFMStatus.label)",
            "YTMDesktop: \(ytmDesktopStatus.label)",
            "",
            "Recent redacted log:"
        ]
        let formatter = ISO8601DateFormatter()
        let log = records.prefix(50).map {
            "[\(formatter.string(from: $0.timestamp))] [\($0.category)] \(Redactor.redact($0.message))"
        }
        return (header + log).joined(separator: "\n")
    }
}
