import Foundation

/// Platform-neutral copy and state for explaining scrobble capture to a person.
/// Operational models remain platform-specific; both apps translate their state
/// into this small presentation contract so equivalent situations read alike.
public struct CaptureStatusPresentation: Codable, Hashable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case detecting
        case progressing
        case queued
        case submitted
        case excluded
        case privateMode
        case needsAttention
    }

    public enum RecoveryAction: String, Codable, CaseIterable, Sendable {
        case grantPlaybackPermission
        case reconnectLastFM
        case retryQueue
        case disablePrivateMode
        case openSettings
    }

    public let status: Status
    public let headline: String
    public let explanation: String
    public let progress: Double?
    public let timestamp: Date?
    public let recoveryAction: RecoveryAction?

    public init(
        status: Status,
        headline: String,
        explanation: String,
        progress: Double? = nil,
        timestamp: Date? = nil,
        recoveryAction: RecoveryAction? = nil
    ) {
        self.status = status
        self.headline = headline
        self.explanation = explanation
        self.progress = progress.map { min(1, max(0, $0)) }
        self.timestamp = timestamp
        self.recoveryAction = recoveryAction
    }
}
