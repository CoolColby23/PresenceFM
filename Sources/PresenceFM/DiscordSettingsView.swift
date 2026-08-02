import SwiftUI

struct DiscordSettingsSection: View {
    let model: AppModel
    let preferences: Preferences
    @State private var profileName = ""

    var body: some View {
        @Bindable var preferences = preferences
        Section("Discord") {
            Toggle("Enable Discord Rich Presence", isOn: $preferences.discordEnabled)
                .accessibilityIdentifier("discord.enabled")
                .onChange(of: preferences.discordEnabled) { _, value in model.setDiscordEnabled(value) }
            profileControls
            Picker("Activity style", selection: $preferences.discordActivityType) {
                ForEach(DiscordActivityType.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.activity-style")
            .onChange(of: preferences.discordActivityType) { _, _ in refresh() }
            TextField("Activity name", text: $preferences.discordActivityName, prompt: Text("PresenceFM"))
                .accessibilityIdentifier("discord.activity-name")
                .onSubmit { refresh() }
            Text("This is the text after “\(preferences.discordActivityType.rawValue)” in Discord. Templates are supported.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("First line", selection: $preferences.discordLineOne) {
                ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.first-line")
            .onChange(of: preferences.discordLineOne) { _, _ in refresh() }
            if preferences.discordLineOne == .custom {
                TextField("First line template", text: $preferences.discordCustomLineOne).onSubmit { refresh() }
            }
            Picker("Second line", selection: $preferences.discordLineTwo) {
                ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.second-line")
            .onChange(of: preferences.discordLineTwo) { _, _ in refresh() }
            if preferences.discordLineTwo == .custom {
                TextField("Second line template", text: $preferences.discordCustomLineTwo).onSubmit { refresh() }
            }
            Toggle("Include album in formatted lines", isOn: $preferences.showAlbum)
                .onChange(of: preferences.showAlbum) { _, _ in refresh() }
            Picker("Timer", selection: $preferences.discordTimerStyle) {
                ForEach(DiscordTimerStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.timer")
            .onChange(of: preferences.discordTimerStyle) { _, _ in refresh() }
            Toggle("Keep status visible while paused", isOn: $preferences.discordSharePaused)
                .accessibilityIdentifier("discord.share-paused")
                .onChange(of: preferences.discordSharePaused) { _, _ in refresh() }
            if preferences.discordSharePaused {
                TextField("Paused status template", text: $preferences.discordPausedText).onSubmit { refresh() }
            }
            Picker("Large image", selection: $preferences.discordLargeImage) {
                ForEach(DiscordLargeImage.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.large-image")
            .onChange(of: preferences.discordLargeImage) { _, _ in refresh() }
            TextField("Large image hover text", text: $preferences.discordLargeImageText, prompt: Text("Optional"))
                .onSubmit { refresh() }
            Picker("Small image", selection: $preferences.discordSmallImage) {
                ForEach(DiscordSmallImage.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.small-image")
            .onChange(of: preferences.discordSmallImage) { _, _ in refresh() }
            if preferences.discordSmallImage != .none {
                TextField("Small image hover text", text: $preferences.discordSmallImageText, prompt: Text("Automatic"))
                    .onSubmit { refresh() }
            }
            Toggle("Show listening link", isOn: $preferences.showLink)
                .accessibilityIdentifier("discord.show-link")
                .onChange(of: preferences.showLink) { _, _ in refresh() }
            if preferences.showLink {
                TextField("Button label", text: $preferences.discordButtonLabel, prompt: Text("Automatic for each platform"))
                    .onSubmit { refresh() }
                Text("Discord limits button labels to 32 characters.").font(.caption).foregroundStyle(.secondary)
            }
            DiscordStatusPreview(
                firstLine: preview(preferences.discordLineOne, custom: preferences.discordCustomLineOne),
                secondLine: preview(preferences.discordLineTwo, custom: preferences.discordCustomLineTwo),
                activity: preferences.discordActivityType.rawValue,
                activityName: previewActivityName,
                timer: preferences.discordTimerStyle.rawValue
            )
            Text("Templates support {title}, {artist}, {album}, {platform}, {state}, {position}, and {duration}.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if preferences.discordEnabled { Button("Reconnect to Discord") { model.refreshDiscord() } }
            }
        }
    }

    private var profileControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu(selectedProfileName) {
                    ForEach(preferences.availableDiscordProfiles) { profile in
                        Button {
                            model.applyDiscordProfile(id: profile.id)
                        } label: {
                            if preferences.selectedDiscordProfileID == profile.id {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                }
                .accessibilityLabel("Discord presence profile")
                TextField("New profile name", text: $profileName)
                    .accessibilityIdentifier("discord.profile-name")
                Button("Save Current") {
                    if model.saveDiscordProfile(named: profileName) != nil { profileName = "" }
                }
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !preferences.discordPresenceProfiles.isEmpty {
                Menu("Delete Custom Profile") {
                    ForEach(preferences.discordPresenceProfiles) { profile in
                        Button(profile.name, role: .destructive) { model.deleteDiscordProfile(id: profile.id) }
                    }
                }
            }
            Text("Profiles save the current Discord layout and sharing options. Built-in profiles are always available.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var selectedProfileName: String {
        guard let id = preferences.selectedDiscordProfileID,
            let profile = preferences.availableDiscordProfiles.first(where: { $0.id == id })
        else {
            return "Choose Profile"
        }
        return profile.name
    }

    private var previewActivityName: String {
        let rendered = DiscordTemplate.render(
            preferences.discordActivityName,
            title: "Midnight Drive",
            artist: "The Satellites",
            album: "Afterglow",
            platform: .appleMusic,
            position: 82,
            duration: 224
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? "PresenceFM" : rendered
    }

    private func preview(_ format: DiscordLineFormat, custom: String) -> String {
        let template =
            format == .custom
            ? custom
            : format.value(title: "Midnight Drive", artist: "The Satellites", album: "Afterglow")
        let rendered = DiscordTemplate.render(
            template,
            title: "Midnight Drive",
            artist: "The Satellites",
            album: "Afterglow",
            platform: .appleMusic,
            position: 82,
            duration: 224
        )
        return rendered.isEmpty ? "Apple Music" : rendered
    }

    private func refresh() { model.refreshPresenceOptions() }

}

private struct DiscordStatusPreview: View {
    let firstLine: String
    let secondLine: String
    let activity: String
    let activityName: String
    let timer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(firstLine).font(.headline).lineLimit(1)
            Text(secondLine).foregroundStyle(.secondary).lineLimit(1)
            Text("\(activity) \(activityName) · \(timer)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("discord.preview")
        .accessibilityLabel("Discord preview: \(activity) \(activityName), \(firstLine), \(secondLine), \(timer)")
    }
}
