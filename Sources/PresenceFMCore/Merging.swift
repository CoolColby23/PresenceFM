import CryptoKit
import Foundation

public enum MergeDecision: Sendable, Equatable {
    case newListen(String)
    case merge(String)
    case review(String?, ReviewReason)
}

public protocol EvidenceMerger: Sendable {
    func merge(_ evidence: PlaybackEvidence, into candidates: [CanonicalListen]) -> MergeDecision
}

public struct DefaultEvidenceMerger: EvidenceMerger {
    public init() {}

    public func merge(_ evidence: PlaybackEvidence, into candidates: [CanonicalListen]) -> MergeDecision {
        let identity = CanonicalListenIdentity.make(for: evidence)
        if let exact = candidates.first(where: { candidate in
            candidate.evidence.contains { prior in
                guard let lhs = prior.sourceTrackID, let rhs = evidence.sourceTrackID else { return false }
                return lhs == rhs && close(prior.originalMetadata.startedAt, evidence.originalMetadata.startedAt)
            }
        }) {
            return .merge(exact.id)
        }

        let metadataMatches = candidates.filter {
            $0.canonicalMetadata.title.presenceNormalized == evidence.originalMetadata.title.presenceNormalized
                && $0.canonicalMetadata.artist.presenceNormalized == evidence.originalMetadata.artist.presenceNormalized
                && close($0.canonicalMetadata.startedAt, evidence.originalMetadata.startedAt)
        }
        if metadataMatches.count == 1 { return .merge(metadataMatches[0].id) }
        if metadataMatches.count > 1 { return .review(nil, .ambiguousDuplicate) }
        return .newListen(identity)
    }

    private func close(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) <= 90
    }
}

public enum CanonicalListenIdentity {
    public static func make(for evidence: PlaybackEvidence) -> String {
        let metadata = evidence.originalMetadata
        let bucket = Int((metadata.startedAt ?? evidence.capturedAt).timeIntervalSince1970 / 120)
        let source = evidence.sourceTrackID ?? "\(metadata.artist.presenceNormalized)|\(metadata.title.presenceNormalized)"
        let digest = SHA256.hash(data: Data("\(source)|\(bucket)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

public enum EvidenceReducer {
    public static func add(_ evidence: PlaybackEvidence, to listen: CanonicalListen) -> CanonicalListen {
        var result = listen
        guard !result.evidence.contains(where: { $0.id == evidence.id }) else { return result }
        result.evidence.append(evidence)
        let strongest = result.evidence.max {
            if $0.confidence.rank != $1.confidence.rank { return $0.confidence.rank < $1.confidence.rank }
            return ($0.observedPlayTime ?? 0) < ($1.observedPlayTime ?? 0)
        }
        if let strongest { result.canonicalMetadata = strongest.originalMetadata }
        return result
    }
}
