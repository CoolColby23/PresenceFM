import PresenceFMCore
import SwiftUI

struct NowPlayingOverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 14, alignment: .top)],
            alignment: .center,
            spacing: 14
        ) {
            captureCard
            playbackCard
            sharingCard
            activityCard
        }
    }

    private var captureCard: some View {
        let presentation = model.captureStatus
        return NowPlayingInfoCard(title: "Scrobble status", symbol: presentation.status.symbol) {
            CaptureConfidenceContent(presentation: presentation) {
                if let action = presentation.recoveryAction {
                    model.performCaptureRecovery(action)
                }
            }
        }
    }

    private var playbackCard: some View {
        NowPlayingInfoCard(title: "Playback & artwork", symbol: "waveform") {
            OverviewStatusRow(
                title: model.playbackServiceName,
                detail: model.musicStatus.detailLabel ?? "Playback detection",
                status: model.musicStatus
            )
            Divider()
            HStack(spacing: 10) {
                Image(systemName: artworkSymbol)
                    .foregroundStyle(artworkTint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Album artwork").font(.callout.weight(.semibold))
                    Text(artworkDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.snapshot.track != nil, !model.demoModeEnabled {
                    Button("Reload", systemImage: "arrow.clockwise") { model.retryCurrentArtwork() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Clear the cached cover and load it again")
                }
            }
        }
    }

    private var sharingCard: some View {
        NowPlayingInfoCard(title: "Sharing", symbol: model.isPrivate ? "eye.slash" : "antenna.radiowaves.left.and.right") {
            if model.isPrivate {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill").foregroundStyle(BrandColors.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private Mode").font(.callout.weight(.semibold))
                        Text("Discord and Last.fm are paused").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Resume") { model.endPrivateMode() }.buttonStyle(.borderless)
                }
                Divider()
            }
            OverviewStatusRow(
                title: "Discord", detail: connectionDetail(for: .discord), status: model.discordStatus
            )
            Divider()
            OverviewStatusRow(
                title: "Last.fm", detail: connectionDetail(for: .lastFM), status: model.lastFMStatus
            )
        }
    }

    private var activityCard: some View {
        // Read once: the model derives this list on every access.
        let activity = model.recentCaptureActivity
        return NowPlayingInfoCard(title: "Recent scrobble activity", symbol: "clock.arrow.circlepath") {
            if activity.isEmpty {
                Text("Completed and interrupted plays will be explained here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(activity.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    HStack(spacing: 9) {
                        Image(systemName: entry.status.symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(entry.status.tint)
                            .frame(width: 13)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.headline)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(entry.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let timestamp = entry.timestamp {
                            Text(timestamp, style: .relative)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(entry.accessibilitySummary)
                }
            }
        }
    }

    private var artworkDetail: String {
        switch model.artworkLoadState {
        case .idle: "Waiting for a track"
        case .loading: "Looking for the best matching cover…"
        case .available(let source): "Loaded from \(source.label)"
        case .unavailable: "No trustworthy cover was found"
        }
    }

    private var artworkSymbol: String {
        switch model.artworkLoadState {
        case .idle: "photo"
        case .loading: "arrow.trianglehead.2.clockwise.rotate.90"
        case .available: "checkmark.circle.fill"
        case .unavailable: "photo.badge.exclamationmark"
        }
    }

    private var artworkTint: Color {
        switch model.artworkLoadState {
        case .available: BrandColors.success
        case .unavailable: BrandColors.warning
        default: BrandColors.neutral
        }
    }

    private func connectionDetail(for id: IntegrationID) -> String {
        guard let health = model.integrationHealth.first(where: { $0.integration == id }) else {
            return "No successful connection yet"
        }
        if let date = health.lastSuccessfulAt {
            return "Last connected \(date.formatted(.relative(presentation: .named)))"
        }
        return health.summary
    }

}

private struct CaptureConfidenceContent: View {
    let presentation: CaptureStatusPresentation
    let recovery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(presentation.status.title, systemImage: presentation.status.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(presentation.status.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(presentation.status.tint.opacity(0.12), in: .capsule)
                Spacer()
                if let timestamp = presentation.timestamp {
                    Text(timestamp, style: .relative)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(presentation.headline)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .accessibilityLabel("Scrobble eligibility")
                    .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
            }
            if let action = presentation.recoveryAction {
                Button(action.buttonTitle, action: recovery)
                    .buttonStyle(.borderless)
            }
        }
        // The status, headline, explanation, and progress are one statement, so
        // VoiceOver reads them as one stop instead of four fragments. The
        // recovery button stays separately focusable.
        .accessibilityElement(children: .contain)
        .accessibilityRepresentation {
            VStack {
                Text(presentation.accessibilitySummary)
                if let action = presentation.recoveryAction {
                    Button(action.buttonTitle, action: recovery)
                }
            }
        }
    }
}

// Titles, symbols, and tone come from `PresenceFMCore` so the Mac and iPhone
// apps describe the same situation identically. Only the palette is local.
private extension CaptureStatusPresentation.Status {
    var tint: Color {
        switch tone {
        case .positive: BrandColors.success
        case .active: BrandColors.electricBlue
        case .paused: BrandColors.warning
        case .neutral: BrandColors.neutral
        case .critical: BrandColors.error
        }
    }
}

private struct NowPlayingInfoCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(theme.primaryColor)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .padding(16)
        .presenceCard(elevated: true)
    }
}

private struct OverviewStatusRow: View {
    let title: String
    let detail: String
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(status.tintColor).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(status.presentationLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(status.tintColor)
        }
    }
}
