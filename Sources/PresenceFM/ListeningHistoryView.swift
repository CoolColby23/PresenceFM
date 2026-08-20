import AppKit
import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListeningHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]
    @State private var searchText = ""
    @State private var outcome: HistoryOutcomeFilter = .all
    @State private var period: HistoryPeriod = .month
    @State private var source: HistorySourceFilter = .local
    @State private var viewMode: HistoryViewMode = .overview
    @State private var showingClearConfirmation = false
    @State private var exportDocument: HistoryCSVDocument?
    @State private var showingExporter = false

    var body: some View {
        VStack(spacing: 0) {
            if records.isEmpty && !hasLastFMConnection && source != .lastFM {
                ContentUnavailableView {
                    Label("No Listening History Yet", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Play music in a supported app and your private listening history will appear here.")
                } actions: {
                    if model.preferences.lastFMEnabled == false {
                        Button("Connect Last.fm for multi-device history") {
                            model.openSettings(.integrations)
                        }
                        .presenceButton(prominent: true)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                        historyHeader
                        if source == .lastFM {
                            lastFMRemoteSection
                        } else {
                            historyModePicker
                            switch viewMode {
                            case .overview:
                                weeklyRecapCard
                                periodSummary
                                listeningOverview
                            case .insights:
                                extendedInsightCards
                            case .activity:
                                if source == .combined { lastFMRemoteSection }
                                historyList
                            }
                        }
                    }
                    .frame(maxWidth: 1100)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Listening History")
        .searchable(text: $searchText, prompt: "Search title, artist, or album")
        .toolbar {
            ToolbarItemGroup {
                Picker("Source", selection: $source) {
                    ForEach(HistorySourceFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(minWidth: 120, idealWidth: 150, maxWidth: 170)
                .onChange(of: source) { _, newValue in
                    if newValue != .local {
                        Task { await model.refreshLastFMRemoteHistory(force: true) }
                    }
                }
                if source != .lastFM {
                    Picker("Period", selection: $period) {
                        ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: 320)
                    Picker("Outcome", selection: $outcome) {
                        ForEach(HistoryOutcomeFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(minWidth: 95, idealWidth: 120, maxWidth: 135)
                }
                Menu("More", systemImage: "ellipsis.circle") {
                    if source != .local {
                        Button("Refresh Last.fm…", systemImage: "arrow.clockwise") {
                            Task { await model.refreshLastFMRemoteHistory(force: true) }
                        }
                        .disabled(!hasLastFMConnection || model.lastFMRemoteTracksLoading)
                    }
                    if source != .lastFM {
                        Button("Export Visible History…", systemImage: "square.and.arrow.up") { exportVisibleHistory() }
                            .disabled(filteredRecords.isEmpty)
                        Divider()
                        Button("Clear Listening History…", systemImage: "trash", role: .destructive) { showingClearConfirmation = true }
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear all listening history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { model.clearListeningHistory() }
        } message: {
            Text("This permanently removes local listening activity. It does not change Last.fm history.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "PresenceFM-History"
        ) { _ in exportDocument = nil }
        .task(id: source) {
            if source != .local {
                await model.refreshLastFMRemoteHistory()
            }
        }
    }

    private var hasLastFMConnection: Bool {
        model.preferences.lastFMEnabled && !model.lastFMUsername.isEmpty
    }

    private var summary: ListeningSummary { ListeningSummary(records: filteredRecords) }
    private var extendedInsights: ExtendedListeningInsights {
        ExtendedListeningInsights(records: records, period: period)
    }
    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source == .lastFM ? "Last.fm across your devices" : "Your listening, at a glance")
                .font(BrandTypography.sectionTitle)
            Text(headerDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var historyModePicker: some View {
        Picker("History View", selection: $viewMode) {
            ForEach(HistoryViewMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 440)
        .accessibilityIdentifier("history.view-mode")
    }

    private var headerDetail: String {
        switch source {
        case .local:
            return "\(period.rawValue) of local listening activity on this Mac"
        case .lastFM:
            if model.lastFMUsername.isEmpty {
                return "Connect Last.fm in Settings to see scrobbles from phones and other devices"
            }
            return "Recent scrobbles for \(model.lastFMUsername), including other devices"
        case .combined:
            return "Local insights plus Last.fm scrobbles from every connected device"
        }
    }

    private var lastFMRemoteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Last.fm recent scrobbles", systemImage: "dot.radiowaves.left.and.right")
                        .font(BrandTypography.cardTitle)
                    if let updated = model.lastFMRemoteTracksUpdatedAt {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Includes listens recorded outside PresenceFM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.lastFMRemoteTracksLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refreshLastFMRemoteHistory(force: true) }
                    }
                    .disabled(!hasLastFMConnection)
                }
            }

            if !hasLastFMConnection {
                ContentUnavailableView {
                    Label("Last.fm not connected", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Authorize Last.fm to pull scrobbles from your phone and other devices.")
                } actions: {
                    Button("Open Last.fm Settings") { model.openSettings(.integrations) }
                        .presenceButton(prominent: true)
                }
                .frame(minHeight: 160)
            } else if let error = model.lastFMRemoteTracksError, filteredRemoteTracks.isEmpty {
                ContentUnavailableView(
                    "Couldn’t load Last.fm",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(minHeight: 140)
            } else if filteredRemoteTracks.isEmpty {
                ContentUnavailableView(
                    model.lastFMRemoteTracksLoading ? "Loading Last.fm…" : "No matching Last.fm scrobbles",
                    systemImage: "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Finished scrobbles from Last.fm will show here." : "Try a different search.")
                )
                .frame(minHeight: 140)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRemoteTracks) { track in
                        LastFMRemoteHistoryRow(track: track)
                        if track.id != filteredRemoteTracks.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }
        }
        .padding(20)
        .presenceCard(elevated: true)
    }

    private var weeklyRecapCard: some View {
        let weeklyRecap = WeeklyListeningRecap(records: records)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("This Week", systemImage: "sparkles")
                    .font(.title3.bold())
                Spacer()
                Button("Copy Recap", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(weeklyRecap.shareText, forType: .string)
                }
                .disabled(weeklyRecap.listens == 0)
            }
            if weeklyRecap.listens == 0 {
                Text("Your weekly recap will appear after you finish a listen.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 24) {
                    RecapValue(value: weeklyRecap.listens.formatted(), label: "Listens")
                    RecapValue(value: weeklyRecap.minutes.formatted(), label: "Minutes")
                    RecapValue(value: weeklyRecap.uniqueArtists.formatted(), label: "Artists")
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    if let value = weeklyRecap.topArtist { LabeledContent("Top artist", value: value) }
                    if let value = weeklyRecap.topTrack { LabeledContent("Top track", value: value) }
                    if let value = weeklyRecap.topAlbum { LabeledContent("Top album", value: value) }
                    if let value = weeklyRecap.topPlatform { LabeledContent("Top platform", value: value) }
                    if let value = weeklyRecap.busiestDay { LabeledContent("Busiest day", value: value) }
                }
                .font(.callout)
            }
        }
        .padding(20)
        .presenceCard()
        .accessibilityElement(children: .contain)
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 280), spacing: 14)],
            alignment: .leading,
            spacing: 14
        ) {
            ComparisonHistoryMetric(
                title: "Listens", value: extendedInsights.comparison.current.listens.formatted(),
                comparison: comparisonText(extendedInsights.comparison.listenDelta), symbol: "play.fill",
                tint: theme.primaryColor)
            ComparisonHistoryMetric(
                title: "Minutes", value: extendedInsights.comparison.current.minutes.formatted(),
                comparison: comparisonText(extendedInsights.comparison.minuteDelta), symbol: "clock.fill",
                tint: theme.secondaryColor)
            HistoryMetric(
                title: "Early Skip Rate", value: extendedInsights.comparison.current.skipRate.formatted(.percent.precision(.fractionLength(0))),
                symbol: "forward.fill", tint: BrandColors.warning
            )
            .help("The share of eligible tracks replaced before the scrobble threshold. Pauses and interrupted sessions are excluded.")
            ComparisonHistoryMetric(
                title: "Artists", value: extendedInsights.comparison.current.uniqueArtists.formatted(),
                comparison: comparisonText(extendedInsights.comparison.artistDelta), symbol: "music.mic",
                tint: theme.primaryColor)
        }
    }

    private var periodSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistorySectionHeader(
                title: "\(period.rawValue) summary",
                detail: periodSummaryDetail
            )
            summaryGrid
            Label("Early skip rate is the share of eligible tracks changed before they reached the Last.fm listening threshold.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var periodSummaryDetail: String {
        if period == .all {
            return "Totals across all available listening history on this Mac"
        }
        let comparisonPeriod = "\(period.dayCount ?? 0)-day period"
        if extendedInsights.comparison.listenDelta == nil {
            return "No earlier \(comparisonPeriod) is available for comparison yet"
        }
        return "Compared with the previous \(comparisonPeriod) on this Mac"
    }

    private var listeningOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistorySectionHeader(
                title: "Listening rhythm",
                detail: "Your recent activity and most-played artists"
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 310, maximum: 540), spacing: 14, alignment: .top)],
                alignment: .leading,
                spacing: 14
            ) {
                activityChart
                topArtists
            }
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Recent 7 Days", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Text("\(summary.dailyCounts.reduce(0) { $0 + $1.plays }) total")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Chart(summary.dailyCounts) { item in
                BarMark(x: .value("Day", item.day, unit: .day), y: .value("Listens", item.plays))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [theme.secondaryColor, theme.primaryColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(.secondary)
                    AxisTick().foregroundStyle(.quaternary)
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .chartPlotStyle { plotArea in
                plotArea.background(.primary.opacity(0.025))
            }
            .frame(height: 190)
            .accessibilityLabel("Listens during the most recent seven days using the active filters")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .presenceCard()
    }

    @ViewBuilder private var topArtists: some View {
        if !summary.topArtists.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Top Artists", systemImage: "music.mic")
                        .font(.headline)
                    Spacer()
                    Text("By listens")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(summary.topArtists.enumerated()), id: \.element.id) { index, artist in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(index == 0 ? theme.primaryColor : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(artist.artist)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            ProgressView(
                                value: Double(artist.plays),
                                total: Double(max(summary.topArtists.first?.plays ?? 1, 1))
                            )
                            .tint(index == 0 ? theme.primaryColor : BrandColors.neutral)
                            .controlSize(.small)
                        }
                        Spacer()
                        Text(artist.plays.formatted())
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .presenceCard()
        }
    }

    private var extendedInsightCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistorySectionHeader(
                title: "Explore your library",
                detail: "Patterns from played tracks in the selected period"
            )
            LazyVGrid(
                columns: insightColumns,
                alignment: .leading,
                spacing: 14
            ) {
                RankedInsightCard(title: "Top Tracks", items: extendedInsights.topTracks)
                RankedInsightCard(title: "Top Albums", items: extendedInsights.topAlbums)
            }
            LazyVGrid(
                columns: insightColumns,
                alignment: .leading,
                spacing: 14
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Listening by Hour", systemImage: "clock")
                        .font(.headline)
                    Chart(extendedInsights.hourlyCounts) { item in
                        BarMark(x: .value("Hour", item.hour), y: .value("Listens", item.plays))
                            .foregroundStyle(theme.primaryColor.gradient)
                            .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) {
                            AxisValueLabel()
                            AxisTick().foregroundStyle(.quaternary)
                        }
                    }
                    .frame(height: 130)
                    .accessibilityLabel(hourlyAccessibilitySummary)
                }
                .padding(20)
                .presenceCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Music Platforms", systemImage: "music.note.list")
                        .font(.headline)
                    if extendedInsights.platformCounts.isEmpty {
                        Text("No played tracks in this period.").foregroundStyle(.secondary)
                    } else {
                        ForEach(extendedInsights.platformCounts) { item in
                            PlatformListenRow(
                                item: item,
                                total: max(extendedInsights.comparison.current.listens, 1)
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .presenceCard()
            }
            Text(
                "Comparisons use the immediately preceding equal-length period and all available local history. Search does not change comparison values; retention settings may limit older data."
            )
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var insightColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 260), spacing: 14, alignment: .top),
            GridItem(.flexible(minimum: 260), spacing: 14, alignment: .top)
        ]
    }

    private var hourlyAccessibilitySummary: String {
        guard let peak = extendedInsights.hourlyCounts.max(by: { $0.plays < $1.plays }), peak.plays > 0 else {
            return "No hourly listening activity in the selected period"
        }
        return "Hourly listening activity. The busiest hour begins at \(peak.hour):00 with \(peak.plays) listens."
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent activity on this Mac")
                        .font(BrandTypography.cardTitle)
                    Text("Local PresenceFM history stays private on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(filteredRecords.count) \(filteredRecords.count == 1 ? "track" : "tracks")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if filteredRecords.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("Adjust the search or filters."))
                    .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRecords) { record in
                        HistoryRow(record: record, currentArtwork: isCurrent(record) ? model.artworkData : nil)
                        if record.id != filteredRecords.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }
        }
        .padding(20)
        .presenceCard(elevated: true)
    }

    private var filteredRecords: [ActivityRecord] {
        let cutoff = period.cutoff(from: .now)
        return records.filter { record in
            let matchesPeriod = cutoff.map { record.startedAt >= $0 } ?? true
            let matchesOutcome: Bool =
                switch outcome {
                case .all: true
                case .played: record.outcomeLabel == "Played"
                case .listened: record.outcomeLabel == "Listened"
                case .skipped: record.outcomeLabel == "Skipped"
                }
            let matchesSearch =
                searchText.isEmpty
                || [record.title, record.artist, record.album ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesPeriod && matchesOutcome && matchesSearch
        }
    }

    private var filteredRemoteTracks: [LastFMRemoteTrack] {
        model.lastFMRemoteTracks.filter { track in
            searchText.isEmpty
                || [track.title, track.artist, track.album ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func isCurrent(_ record: ActivityRecord) -> Bool {
        record.title == model.snapshot.track?.title && record.artist == model.snapshot.track?.artist
    }

    private func comparisonText(_ delta: Int?) -> String {
        guard period != .all, let delta else { return "" }
        return delta == 0 ? "Same as prior" : "\(delta > 0 ? "+" : "")\(delta) vs prior"
    }

    private func exportVisibleHistory() {
        exportDocument = HistoryCSVDocument(text: HistoryCSVExporter.csv(records: filteredRecords))
        showingExporter = true
    }
}

enum HistorySourceFilter: String, CaseIterable, Identifiable {
    case local = "This Mac"
    case lastFM = "Last.fm"
    case combined = "Combined"
    var id: Self { self }
}

private enum HistoryViewMode: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case insights = "Insights"
    case activity = "Activity"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .insights: "chart.xyaxis.line"
        case .activity: "list.bullet"
        }
    }
}

private struct LastFMRemoteHistoryRow: View {
    let track: LastFMRemoteTrack
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            remoteArtwork
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(track.title)
                        .font(.headline)
                        .lineLimit(1)
                    if track.isNowPlaying {
                        Text("Now")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.primaryColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.primaryColor.opacity(0.12), in: .capsule)
                    }
                }
                Text(track.artist)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let album = track.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label("Last.fm", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.primaryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(theme.primaryColor.opacity(0.11), in: .capsule)
                if let listenedAt = track.listenedAt {
                    Text(listenedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if track.isNowPlaying {
                    Text("Playing now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 128, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var remoteArtwork: some View {
        if let url = track.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    remotePlaceholder
                case .empty:
                    ZStack {
                        remotePlaceholder
                        ProgressView().controlSize(.mini)
                    }
                @unknown default:
                    remotePlaceholder
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
        } else {
            remotePlaceholder
                .frame(width: 50, height: 50)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
        }
    }

    private var remotePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [theme.darkBackground, theme.primaryColor.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            BrandMark().padding(10)
        }
    }
}

private struct ComparisonHistoryMetric: View {
    let title: String
    let value: String
    let comparison: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MetricIcon(symbol: symbol, tint: tint)
                Spacer()
                if !comparison.isEmpty {
                    Text(comparison)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title.bold())
                    .monospacedDigit()
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(18)
        .presenceCard()
        .accessibilityElement(children: .combine)
    }
}

private struct RankedInsightCard: View {
    let title: String
    let items: [RankedListen]
    @Environment(\.appTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: title == "Top Tracks" ? "music.note" : "square.stack")
                .font(.headline)
            if items.isEmpty {
                Text("No played tracks in this period.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(index == 0 ? theme.primaryColor : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(item.plays.formatted())
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .presenceCard()
    }
}

private struct HistoryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MetricIcon(symbol: symbol, tint: tint)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title.bold())
                    .monospacedDigit()
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(18)
        .presenceCard()
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRow: View {
    let record: ActivityRecord
    let currentArtwork: Data?
    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(data: currentArtwork ?? record.artworkData, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.artist)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let album = record.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                OutcomeLabel(outcome: record.outcomeLabel)
                Text(record.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 116, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct HistorySectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MetricIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

private struct RecapValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlatformListenRow: View {
    let item: PlatformListenCount
    let total: Int
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(item.platform)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(item.plays.formatted())
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(item.plays), total: Double(total))
                .tint(theme.primaryColor)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OutcomeLabel: View {
    let outcome: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Label(outcome, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.11), in: .capsule)
    }

    private var symbol: String {
        outcome == "Skipped" ? "forward.fill" : "checkmark"
    }

    private var tint: Color {
        outcome == "Skipped" ? BrandColors.neutral : theme.primaryColor
    }
}

struct HistoryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
