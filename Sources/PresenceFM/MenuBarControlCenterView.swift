import AppKit
import SwiftData
import SwiftUI

struct MenuBarControlCenterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(alignment: .leading, spacing: 14) {
            nowPlaying
            Divider()
            sharingControls(preferences: preferences)
            MenuBarWeeklyRecapView()
            PrivacyControls()
            Divider()
            HStack {
                Button("Dashboard") { NSApp.showDashboard(using: openWindow) }
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") {
                    model.shutdown(); NSApp.terminate(nil)
                }
            }
        }
        .padding(18)
        .frame(width: 410)
        .task { model.start() }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ArtworkView(image: model.artworkImage, size: 68)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.snapshot.track?.title ?? "Nothing Playing").font(.headline).lineLimit(1)
                    Text(model.snapshot.track?.artist ?? "Choose a connected music app")
                        .foregroundStyle(.secondary).lineLimit(1)
                    if let platform = model.snapshot.track?.platform.rawValue {
                        Text(platform).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            if let track = model.snapshot.track {
                if track.supportsFiniteProgress {
                    PlaybackProgress(snapshot: model.snapshot, duration: track.duration)
                }
                ScrobbleProgress(state: model.scrobblePresentation)
            }
        }
    }

    private func sharingControls(preferences: Preferences) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Sharing").font(.headline)
            HStack {
                Toggle(
                    "Discord",
                    isOn: Binding(
                        get: { preferences.discordEnabled },
                        set: { model.setDiscordEnabled($0) }
                    ))
                Spacer()
                Text(model.discordStatus.label).font(.caption).foregroundStyle(.secondary)
                Button("Reconnect", systemImage: "arrow.clockwise") { model.refreshDiscord() }
                    .labelStyle(.iconOnly)
                    .disabled(!preferences.discordEnabled)
                    .help("Reconnect Discord")
                    .accessibilityLabel("Reconnect Discord")
            }
            if preferences.discordEnabled {
                Menu(selectedProfileName) {
                    ForEach(preferences.availableDiscordProfiles) { profile in
                        Button(profile.name) { model.applyDiscordProfile(id: profile.id) }
                    }
                }
                .accessibilityLabel("Discord presence profile")
            }
            HStack {
                Toggle(
                    "Last.fm",
                    isOn: Binding(
                        get: { preferences.lastFMEnabled },
                        set: { model.setLastFMEnabled($0) }
                    ))
                Spacer()
                Text(model.lastFMStatus.label).font(.caption).foregroundStyle(.secondary)
                Button("Open settings", systemImage: "gearshape") {
                    model.selectedSection = .settings
                    NSApp.showDashboard(using: openWindow)
                }
                .labelStyle(.iconOnly)
                .help("Open Last.fm settings")
                .accessibilityLabel("Open Last.fm settings")
            }
        }
    }

    private var selectedProfileName: String {
        guard let id = model.preferences.selectedDiscordProfileID,
            let profile = model.preferences.availableDiscordProfiles.first(where: { $0.id == id })
        else {
            return "Presence Profile"
        }
        return profile.name
    }
}

private struct MenuBarWeeklyRecapView: View {
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]

    var body: some View {
        let recap = WeeklyListeningRecap(records: records)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("This Week", systemImage: "sparkles").font(.headline)
                Spacer()
                if recap.listens > 0 {
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(recap.shareText, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .help("Copy weekly recap")
                    .accessibilityLabel("Copy weekly recap")
                }
            }
            if recap.listens == 0 {
                Text("No completed listens yet").foregroundStyle(.secondary)
            } else {
                Text("\(recap.listens) listens · \(recap.minutes) min · \(recap.uniqueArtists) artists")
                    .font(.callout.weight(.medium))
                if let artist = recap.topArtist {
                    Text("Top artist: \(artist)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
