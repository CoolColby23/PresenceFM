import Foundation
import Testing

@testable import PresenceFMCore

struct PresenceFMCoreTests {
    let deviceID = UUID()

    @Test func eligibilityRejectsPreBaselineAndForwardProgressMustBeObserved() {
        let baseline = CaptureBaseline(establishedAt: Date(timeIntervalSince1970: 1_000))
        let old = evidence(start: Date(timeIntervalSince1970: 900), played: 200)
        #expect(ScrobbleEligibilityPolicy.evaluate(old, baseline: baseline) == .review(.beforeBaseline))
        let eligible = evidence(start: Date(timeIntervalSince1970: 1_100), played: 121)
        #expect(ScrobbleEligibilityPolicy.evaluate(eligible, baseline: baseline) == .eligible)
    }

    @Test func reconciledHistoryRequiresExplicitImportSelection() {
        let played = Date(timeIntervalSince1970: 900)
        let historical = PlaybackEvidence(
            deviceID: deviceID,
            sourceTrackID: "historical-song",
            metadata: .init(title: "Past Track", artist: "Artist", duration: 240, startedAt: played),
            observedPlayTime: nil,
            origin: .reconciled,
            confidence: .probable,
            capturedAt: Date(timeIntervalSince1970: 1_100)
        )

        #expect(ScrobbleEligibilityPolicy.evaluate(
            historical,
            baseline: CaptureBaseline(establishedAt: Date(timeIntervalSince1970: 1_000))
        ) == .review(.historicalImport))
    }

    @Test func repeatedTracksOutsideWindowRemainSeparate() {
        let first = evidence(start: Date(timeIntervalSince1970: 2_000), played: 120)
        let listen = CanonicalListen(id: CanonicalListenIdentity.make(for: first), evidence: [first], metadata: first.originalMetadata, state: .queued)
        let replay = evidence(start: Date(timeIntervalSince1970: 2_500), played: 120)
        if case .newListen = DefaultEvidenceMerger().merge(replay, into: [listen]) {} else { Issue.record("Replay was incorrectly merged") }
    }

    @Test func lastFMSignatureIsStable() {
        let signature = LastFMRequestBuilder.signature(parameters: ["method": "track.scrobble", "api_key": "key"], secret: "secret")
        #expect(signature.count == 32)
        #expect(signature == LastFMRequestBuilder.signature(parameters: ["api_key": "key", "method": "track.scrobble"], secret: "secret"))
    }

    @Test func capturePresentationClampsProgressAndPreservesRecovery() throws {
        let presentation = CaptureStatusPresentation(
            status: .needsAttention,
            headline: "Reconnect Last.fm",
            explanation: "Scrobbles will wait until the account is connected.",
            progress: 1.5,
            timestamp: Date(timeIntervalSince1970: 1_000),
            recoveryAction: .reconnectLastFM
        )

        #expect(presentation.progress == 1)
        #expect(presentation.recoveryAction == .reconnectLastFM)
        #expect(try JSONDecoder().decode(
            CaptureStatusPresentation.self,
            from: JSONEncoder().encode(presentation)
        ) == presentation)
    }

    private func evidence(start: Date, played: TimeInterval) -> PlaybackEvidence {
        PlaybackEvidence(
            deviceID: deviceID, sourceTrackID: "song-1", metadata: .init(title: "Track", artist: "Artist", album: "Album", duration: 240, startedAt: start),
            observedPlayTime: played, origin: .observed, confidence: .strong, capturedAt: start)
    }
}
