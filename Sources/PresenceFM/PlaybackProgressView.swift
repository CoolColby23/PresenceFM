import Foundation
import SwiftUI

struct PlaybackProgress: View {
    let snapshot: PlaybackSnapshot
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: snapshot.state != .playing)) { context in
            let position = PlaybackProgressPresentation.position(
                for: snapshot,
                at: context.date,
                duration: duration
            )
            PlaybackProgressContent(position: position, duration: duration)
        }
    }
}

private struct PlaybackProgressContent: View {
    let position: TimeInterval
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: min(max(position, 0), duration), total: max(duration, 1))
                .tint(BrandColors.accentRibbon)
                .accessibilityLabel("Playback progress")
                .accessibilityValue(
                    PlaybackProgressPresentation.accessibilityValue(
                        position: position,
                        duration: duration
                    )
                )
            HStack {
                Text(position.formattedDuration)
                Spacer()
                Text("−\(max(0, duration - position).formattedDuration)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

enum PlaybackProgressPresentation {
    static let announcementInterval: TimeInterval = 15

    static func position(
        for snapshot: PlaybackSnapshot,
        at date: Date,
        duration: TimeInterval
    ) -> TimeInterval {
        let elapsed = snapshot.state == .playing ? max(0, date.timeIntervalSince(snapshot.observedAt)) : 0
        return min(max(0, snapshot.position + elapsed), max(0, duration))
    }

    static func accessibilityValue(position: TimeInterval, duration: TimeInterval) -> String {
        let announcedPosition = min(
            max(0, floor(position / announcementInterval) * announcementInterval),
            max(0, duration)
        )
        return "\(announcedPosition.formattedDuration) elapsed, \(max(0, duration - announcedPosition).formattedDuration) remaining"
    }
}
