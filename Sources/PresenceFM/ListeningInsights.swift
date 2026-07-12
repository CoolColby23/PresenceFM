import Foundation

enum HistoryOutcomeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case played = "Played"
    case skipped = "Skipped"
    var id: Self { self }
}

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case month = "30 Days"
    case all = "All Time"
    var id: Self { self }

    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .day, value: -30, to: now)
        case .all: nil
        }
    }
}

struct ArtistPlayCount: Identifiable, Equatable {
    var id: String { artist }
    let artist: String
    let plays: Int
}

struct DailyListenCount: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    let plays: Int
}

struct ListeningSummary {
    let total: Int
    let played: Int
    let skipped: Int
    let listeningMinutes: Int
    let topArtists: [ArtistPlayCount]
    let dailyCounts: [DailyListenCount]

    @MainActor
    init(records: [ActivityRecord], now: Date = .now, calendar: Calendar = .current) {
        total = records.count
        played = records.filter { $0.outcomeLabel == "Played" }.count
        skipped = records.filter { $0.outcomeLabel == "Skipped" }.count
        let seconds = records.reduce(0.0) { partial, record in
            partial + max(0, record.listenedTime ?? (record.outcomeLabel == "Played" ? record.duration ?? 0 : 0))
        }
        listeningMinutes = Int((seconds / 60).rounded())

        let playedRecords = records.filter { $0.outcomeLabel == "Played" }
        let groupedArtists: [String: [ActivityRecord]] = Dictionary(grouping: playedRecords) { $0.artist }
        var artistCounts: [ArtistPlayCount] = groupedArtists.map { entry in
            ArtistPlayCount(artist: entry.key, plays: entry.value.count)
        }
        artistCounts.sort { lhs, rhs in
            if lhs.plays != rhs.plays { return lhs.plays > rhs.plays }
            return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
        }
        topArtists = Array(artistCounts.prefix(5))

        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
        let grouped = Dictionary(grouping: records.filter { $0.startedAt >= start && $0.outcomeLabel == "Played" }) {
            calendar.startOfDay(for: $0.startedAt)
        }
        dailyCounts = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DailyListenCount(day: day, plays: grouped[day]?.count ?? 0)
        }
    }
}

enum HistoryCSVExporter {
    @MainActor
    static func csv(records: [ActivityRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows: [String] = ["Date,Title,Artist,Album,Outcome,Duration Seconds,Listening Seconds"]
        for record in records {
            let duration = record.duration.map { String($0) } ?? ""
            let listenedTime = record.listenedTime.map { String($0) } ?? ""
            let fields: [String] = [
                formatter.string(from: record.startedAt), record.title, record.artist,
                record.album ?? "", record.outcomeLabel, duration, listenedTime
            ]
            rows.append(fields.map { csvField($0) }.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
