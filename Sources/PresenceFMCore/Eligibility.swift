import Foundation

public enum EligibilityDecision: Equatable, Sendable {
    case ineligible(String)
    case listening(progress: Double, remaining: TimeInterval)
    case eligible
    case review(ReviewReason)
}

public enum ScrobbleEligibilityPolicy {
    public static func evaluate(_ evidence: PlaybackEvidence, baseline: CaptureBaseline) -> EligibilityDecision {
        let metadata = evidence.originalMetadata
        guard !metadata.title.trimmed.isEmpty, !metadata.artist.trimmed.isEmpty else {
            return .ineligible("Title and artist are required.")
        }
        guard let startedAt = metadata.startedAt else { return .review(.missingTimestamp) }
        if let duration = metadata.duration, duration <= 30 {
            return .ineligible("Tracks must be longer than 30 seconds.")
        }
        // MusicKit exposes a last-played timestamp for historical items but not
        // enough evidence to prove Last.fm's listening threshold. Present these
        // to the user for explicit selection instead of silently submitting or
        // rejecting them against the live-capture baseline.
        if evidence.origin == .reconciled { return .review(.historicalImport) }
        guard startedAt >= baseline.establishedAt || evidence.origin == .manual else { return .review(.beforeBaseline) }
        guard let duration = metadata.duration else { return .review(.missingDuration) }
        let threshold = min(duration * 0.5, 240)
        guard let played = evidence.observedPlayTime else {
            return evidence.origin == .observed ? .review(.insufficientPlayTime) : .review(.insufficientPlayTime)
        }
        guard played < threshold else { return .eligible }
        return .listening(progress: max(0, min(1, played / threshold)), remaining: max(0, threshold - played))
    }
}

extension String {
    public var presenceNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
