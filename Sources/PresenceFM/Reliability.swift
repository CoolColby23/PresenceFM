import Foundation

protocol AppClock: Sendable {
    var now: Date { get }
    func sleep(until deadline: Date) async throws
}

struct SystemAppClock: AppClock {
    var now: Date { Date() }

    func sleep(until deadline: Date) async throws {
        try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
    }
}

struct ClosureAppClock: AppClock {
    private let nowProvider: @Sendable () -> Date
    private let sleeper: @Sendable (Date) async throws -> Void

    init(
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Date) async throws -> Void = { deadline in
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
        }
    ) {
        nowProvider = now
        sleeper = sleep
    }

    var now: Date { nowProvider() }
    func sleep(until deadline: Date) async throws { try await sleeper(deadline) }
}

enum IntegrationPolicy {
    static let playingPollInterval: TimeInterval = 0.5
    static let idlePollInterval: TimeInterval = 2
    static let youtubePollInterval: TimeInterval = 5
    static let scrobbleWorkerInterval: TimeInterval = 30
    static let scrobbleRetryMaximum: TimeInterval = 3_600
    static let lastFMTimeout: TimeInterval = 20
    static let artworkTimeout: TimeInterval = 8
    static let artworkDownloadLimit = 12_000_000
    static let artworkMemoryEntries = 12
    static let artworkDiskEntries = 40
    static let activityRecordLimit = 5_000
    static let diagnosticRecordLimit = 1_000
    static let healthEventLimit = 200
    static let permanentQueueWarning = 400
    static let permanentQueueLimit = 500
    static let pendingQueueWarning = 4_000
    static let pendingQueueLimit = 5_000
}

enum PlaybackProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleMusic, spotify, youtubeMusic, tidal
    var id: Self { self }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtubeMusic: "YouTube Music"
        case .tidal: "TIDAL"
        }
    }
}

enum ProviderHealth: Sendable, Equatable {
    case available
    case inactive
    case permissionRequired
    case unavailable(String)
}

struct ProviderSnapshot: Sendable {
    let provider: PlaybackProviderID
    let playback: PlaybackSnapshot?
    let health: ProviderHealth
    let observedAt: Date
}

protocol PlaybackProvider: Sendable {
    var id: PlaybackProviderID { get }
    func snapshot() async -> ProviderSnapshot
}

actor PlaybackCoordinator {
    private var activeProvider: PlaybackProviderID?

    func select(_ snapshots: [ProviderSnapshot], now: Date = .now) -> PlaybackSnapshot {
        let byProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        let ordered = PlaybackProviderID.allCases.compactMap { byProvider[$0] }

        if let activeProvider,
           let active = byProvider[activeProvider]?.playback,
           active.state == .playing {
            return active
        }
        if let selected = ordered.compactMap(\.playback).first(where: { $0.state == .playing }) {
            activeProvider = providerID(for: selected)
            return selected
        }
        if let activeProvider,
           let active = byProvider[activeProvider]?.playback,
           active.state == .paused {
            return active
        }
        if let selected = ordered.compactMap(\.playback).first(where: { $0.state == .paused }) {
            activeProvider = providerID(for: selected)
            return selected
        }

        activeProvider = nil
        let permissionBlocked = ordered.contains { $0.health == .permissionRequired }
        return PlaybackSnapshot(
            track: nil, state: .stopped, position: 0, observedAt: now,
            confidence: permissionBlocked ? .low : .high
        )
    }

    private func providerID(for snapshot: PlaybackSnapshot) -> PlaybackProviderID? {
        guard let platform = snapshot.track?.platform else { return nil }
        switch platform {
        case .appleMusic: return .appleMusic
        case .spotify: return .spotify
        case .youtubeMusic: return .youtubeMusic
        case .tidal: return .tidal
        }
    }
}

enum IntegrationID: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleMusic, spotify, youtubeMusic, tidal, discord, lastFM
    var id: Self { self }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtubeMusic: "YouTube Music"
        case .tidal: "TIDAL"
        case .discord: "Discord"
        case .lastFM: "Last.fm"
        }
    }
}

enum IntegrationState: String, Codable, Sendable {
    case disabled, connecting, connected, offline, permissionRequired, authorizationExpired, failed
}

enum RecoveryAction: String, Codable, Sendable {
    case openAutomationSettings, reconnectDiscord, reconnectLastFM, reconnectYouTubeMusic
}

struct IntegrationHealth: Sendable, Identifiable {
    let integration: IntegrationID
    let state: IntegrationState
    let summary: String
    let lastSuccessfulAt: Date?
    let recoveryAction: RecoveryAction?
    var id: IntegrationID { integration }
}
