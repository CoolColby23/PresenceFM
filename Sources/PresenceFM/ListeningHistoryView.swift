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
                    description: Text("Play music in Apple Music and your private listening history will appear here.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        summaryGrid
                        activityChart
                        topArtists
                        historyList
                    }.padding(24)
                }
            }
        }
        .navigationTitle("Listening History")
        .searchable(text: $searchText, prompt: "Search title, artist, or album")
        .toolbar {
            ToolbarItemGroup {
                Picker("Period", selection: $period) {
                    ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 240)
                Picker("Outcome", selection: $outcome) {
                    ForEach(HistoryOutcomeFilter.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 110)
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

    private var summaryGrid: some View {
        HStack(spacing: 12) {
            HistoryMetric(title: "Listens", value: summary.played.formatted(), symbol: "play.fill", tint: BrandColors.electricBlue)
            HistoryMetric(title: "Minutes", value: summary.listeningMinutes.formatted(), symbol: "clock.fill", tint: BrandColors.violet)
            HistoryMetric(title: "Skipped", value: summary.skipped.formatted(), symbol: "forward.fill", tint: BrandColors.coral)
            HistoryMetric(title: "Artists", value: Set(filteredRecords.map(\.artist)).count.formatted(), symbol: "music.mic", tint: BrandColors.magenta)
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Last 7 Days").font(.headline)
            Chart(summary.dailyCounts) { item in
                BarMark(x: .value("Day", item.day, unit: .day), y: .value("Listens", item.plays))
                    .foregroundStyle(BrandColors.signal)
                    .cornerRadius(4)
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .frame(height: 170)
            .accessibilityLabel("Listens during the last seven days")
        }.padding(18).presenceCard()
    }

    @ViewBuilder private var topArtists: some View {
        if !summary.topArtists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Artists").font(.headline)
                ForEach(Array(summary.topArtists.enumerated()), id: \.element.id) { index, artist in
                    HStack {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                        Text(artist.artist).lineLimit(1)
                        Spacer()
                        Text("\(artist.plays) \(artist.plays == 1 ? "listen" : "listens")").foregroundStyle(.secondary)
                    }
                }
            }.padding(18).presenceCard()
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Text("\(filteredRecords.count) items").foregroundStyle(.secondary)
            }
            if filteredRecords.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("Adjust the search or filters."))
                    .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRecords) { record in
                        HistoryRow(record: record, currentArtwork: isCurrent(record) ? model.artworkData : nil)
                        if record.id != filteredRecords.last?.id { Divider().padding(.leading, 58) }
                    }
                }
            }
        }.padding(18).presenceCard()
    }

    private var filteredRecords: [ActivityRecord] {
        let cutoff = period.cutoff(from: .now)
        return records.filter { record in
            let matchesPeriod = cutoff.map { record.startedAt >= $0 } ?? true
            let matchesOutcome: Bool = switch outcome {
            case .all: true
            case .played: record.outcomeLabel == "Played"
            case .skipped: record.outcomeLabel == "Skipped"
            }
            let matchesSearch = searchText.isEmpty || [record.title, record.artist, record.album ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesPeriod && matchesOutcome && matchesSearch
        }
    }

    private func isCurrent(_ record: ActivityRecord) -> Bool {
        record.title == model.snapshot.track?.title && record.artist == model.snapshot.track?.artist
    }

    private func exportVisibleHistory() {
        exportDocument = HistoryCSVDocument(text: HistoryCSVExporter.csv(records: filteredRecords))
        showingExporter = true
    }
}

private struct HistoryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.title.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).presenceCard()
    }
}

private struct HistoryRow: View {
    let record: ActivityRecord
    let currentArtwork: Data?
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(data: currentArtwork ?? record.artworkData, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title).font(.headline).lineLimit(1)
                Text(record.album.map { "\(record.artist) • \($0)" } ?? record.artist).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Label(record.outcomeLabel, systemImage: record.outcomeLabel == "Skipped" ? "forward.fill" : "checkmark.circle.fill")
                .font(.caption).foregroundStyle(record.outcomeLabel == "Skipped" ? .secondary : BrandColors.electricBlue)
            Text(record.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption).foregroundStyle(.secondary).frame(width: 105, alignment: .trailing)
        }.padding(.vertical, 10)
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
