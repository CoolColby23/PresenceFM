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
        NowPlayingInfoCard(title: "Recent scrobble activity", symbol: "clock.arrow.circlepath") {
            if model.recentCaptureActivity.isEmpty {
                Text("Completed and interrupted plays will be explained here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.recentCaptureActivity.enumerated()), id: \.offset) { index, activity in
                    if index > 0 { Divider() }
                    HStack(spacing: 9) {
                        Circle()
                            .fill(activity.status.tint)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.headline)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(activity.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let timestamp = activity.timestamp {
                            Text(timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
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
                Image(systemName: presentation.status.symbol)
                    .foregroundStyle(presentation.status.tint)
                Text(presentation.headline)
                    .font(.callout.weight(.semibold))
                Spacer()
                if let timestamp = presentation.timestamp {
                    Text(timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(presentation.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .accessibilityLabel("Scrobble eligibility")
                    .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
            }
            if presentation.recoveryAction != nil {
                Button(presentation.recoveryAction!.buttonTitle, action: recovery)
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private extension CaptureStatusPresentation.Status {
    var symbol: String {
        switch self {
        case .detecting: "waveform.badge.magnifyingglass"
        case .progressing: "waveform"
        case .queued: "tray.full"
        case .submitted: "checkmark.circle.fill"
        case .excluded: "nosign"
        case .privateMode: "eye.slash.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .submitted: BrandColors.success
        case .progressing, .detecting: BrandColors.electricBlue
        case .queued, .privateMode: BrandColors.warning
        case .excluded: BrandColors.neutral
        case .needsAttention: BrandColors.error
        }
    }
}

private extension CaptureStatusPresentation.RecoveryAction {
    var buttonTitle: String {
        switch self {
        case .grantPlaybackPermission: "Grant Permission"
        case .reconnectLastFM: "Reconnect Last.fm"
        case .retryQueue: "Review Queue"
        case .disablePrivateMode: "End Private Mode"
        case .openSettings: "Open Settings"
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
