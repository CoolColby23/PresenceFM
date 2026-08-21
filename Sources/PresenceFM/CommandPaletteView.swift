import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Open a page or run an action", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                Text("⌘K")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
            }
            .padding(18)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if filteredCommands.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        ForEach(filteredCommands) { command in
                            Button {
                                command.action()
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: command.symbol)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 34, height: 34)
                                        .background(.quaternary, in: .rect(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(command.title)
                                            .font(.callout.weight(.semibold))
                                        Text(command.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(command.group)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(.rect)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(command.detail)
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 560, height: 500)
        .onAppear { searchFocused = true }
    }

    private var filteredCommands: [PaletteCommand] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return commands }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return commands.filter { command in
            let haystack = "\(command.title) \(command.detail) \(command.group) \(command.keywords)".lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    private var commands: [PaletteCommand] {
        let navigation = DashboardSection.allCases.map { section in
            PaletteCommand(
                id: "section.\(section.rawValue)", title: section.title,
                detail: "Open \(section.title)", group: "Navigate", symbol: section.symbol,
                keywords: section.rawValue
            ) { model.navigate(to: section) }
        }
        let settings = SettingsCategory.allCases.map { category in
            PaletteCommand(
                id: "settings.\(category.rawValue)", title: category.rawValue,
                detail: category.detail, group: "Settings", symbol: category.symbol,
                keywords: "preferences configuration"
            ) { model.openSettings(category) }
        }
        var actions = [
            PaletteCommand(
                id: "privacy", title: model.isPrivate ? "End Private Mode" : "Go Private",
                detail: model.isPrivate ? "Resume Discord and Last.fm sharing" : "Pause external sharing until resumed",
                group: "Action", symbol: model.isPrivate ? "eye" : "eye.slash", keywords: "discord lastfm privacy"
            ) {
                model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
            },
            PaletteCommand(
                id: "demo", title: model.demoModeEnabled ? "End Demo Playback" : "Start Demo Playback",
                detail: "Preview the Now Playing experience safely", group: "Action",
                symbol: "testtube.2", keywords: "sample test music"
            ) { model.setDemoModeEnabled(!model.demoModeEnabled) },
        ]
        if model.snapshot.track != nil {
            actions.append(
                PaletteCommand(
                    id: "artwork", title: "Reload Album Artwork",
                    detail: "Clear the current cover cache and fetch it again", group: "Action",
                    symbol: "photo.badge.arrow.down", keywords: "cover image retry repair"
                ) { model.retryCurrentArtwork() }
            )
        }
        return navigation + settings + actions
    }
}

private struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let detail: String
    let group: String
    let symbol: String
    let keywords: String
    let action: () -> Void
}
