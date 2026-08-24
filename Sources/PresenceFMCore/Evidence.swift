import Foundation

public enum CaptureOrigin: String, Codable, Sendable, CaseIterable {
    case observed, reconciled, manual, externalLastFM
}

public enum CaptureConfidence: String, Codable, Sendable, CaseIterable {
    case strong, probable, uncertain

    public var rank: Int {
        switch self {
        case .strong: 3;
        case .probable: 2;
        case .uncertain: 1
        }
    }
}

public enum CompanionPlatform: String, Codable, Sendable { case appleMusic, localMusic }
public enum ListenState: String, Codable, Sendable { case listening, review, queued, submitting, submitted, failed, dismissed, privateListen }

public enum ReviewReason: String, Codable, Sendable {
    case missingTimestamp, missingDuration, insufficientPlayTime, ambiguousDuplicate, conflictingMetadata, beforeBaseline
    case historicalImport
    /// A reason written by a build newer than this one.
    case unrecognized

    /// Synthesized decoding throws on an unknown raw value, and `CompanionStore`
    /// treats any decode failure as an empty ledger. A reason this build has not
    /// heard of must therefore degrade to `unrecognized` rather than discard the
    /// person's entire listen history.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReviewReason(rawValue: raw) ?? .unrecognized
    }
}

public struct ScrobbleMetadata: Codable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String?
    public var duration: TimeInterval?
    public var startedAt: Date?

    public init(title: String, artist: String, album: String? = nil, duration: TimeInterval? = nil, startedAt: Date? = nil) {
        self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.startedAt = startedAt
    }
}

public struct PlaybackEvidence: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let deviceID: UUID
    public let platform: CompanionPlatform
    public let sourceTrackID: String?
    public let originalMetadata: ScrobbleMetadata
    public var observedPlayTime: TimeInterval?
    public let origin: CaptureOrigin
    public let confidence: CaptureConfidence
    public let capturedAt: Date

    public init(
        id: UUID = UUID(), deviceID: UUID, platform: CompanionPlatform = .appleMusic,
        sourceTrackID: String?, metadata: ScrobbleMetadata, observedPlayTime: TimeInterval?,
        origin: CaptureOrigin, confidence: CaptureConfidence, capturedAt: Date = .now
    ) {
        self.id = id; self.deviceID = deviceID; self.platform = platform
        self.sourceTrackID = sourceTrackID; originalMetadata = metadata
        self.observedPlayTime = observedPlayTime; self.origin = origin
        self.confidence = confidence; self.capturedAt = capturedAt
    }
}

public struct CanonicalListen: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var evidence: [PlaybackEvidence]
    public var canonicalMetadata: ScrobbleMetadata
    public var state: ListenState
    public var reviewReason: ReviewReason?
    public var submittedAt: Date?
    /// Why Last.fm refused this listen for good. Present only when the refusal
    /// cannot succeed on a retry, so the UI can stop promising one. Optional and
    /// additive, so older and newer ledgers decode each other.
    public var failureReason: String?

    public init(id: String, evidence: [PlaybackEvidence], metadata: ScrobbleMetadata, state: ListenState, reviewReason: ReviewReason? = nil) {
        self.id = id; self.evidence = evidence; canonicalMetadata = metadata
        self.state = state; self.reviewReason = reviewReason
    }
}

public struct CaptureBaseline: Codable, Hashable, Sendable {
    public let establishedAt: Date; public init(establishedAt: Date = .now) { self.establishedAt = establishedAt }
}
public struct ReconciliationCursor: Codable, Hashable, Sendable {
    public var lastCheckedAt: Date; public init(lastCheckedAt: Date) { self.lastCheckedAt = lastCheckedAt }
}
public struct ReconciliationResult: Sendable {
    public let evidence: [PlaybackEvidence]; public let cursor: ReconciliationCursor;
    public init(evidence: [PlaybackEvidence], cursor: ReconciliationCursor) { self.evidence = evidence; self.cursor = cursor }
}

public protocol PlaybackEvidenceSource: Sendable {
    func establishBaseline() async throws -> CaptureBaseline
    func currentEvidence() async -> PlaybackEvidence?
    func reconcile(since cursor: ReconciliationCursor) async throws -> ReconciliationResult
}
