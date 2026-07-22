import Darwin
import Foundation

enum DiscordError: LocalizedError, Equatable {
    case missingApplicationID, unavailable, connectFailed, writeFailed
    var errorDescription: String? {
        switch self {
        case .missingApplicationID: "Enter a Discord application ID."
        case .unavailable: "Discord Desktop is not running."
        case .connectFailed: "Could not connect to Discord."
        case .writeFailed: "Discord disconnected while updating presence."
        }
    }
}

actor DiscordPresenceClient: PresencePublishing {
    private var applicationID: String
    private var socketFD: Int32 = -1
    private var lastPresence: DiscordPresence?
    private var lastPublishAt: Date?
    private(set) var socketPath: String?

    init(applicationID: String = ReleaseConfiguration.discordApplicationID) {
        self.applicationID = applicationID.isEmpty ? ReleaseConfiguration.discordApplicationID : applicationID
    }
    deinit { if socketFD >= 0 { Darwin.close(socketFD) } }

    func publish(_ presence: DiscordPresence) async throws {
        if presence == lastPresence, let lastPublishAt, Date().timeIntervalSince(lastPublishAt) < 15 { return }
        try await connectIfNeeded()
        let activity = Self.activityPayload(for: presence)
        try send(opcode: 1, payload: [
            "cmd": "SET_ACTIVITY", "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": activity],
            "nonce": UUID().uuidString
        ])
        lastPresence = presence
        lastPublishAt = .now
    }

    nonisolated static func activityPayload(for presence: DiscordPresence) -> [String: Any] {
        let largeImage = switch presence.largeImage {
        case .artwork: presence.artworkURL?.absoluteString ?? ReleaseConfiguration.discordApplicationIconURL
        case .playbackPlatform: presence.platform.discordSmallImageURL
        case .presenceFM: ReleaseConfiguration.discordApplicationIconURL
        }
        let details = bounded(presence.title, fallback: "Listening on \(presence.platform.rawValue)")
        let state = bounded(presence.state, fallback: presence.platform.rawValue)
        var assets = ["large_image": largeImage]
        let largeText = presence.largeImageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !largeText.isEmpty { assets["large_text"] = bounded(largeText, fallback: presence.platform.rawValue) }
        switch presence.smallImage {
        case .presenceFM:
            assets["small_image"] = ReleaseConfiguration.discordApplicationIconURL
            assets["small_text"] = bounded(presence.smallImageText, fallback: "Shared with PresenceFM")
        case .playbackPlatform:
            assets["small_image"] = presence.platform.discordSmallImageURL
            assets["small_text"] = bounded(presence.smallImageText, fallback: "Playing on \(presence.platform.rawValue)")
        case .none: break
        }
        var activity: [String: Any] = [
            "type": presence.activityType.payloadValue,
            "name": bounded(presence.activityName, fallback: "PresenceFM"),
            "details": details, "state": state,
            "assets": assets
        ]
        var timestamps: [String: Int] = [:]
        if let startedAt = presence.startedAt {
            timestamps["start"] = Int(startedAt.timeIntervalSince1970 * 1_000)
        }
        if let endsAt = presence.endsAt {
            if let startedAt = presence.startedAt {
                if endsAt > startedAt { timestamps["end"] = Int(endsAt.timeIntervalSince1970 * 1_000) }
            } else {
                timestamps["end"] = Int(endsAt.timeIntervalSince1970 * 1_000)
            }
        }
        if !timestamps.isEmpty {
            activity["timestamps"] = timestamps
        }
        if let url = presence.appleMusicURL {
            let label = presence.buttonLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            activity["buttons"] = [["label": String((label.isEmpty ? "Listen on \(presence.platform.rawValue)" : label).prefix(32)), "url": url.absoluteString]]
        }
        return activity
    }

    nonisolated private static func bounded(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(128))
    }

    func clear() async {
        guard socketFD >= 0 else { return }
        try? send(opcode: 1, payload: [
            "cmd": "SET_ACTIVITY", "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": NSNull()],
            "nonce": UUID().uuidString
        ])
        lastPresence = nil
        lastPublishAt = nil
    }

    func disconnect() {
        if socketFD >= 0 { Darwin.close(socketFD) }
        socketFD = -1
        socketPath = nil
        lastPresence = nil
        lastPublishAt = nil
    }

    func setApplicationID(_ value: String) {
        applicationID = value.isEmpty ? ReleaseConfiguration.discordApplicationID : value
        disconnect()
    }

    private func connectIfNeeded() async throws {
        guard socketFD < 0 else { return }
        guard !applicationID.isEmpty else {
            throw DiscordError.missingApplicationID
        }
        guard let path = candidatePaths().first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw DiscordError.unavailable
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DiscordError.connectFailed }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8CString.count <= pathCapacity else { Darwin.close(fd); throw DiscordError.connectFailed }
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            path.withCString { source in _ = Darwin.strncpy(destination, source, pathCapacity) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { Darwin.close(fd); throw DiscordError.connectFailed }
        socketFD = fd
        socketPath = path
        do { try send(opcode: 0, payload: ["v": 1, "client_id": applicationID]) }
        catch { disconnect(); throw error }
    }

    private func send(opcode: UInt32, payload: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: payload)
        var op = opcode.littleEndian
        var length = UInt32(body.count).littleEndian
        var frame = Data(bytes: &op, count: 4)
        frame.append(Data(bytes: &length, count: 4)); frame.append(body)
        var offset = 0
        while offset < frame.count {
            let written = frame.withUnsafeBytes { bytes in
                Darwin.write(socketFD, bytes.baseAddress!.advanced(by: offset), frame.count - offset)
            }
            guard written > 0 else { disconnect(); throw DiscordError.writeFailed }
            offset += written
        }
    }

    private func candidatePaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let roots = [environment["XDG_RUNTIME_DIR"], environment["TMPDIR"], environment["TMP"], environment["TEMP"], "/tmp"].compactMap { $0 }
        return roots.flatMap { root in (0...9).map { URL(fileURLWithPath: root).appendingPathComponent("discord-ipc-\($0)").path } }
    }
}
