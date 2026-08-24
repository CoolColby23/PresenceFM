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

    @Test func everyCaptureStatusAndRecoveryActionHasPresentableCopy() {
        for status in CaptureStatusPresentation.Status.allCases {
            #expect(!status.title.isEmpty, "\(status) has no pill title")
            #expect(!status.symbol.isEmpty, "\(status) has no symbol")
            // A title that reads as a sentence does not fit a status pill.
            #expect(!status.title.hasSuffix("."), "\(status) title reads as a sentence")
            #expect(status.needsPersonAction == (status.tone == .critical))
        }
        for action in CaptureStatusPresentation.RecoveryAction.allCases {
            #expect(!action.buttonTitle.isEmpty, "\(action) has no button title")
        }
        // Distinct statuses must stay visually distinguishable by symbol.
        let symbols = Set(CaptureStatusPresentation.Status.allCases.map(\.symbol))
        #expect(symbols.count == CaptureStatusPresentation.Status.allCases.count)
    }

    @Test func everyCaptureStatusSurvivesACodingRoundTrip() throws {
        for status in CaptureStatusPresentation.Status.allCases {
            for action in CaptureStatusPresentation.RecoveryAction.allCases {
                let presentation = CaptureStatusPresentation(
                    status: status,
                    headline: status.title,
                    explanation: "Explanation for \(status).",
                    progress: 0.5,
                    timestamp: Date(timeIntervalSince1970: 1_000),
                    recoveryAction: action
                )
                let decoded = try JSONDecoder().decode(
                    CaptureStatusPresentation.self,
                    from: JSONEncoder().encode(presentation)
                )
                #expect(decoded == presentation)
                #expect(decoded.id == presentation.id)
            }
        }
    }

    @Test func captureIdentityTracksThePlayRatherThanThePosition() {
        let first = CaptureStatusPresentation(
            status: .submitted,
            headline: "Midnight Signal",
            explanation: "Submitted to Last.fm",
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let recomputed = CaptureStatusPresentation(
            status: .submitted,
            headline: "Midnight Signal",
            explanation: "Submitted to Last.fm",
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let laterPlay = CaptureStatusPresentation(
            status: .submitted,
            headline: "Midnight Signal",
            explanation: "Submitted to Last.fm",
            timestamp: Date(timeIntervalSince1970: 2_000)
        )
        let differentTrack = CaptureStatusPresentation(
            status: .submitted,
            headline: "Afterglow",
            explanation: "Submitted to Last.fm",
            timestamp: Date(timeIntervalSince1970: 1_000)
        )

        #expect(first.id == recomputed.id)
        #expect(first.id != laterPlay.id)
        #expect(first.id != differentTrack.id)
    }

    @Test func accessibilitySummaryReadsAsOneStatement() {
        let progressing = CaptureStatusPresentation(
            status: .progressing,
            headline: "Listening toward a scrobble",
            explanation: "Keep playing for 1:20 to make this track eligible.",
            progress: 0.25
        )
        // One separator between sentences: the explanation already ends in a
        // period, and doubling it makes VoiceOver stumble.
        #expect(progressing.accessibilitySummary == """
            In progress. Listening toward a scrobble. Keep playing for 1:20 to \
            make this track eligible. 25 percent toward eligibility
            """)
        #expect(!progressing.accessibilitySummary.contains(".."))

        let withoutProgress = CaptureStatusPresentation(
            status: .submitted,
            headline: "Scrobbled to Last.fm",
            explanation: "This play was accepted by Last.fm."
        )
        #expect(!withoutProgress.accessibilitySummary.contains("percent"))
        #expect(withoutProgress.accessibilitySummary.hasSuffix("accepted by Last.fm"))

        // No status is left without copy, and none doubles its punctuation.
        for status in CaptureStatusPresentation.Status.allCases {
            let summary = CaptureStatusPresentation(
                status: status, headline: status.title, explanation: "Something happened."
            ).accessibilitySummary
            #expect(!summary.contains(".."), "\(status) doubles its sentence separator")
        }
    }

    private func evidence(start: Date, played: TimeInterval) -> PlaybackEvidence {
        PlaybackEvidence(
            deviceID: deviceID, sourceTrackID: "song-1", metadata: .init(title: "Track", artist: "Artist", album: "Album", duration: 240, startedAt: start),
            observedPlayTime: played, origin: .observed, confidence: .strong, capturedAt: start)
    }
}
