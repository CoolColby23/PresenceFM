import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListeningHistoryView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]
    @State private var searchText = ""
    @State private var outcome: HistoryOutcomeFilter = .all
    @State private var period: HistoryPeriod = .month
    @State private var showingClearConfirmation = false
    @State private var exportDocument: HistoryCSVDocument?
    @State private var showingExporter = false

    var body: some View {
        VStack(spacing: 0) {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Listening History Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Play music in a supported app and your private listening history will appear here.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        historyHeader
                        summaryGrid
                        listeningOverview
                        extendedInsightCards
                        historyList
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
                Picker("Period", selection: $period) {
                    ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 320)
                Picker("Outcome", selection: $outcome) {
                    ForEach(HistoryOutcomeFilter.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 125)
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Export Visible History…", systemImage: "square.and.arrow.up") { exportVisibleHistory() }
                        .disabled(filteredRecords.isEmpty)
                    Divider()
                    Button("Clear Listening History…", systemImage: "trash", role: .destructive) { showingClearConfirmation = true }
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
    }

    private var summary: ListeningSummary { ListeningSummary(records: filteredRecords) }
    private var extendedInsights: ExtendedListeningInsights {
        ExtendedListeningInsights(records: records, period: period)
    }

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your listening, at a glance")
                .font(.title2.bold())
            Text("\(period.rawValue) of local listening activity")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
                tint: BrandColors.electricBlue)
            ComparisonHistoryMetric(
                title: "Minutes", value: extendedInsights.comparison.current.minutes.formatted(),
                comparison: comparisonText(extendedInsights.comparison.minuteDelta), symbol: "clock.fill",
                tint: BrandColors.cyan)
            HistoryMetric(
                title: "Early Skip Rate", value: extendedInsights.comparison.current.skipRate.formatted(.percent.precision(.fractionLength(0))),
                symbol: "forward.fill", tint: BrandColors.warning
            )
            .help("The share of eligible tracks replaced before the scrobble threshold. Pauses and interrupted sessions are excluded.")
            ComparisonHistoryMetric(
                title: "Artists", value: extendedInsights.comparison.current.uniqueArtists.formatted(),
                comparison: comparisonText(extendedInsights.comparison.artistDelta), symbol: "music.mic",
                tint: BrandColors.electricBlue)
        }
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
                            colors: [BrandColors.cyan, BrandColors.electricBlue],
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
                            .foregroundStyle(index == 0 ? BrandColors.electricBlue : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(artist.artist)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            ProgressView(
                                value: Double(artist.plays),
                                total: Double(max(summary.topArtists.first?.plays ?? 1, 1))
                            )
                            .tint(index == 0 ? BrandColors.electricBlue : BrandColors.neutral)
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
                columns: [GridItem(.adaptive(minimum: 260, maximum: 520), spacing: 14, alignment: .top)],
                alignment: .leading,
                spacing: 14
            ) {
                RankedInsightCard(title: "Top Tracks", items: extendedInsights.topTracks)
                RankedInsightCard(title: "Top Albums", items: extendedInsights.topAlbums)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 520), spacing: 14, alignment: .top)],
                alignment: .leading,
                spacing: 14
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Listening by Hour", systemImage: "clock")
                        .font(.headline)
                    Chart(extendedInsights.hourlyCounts) { item in
                        BarMark(x: .value("Hour", item.hour), y: .value("Listens", item.plays))
                            .foregroundStyle(BrandColors.electricBlue.gradient)
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
                    Text("Recent activity")
                        .font(.title3.bold())
                    Text("Every track stays private on this Mac")
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
        .presenceCard()
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

    private func isCurrent(_ record: ActivityRecord) -> Bool {
        record.title == model.snapshot.track?.title && record.artist == model.snapshot.track?.artist
    }

    private func comparisonText(_ delta: Int?) -> String {
        guard period != .all else { return "All time" }
        guard let delta else { return "No prior data" }
        return delta == 0 ? "No change" : "\(delta > 0 ? "+" : "")\(delta)"
    }

    private func exportVisibleHistory() {
        exportDocument = HistoryCSVDocument(text: HistoryCSVExporter.csv(records: filteredRecords))
        showingExporter = true
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
                Text(comparison)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(index == 0 ? BrandColors.electricBlue : .secondary)
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

private struct PlatformListenRow: View {
    let item: PlatformListenCount
    let total: Int

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
                .tint(BrandColors.electricBlue)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OutcomeLabel: View {
    let outcome: String

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
        outcome == "Skipped" ? BrandColors.neutral : BrandColors.electricBlue
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
