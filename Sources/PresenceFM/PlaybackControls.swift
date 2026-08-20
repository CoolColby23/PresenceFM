import AppKit
import Foundation

enum PlaybackControlCommand: String, Sendable, CaseIterable {
    case previous
    case toggle
    case next

    var symbol: String {
        switch self {
        case .previous: "backward.fill"
        case .toggle: "playpause.fill"
        case .next: "forward.fill"
        }
    }
}

enum SystemPlaybackController {
    static func supports(_ platform: PlaybackPlatform?) -> Bool {
        platform == .appleMusic || platform == .spotify
    }

    @discardableResult
    static func perform(_ command: PlaybackControlCommand, platform: PlaybackPlatform) -> Bool {
        guard supports(platform) else { return false }
        let application = platform == .spotify ? "Spotify" : "Music"
        let action = switch command {
        case .previous: "previous track"
        case .toggle: "playpause"
        case .next: "next track"
        }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(application)\" to \(action)")?
            .executeAndReturnError(&error)
        return error == nil
    }

    @discardableResult
    static func seek(to position: TimeInterval, platform: PlaybackPlatform) -> Bool {
        guard supports(platform) else { return false }
        return run("set player position to \(max(0, position))", platform: platform)
    }

    @discardableResult
    static func adjustVolume(by amount: Int, platform: PlaybackPlatform) -> Bool {
        guard supports(platform) else { return false }
        let script = "set sound volume to (sound volume + (\(amount)))"
        return run(script, platform: platform)
    }

    private static func run(_ action: String, platform: PlaybackPlatform) -> Bool {
        let application = platform == .spotify ? "Spotify" : "Music"
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(application)\" to \(action)")?
            .executeAndReturnError(&error)
        return error == nil
    }
}
