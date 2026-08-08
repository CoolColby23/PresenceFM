import AppKit
import SwiftData
import SwiftUI

struct MenuBarControlCenterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            header
            nowPlaying
            sharingControls(preferences: preferences)
            MenuBarWeeklyRecapView()
            PrivacyControls()
            HStack {
                Button("Dashboard") { NSApp.showDashboard(using: openWindow) }
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") {
                    model.shutdown(); NSApp.terminate(nil)
                }
            }
            .presenceButton()
        }
        .padding(18)
        .frame(width: 432, alignment: .leading)
        .presencePanelBackground()
        .task { model.start() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandMark()
                .frame(width: 34, height: 34)
                .padding(8)
                .background(.ultraThinMaterial, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("PresenceFM")
                    .font(BrandTypography.sectionTitle)
                Text(model.isPrivate ? "Private Mode engaged" : "Control center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.demoModeEnabled {
                StatusCapsule(title: "Demo", status: .connected)
            }
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ArtworkView(image: model.artworkImage, size: 86)
                    .presenceHeroGlow(active: model.snapshot.state == .playing)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.snapshot.track?.title ?? "Nothing Playing")
                        .font(BrandTypography.cardTitle)
                        .lineLimit(2)
                    Text(model.snapshot.track?.artist ?? "Choose a connected music app")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let platform = model.snapshot.track?.platform.rawValue {
                        Text(platform)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .padding(14)
        .presenceCard(elevated: true)
    }

    private func sharingControls(preferences: Preferences) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sharing")
                .font(BrandTypography.cardTitle)
            HStack {
                Toggle(
                    "Discord",
                    isOn: Binding(
                        get: { preferences.discordEnabled },
                        set: { model.setDiscordEnabled($0) }
                    ))
                Spacer()
                Text(model.discordStatus.presentationLabel).font(.caption).foregroundStyle(.secondary)
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
                Text(model.lastFMStatus.presentationLabel).font(.caption).foregroundStyle(.secondary)
                Button("Open settings", systemImage: "gearshape") {
                    model.selectedSection = .settings
                    NSApp.showDashboard(using: openWindow)
                }
                .labelStyle(.iconOnly)
                .help("Open Last.fm settings")
                .accessibilityLabel("Open Last.fm settings")
            }
        }
        .padding(14)
        .presenceCard(elevated: true)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("This Week", systemImage: "sparkles")
                    .font(BrandTypography.cardTitle)
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
                Text("No completed listens yet")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(recap.listens) listens · \(recap.minutes) min · \(recap.uniqueArtists) artists")
                    .font(.callout.weight(.medium))
                if let artist = recap.topArtist {
                    Text("Top artist: \(artist)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .presenceCard(elevated: true)
        .accessibilityElement(children: .contain)
    }
}
