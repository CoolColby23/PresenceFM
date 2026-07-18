import Foundation

actor PlaybackSessionTracker {
    private static let stoppedGracePeriod: TimeInterval = 2
    private(set) var active: PlaybackSession?
    private var lastObservedAt: Date?
    private var lastState: PlaybackState = .stopped
    private var missingTrackSince: Date?

    enum Event: Sendable {
        case started(PlaybackSession)
        case updated(PlaybackSession)
        case eligible(PlaybackSession)
        case finalized(PlaybackSession)
        case none
    }

    func ingest(_ snapshot: PlaybackSnapshot) -> [Event] {
        var events: [Event] = []
        guard snapshot.confidence != .low else {
            // Permission and transient metadata failures must not turn an active listen into a skip.
            lastObservedAt = snapshot.observedAt
            lastState = .paused
            return [.none]
        }
        guard let track = snapshot.track else {
            guard active != nil else {
                lastObservedAt = snapshot.observedAt
                lastState = snapshot.state
                return [.none]
            }
            if active?.eligibility != .eligible {
                if missingTrackSince == nil {
                    missingTrackSince = snapshot.observedAt
                    lastObservedAt = snapshot.observedAt
                    lastState = snapshot.state
                    return [.none]
                }
                guard snapshot.observedAt.timeIntervalSince(missingTrackSince ?? snapshot.observedAt) >= Self.stoppedGracePeriod else {
                    lastObservedAt = snapshot.observedAt
                    lastState = snapshot.state
                    return [.none]
                }
            }
            if let finalized = finalize(as: finalOutcome(for: active, replacementState: nil)) {
                events.append(.finalized(finalized))
            }
            missingTrackSince = nil
            lastObservedAt = snapshot.observedAt
            lastState = snapshot.state
            return events.isEmpty ? [.none] : events
        }

        missingTrackSince = nil
        if active?.track.identity != track.identity {
            if let finalized = finalize(as: finalOutcome(for: active, replacementState: snapshot.state)) {
                events.append(.finalized(finalized))
            }
            let initialPlayTime = min(max(0, snapshot.position), max(0, track.duration))
            var session = PlaybackSession(
                id: UUID(), track: track,
                startedAt: snapshot.observedAt.addingTimeInterval(-snapshot.position),
                accumulatedPlayTime: initialPlayTime, lastPosition: snapshot.position,
                eligibility: track.isScrobbleable ? .listening : .ineligible,
                outcome: .active
            )
            if snapshot.state == .playing { session.eligibility = eligibility(for: session) }
            active = session
            events.append(.started(session))
        } else if var session = active {
            if lastState == .playing, snapshot.state == .playing, let lastObservedAt {
                let wallDelta = max(0, snapshot.observedAt.timeIntervalSince(lastObservedAt))
                let positionDelta = snapshot.position - session.lastPosition
                // Count wall time only while playback advances naturally. Forward seeks do not
                // grant listening credit and backward seeks do not erase earned credit.
                if positionDelta >= -2, positionDelta <= wallDelta + 4 {
                    session.accumulatedPlayTime += min(wallDelta, max(0, positionDelta + 1))
                }
            }
            session.lastPosition = snapshot.position
            let before = session.eligibility
            session.eligibility = eligibility(for: session)
            active = session
            events.append(before != .eligible && session.eligibility == .eligible ? .eligible(session) : .updated(session))
        }

        lastObservedAt = snapshot.observedAt
        lastState = snapshot.state
        return events
    }

    func shutdown() -> PlaybackSession? {
        finalize(as: finalOutcome(for: active, replacementState: nil))
    }

    private func eligibility(for session: PlaybackSession) -> ScrobbleEligibility {
        guard session.track.isScrobbleable else { return .ineligible }
        let threshold = session.scrobbleThreshold
        return session.accumulatedPlayTime >= threshold ? .eligible : .listening
    }

    private func finalize(as outcome: SessionOutcome) -> PlaybackSession? {
        guard var session = active else { return nil }
        session.outcome = outcome
        active = nil
        return session
    }

    private func finalOutcome(
        for session: PlaybackSession?,
        replacementState: PlaybackState?
    ) -> SessionOutcome {
        guard let session else { return .interrupted }
        if session.eligibility == .eligible { return .played }
        if session.track.isStream || !session.track.isScrobbleable { return .listened }
        if lastState == .playing, replacementState == .playing { return .skipped }
        return .interrupted
    }
}
