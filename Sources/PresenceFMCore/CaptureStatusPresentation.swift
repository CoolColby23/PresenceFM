import Foundation

/// Platform-neutral copy and state for explaining scrobble capture to a person.
/// Operational models remain platform-specific; both apps translate their state
/// into this small presentation contract so equivalent situations read alike.
///
/// The wording and iconography live here rather than in either app's view layer.
/// When each app carried its own `switch`, the two drifted — the same recovery
/// action was labelled "Retry Queue" on iPhone and "Review Queue" on the Mac.
public struct CaptureStatusPresentation: Codable, Hashable, Sendable, Identifiable {
    /// How a status should read emotionally, so each app can map it onto its own
    /// palette without restating which statuses are good, busy, or alarming.
    public enum Tone: String, Codable, CaseIterable, Sendable {
        /// Finished successfully.
        case positive
        /// Working right now; nothing is required of the person.
        case active
        /// Deliberately held, or waiting on something that resolves by itself.
        case paused
        /// Not scrobbling by design, and not a failure.
        case neutral
        /// Stalled until the person does something.
        case critical
    }

    public enum Status: String, Codable, CaseIterable, Sendable {
        case detecting
        case progressing
        case queued
        case submitted
        case excluded
        case privateMode
        case needsAttention

        /// Short label for a status pill. Sentence case, never a full sentence.
        public var title: String {
            switch self {
            case .detecting: "Listening"
            case .progressing: "In progress"
            case .queued: "Queued"
            case .submitted: "Scrobbled"
            case .excluded: "Not eligible"
            case .privateMode: "Private Mode"
            case .needsAttention: "Needs attention"
            }
        }

        /// SF Symbol name. Available on both platforms at the deployment targets
        /// this package supports.
        public var symbol: String {
            switch self {
            case .detecting: "waveform.badge.magnifyingglass"
            case .progressing: "waveform"
            case .queued: "tray.full"
            case .submitted: "checkmark.circle.fill"
            case .excluded: "nosign"
            case .privateMode: "eye.slash.fill"
            case .needsAttention: "exclamationmark.triangle.fill"
            }
        }

        public var tone: Tone {
            switch self {
            case .submitted: .positive
            case .detecting, .progressing: .active
            case .queued, .privateMode: .paused
            case .excluded: .neutral
            case .needsAttention: .critical
            }
        }

        /// Whether this status means PresenceFM is waiting on the person rather
        /// than on playback, the network, or Last.fm.
        public var needsPersonAction: Bool { tone == .critical }
    }

    public enum RecoveryAction: String, Codable, CaseIterable, Sendable {
        case grantPlaybackPermission
        case reconnectLastFM
        case retryQueue
        case disablePrivateMode
        /// Re-scan recently played music now instead of waiting for the next
        /// scheduled reconciliation. Distinct from `openSettings`, which the
        /// iPhone app previously overloaded for this.
        case recheckNow
        case openSettings

        public var buttonTitle: String {
            switch self {
            case .grantPlaybackPermission: "Grant Permission"
            case .reconnectLastFM: "Reconnect Last.fm"
            case .retryQueue: "Review Queue"
            case .disablePrivateMode: "End Private Mode"
            case .recheckNow: "Check Again"
            case .openSettings: "Open Settings"
            }
        }
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

    /// Derived from content rather than stored, so recomputing an activity feed
    /// keeps each row's identity attached to the play it describes. Positional
    /// identity would re-target rows onto different plays as the feed shifts.
    public var id: String {
        let time = timestamp.map { String($0.timeIntervalSinceReferenceDate) } ?? "-"
        return "\(status.rawValue)|\(time)|\(headline)"
    }

    public var tone: Tone { status.tone }

    /// One spoken string for assistive technology, so a card built from several
    /// `Text` views does not have to be read out piecewise.
    ///
    /// Parts are joined with a single sentence separator. Explanations are
    /// written as full sentences and already end in a period, so joining
    /// naively would produce "eligible.. 25 percent", which VoiceOver reads
    /// with a stumble.
    public var accessibilitySummary: String {
        var parts = [status.title, headline, explanation]
        if let progress {
            parts.append("\(Int((progress * 100).rounded())) percent toward eligibility")
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { part in
                var trimmed = part
                while trimmed.hasSuffix(".") { trimmed.removeLast() }
                return trimmed.isEmpty ? part : trimmed
            }
            .joined(separator: ". ")
    }
}
