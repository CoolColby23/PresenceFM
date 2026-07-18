import Foundation

enum HistoryOutcomeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case played = "Played"
    case listened = "Listened"
    case skipped = "Skipped"
    var id: Self { self }
}

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case month = "30 Days"
    case quarter = "90 Days"
    case all = "All Time"
    var id: Self { self }

    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .day, value: -30, to: now)
        case .quarter: calendar.date(byAdding: .day, value: -90, to: now)
        case .all: nil
        }
    }

    var dayCount: Int? {
        switch self { case .week: 7; case .month: 30; case .quarter: 90; case .all: nil }
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
        played = records.filter(\.countsAsListen).count
        skipped = records.filter { $0.outcomeLabel == "Skipped" }.count
        let seconds = records.reduce(0.0) { partial, record in
            partial + max(0, record.listenedTime ?? (record.outcomeLabel == "Played" ? record.duration ?? 0 : 0))
        }
        listeningMinutes = Int((seconds / 60).rounded())

        let playedRecords = records.filter(\.countsAsListen)
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
        let grouped = Dictionary(grouping: records.filter { $0.startedAt >= start && $0.countsAsListen }) {
            calendar.startOfDay(for: $0.startedAt)
        }
        dailyCounts = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DailyListenCount(day: day, plays: grouped[day]?.count ?? 0)
        }
    }
}

struct ListeningMetrics: Equatable {
    let listens: Int
    let minutes: Int
    let uniqueArtists: Int
    let skipRate: Double
}

struct MetricComparison: Equatable {
    let current: ListeningMetrics
    let previous: ListeningMetrics?

    var listenDelta: Int? { previous.map { current.listens - $0.listens } }
    var minuteDelta: Int? { previous.map { current.minutes - $0.minutes } }
    var artistDelta: Int? { previous.map { current.uniqueArtists - $0.uniqueArtists } }
    var skipRateDelta: Double? { previous.map { current.skipRate - $0.skipRate } }
}

struct RankedListen: Identifiable, Equatable {
    let name: String
    let detail: String?
    let plays: Int
    var id: String { "\(name)|\(detail ?? "")" }
}

struct HourlyListenCount: Identifiable, Equatable {
    let hour: Int
    let plays: Int
    var id: Int { hour }
}

struct PlatformListenCount: Identifiable, Equatable {
    let platform: String
    let plays: Int
    var id: String { platform }
}

struct ExtendedListeningInsights {
    let comparison: MetricComparison
    let topTracks: [RankedListen]
    let topAlbums: [RankedListen]
    let hourlyCounts: [HourlyListenCount]
    let platformCounts: [PlatformListenCount]

    @MainActor
    init(records: [ActivityRecord], period: HistoryPeriod, now: Date = .now, calendar: Calendar = .current) {
        let currentStart = period.cutoff(from: now, calendar: calendar)
        let current = records.filter { record in currentStart.map { record.startedAt >= $0 } ?? true }
        let previous: [ActivityRecord]?
        if let days = period.dayCount,
           let start = currentStart,
           let previousStart = calendar.date(byAdding: .day, value: -days, to: start) {
            previous = records.filter { $0.startedAt >= previousStart && $0.startedAt < start }
        } else { previous = nil }
        comparison = MetricComparison(current: Self.metrics(current), previous: previous.map(Self.metrics))

        let played = current.filter(\.countsAsListen)
        topTracks = Self.rank(played) { ($0.title, $0.artist) }
        topAlbums = Self.rank(played.filter { $0.album?.isEmpty == false }) { ($0.album ?? "Unknown Album", $0.artist) }
        let byHour = Dictionary(grouping: played) { calendar.component(.hour, from: $0.startedAt) }
        hourlyCounts = (0..<24).map { HourlyListenCount(hour: $0, plays: byHour[$0]?.count ?? 0) }
        let byPlatform = Dictionary(grouping: played) { $0.platformRaw ?? "Unknown platform" }
        platformCounts = byPlatform.map { PlatformListenCount(platform: $0.key, plays: $0.value.count) }
            .sorted { $0.plays == $1.plays ? $0.platform < $1.platform : $0.plays > $1.plays }
    }

    @MainActor private static func metrics(_ records: [ActivityRecord]) -> ListeningMetrics {
        let played = records.filter(\.countsAsListen)
        let skipped = records.filter { $0.outcomeLabel == "Skipped" }
        let total = played.count + skipped.count
        let seconds = records.reduce(0.0) { $0 + max(0, $1.listenedTime ?? ($1.outcomeLabel == "Played" ? ($1.trackDuration ?? $1.duration ?? 0) : 0)) }
        return ListeningMetrics(
            listens: played.count, minutes: Int((seconds / 60).rounded()),
            uniqueArtists: Set(played.map { $0.artist.localizedLowercase }).count,
            skipRate: total == 0 ? 0 : Double(skipped.count) / Double(total)
        )
    }

    @MainActor private static func rank(
        _ records: [ActivityRecord], key: (ActivityRecord) -> (String, String?)
    ) -> [RankedListen] {
        let grouped = Dictionary(grouping: records) { let value = key($0); return "\(value.0)|\(value.1 ?? "")" }
        return grouped.compactMap { _, values in
            guard let first = values.first else { return nil }
            let value = key(first)
            return RankedListen(name: value.0, detail: value.1, plays: values.count)
        }
        .sorted {
            if $0.plays != $1.plays { return $0.plays > $1.plays }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        .prefix(5).map { $0 }
    }
}

private extension ActivityRecord {
    var countsAsListen: Bool { outcomeLabel == "Played" || outcomeLabel == "Listened" }
}

enum HistoryCSVExporter {
    @MainActor
    static func csv(records: [ActivityRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows: [String] = ["schema_version,id,started_at,finalized_at,title,artist,album,platform,outcome,duration_seconds,listening_seconds,persistent_id"]
        for record in records {
            let duration = (record.trackDuration ?? record.duration).map { String($0) } ?? ""
            let listenedTime = record.listenedTime.map { String($0) } ?? ""
            let fields: [String] = [
                "1", record.id.uuidString, formatter.string(from: record.startedAt),
                record.finalizedAt.map(formatter.string) ?? "", record.title, record.artist,
                record.album ?? "", record.platformRaw ?? "Unknown platform", record.outcomeLabel,
                duration, listenedTime, record.persistentID ?? ""
            ]
            rows.append(fields.map { csvField($0) }.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
