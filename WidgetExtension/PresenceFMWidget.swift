import Foundation
import SwiftUI
import WidgetKit

private struct WidgetSnapshot: Codable {
    let title: String
    let artist: String
    let platform: String
    let state: String
    let position: TimeInterval
    let duration: TimeInterval
    let observedAt: Date
    let isPrivate: Bool
}

private struct PresenceFMEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct PresenceFMProvider: TimelineProvider {
    func placeholder(in context: Context) -> PresenceFMEntry {
        PresenceFMEntry(date: .now, snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PresenceFMEntry) -> Void) {
        completion(PresenceFMEntry(date: .now, snapshot: load() ?? sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PresenceFMEntry>) -> Void) {
        let now = Date.now
        completion(
            Timeline(
                entries: [PresenceFMEntry(date: now, snapshot: load())],
                policy: .after(now.addingTimeInterval(60))
            ))
    }

    private func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: "group.fm.presence.PresenceFM"),
            let data = defaults.data(forKey: "widgetSnapshot")
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private var sample: WidgetSnapshot {
        WidgetSnapshot(
            title: "Midnight Signal", artist: "PresenceFM", platform: "Apple Music",
            state: "playing", position: 42, duration: 180, observedAt: .now, isPrivate: false
        )
    }
}

private struct PresenceFMWidgetView: View {
    let entry: PresenceFMEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("PresenceFM", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if entry.snapshot?.isPrivate == true {
                Label("Private Mode", systemImage: "eye.slash.fill").font(.headline)
                Text("Listening details are hidden").font(.caption).foregroundStyle(.secondary)
            } else if let snapshot = entry.snapshot {
                Text(snapshot.title).font(.headline).lineLimit(2)
                Text(snapshot.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(snapshot.platform).font(.caption2).foregroundStyle(.tertiary)
                if snapshot.duration > 0 {
                    ProgressView(value: currentPosition(snapshot), total: snapshot.duration)
                }
            } else {
                Text("Open PresenceFM").font(.headline)
                Text("Launch the app to update this widget.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "presencefm://now-playing"))
    }

    private func currentPosition(_ snapshot: WidgetSnapshot) -> TimeInterval {
        let elapsed = snapshot.state == "playing" ? max(0, entry.date.timeIntervalSince(snapshot.observedAt)) : 0
        return min(snapshot.duration, max(0, snapshot.position + elapsed))
    }
}

@main
struct PresenceFMWidget: Widget {
    let kind = "PresenceFMNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PresenceFMProvider()) { entry in
            PresenceFMWidgetView(entry: entry)
        }
        .configurationDisplayName("PresenceFM Now Playing")
        .description("See the current track and playback progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
