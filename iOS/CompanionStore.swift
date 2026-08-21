import Foundation
import PresenceFMCore

struct CompanionSnapshot: Codable, Sendable {
    var baseline: CaptureBaseline?
    var cursor: ReconciliationCursor?
    var listens: [CanonicalListen]
    var privateMode: Bool
    var privateModeEffectiveAt: Date?
    var diagnostics: [DiagnosticEntry]

    static let empty = CompanionSnapshot(baseline: nil, cursor: nil, listens: [], privateMode: false, privateModeEffectiveAt: nil, diagnostics: [])
}

struct DiagnosticEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let category: String
    let message: String
    init(category: String, message: String) { id = UUID(); date = .now; self.category = category; self.message = message }
}

actor CompanionStore {
    private let fileURL: URL
    private var snapshot: CompanionSnapshot

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PresenceFMCompanion", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("ledger.json")
        if let data = try? Data(contentsOf: self.fileURL), let decoded = try? JSONDecoder.companion.decode(CompanionSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = .empty
        }
    }

    func current() -> CompanionSnapshot { snapshot }

    func establishBaselineIfNeeded(_ baseline: CaptureBaseline) throws {
        guard snapshot.baseline == nil else { return }; snapshot.baseline = baseline
        snapshot.cursor = ReconciliationCursor(lastCheckedAt: baseline.establishedAt); try persist()
    }

    @discardableResult func ingest(_ evidence: PlaybackEvidence) throws -> CanonicalListen {
        let merger = DefaultEvidenceMerger(); let decision = merger.merge(evidence, into: snapshot.listens)
        let baseline = snapshot.baseline ?? CaptureBaseline(establishedAt: evidence.capturedAt)
        let eligibility = ScrobbleEligibilityPolicy.evaluate(evidence, baseline: baseline)
        let state: ListenState; let reason: ReviewReason?
        switch eligibility {
        case .eligible: state = snapshot.privateMode ? .privateListen : .queued; reason = nil
        case .review(let value): state = .review; reason = value
        case .ineligible: state = .dismissed; reason = nil
        case .listening: state = .listening; reason = nil
        }
        switch decision {
        case .merge(let id):
            let index = snapshot.listens.firstIndex(where: { $0.id == id })!
            var merged = EvidenceReducer.add(evidence, to: snapshot.listens[index])
            if merged.state == .listening || merged.state == .review { merged.state = state; merged.reviewReason = reason }
            snapshot.listens[index] = merged; try persist(); return merged
        case .review(_, let mergeReason):
            let id = CanonicalListenIdentity.make(for: evidence)
            let listen = CanonicalListen(id: id, evidence: [evidence], metadata: evidence.originalMetadata, state: .review, reviewReason: mergeReason)
            snapshot.listens.append(listen); try persist(); return listen
        case .newListen(let id):
            let listen = CanonicalListen(id: id, evidence: [evidence], metadata: evidence.originalMetadata, state: state, reviewReason: reason)
            snapshot.listens.append(listen); try persist(); return listen
        }
    }

    func setCursor(_ cursor: ReconciliationCursor) throws { snapshot.cursor = cursor; try persist() }
    func setState(_ state: ListenState, for id: String, submittedAt: Date? = nil) throws {
        guard let index = snapshot.listens.firstIndex(where: { $0.id == id }) else { return }
        snapshot.listens[index].state = state; snapshot.listens[index].submittedAt = submittedAt; try persist()
    }
    func correct(id: String, title: String, artist: String, album: String?) throws {
        guard let index = snapshot.listens.firstIndex(where: { $0.id == id }) else { return }
        snapshot.listens[index].canonicalMetadata.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.listens[index].canonicalMetadata.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.listens[index].canonicalMetadata.album = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        try persist()
    }
    func setPrivateMode(_ enabled: Bool, effectiveAt: Date = .now) throws {
        snapshot.privateMode = enabled; snapshot.privateModeEffectiveAt = effectiveAt
        if enabled {
            for index in snapshot.listens.indices where [.listening, .queued].contains(snapshot.listens[index].state) {
                snapshot.listens[index].state = .privateListen
            }
        }
        try persist()
    }
    func log(_ category: String, _ message: String) throws {
        snapshot.diagnostics.append(.init(category: category, message: message))
        if snapshot.diagnostics.count > 1_000 { snapshot.diagnostics.removeFirst(snapshot.diagnostics.count - 1_000) }
        try persist()
    }

    func diagnosticsExport() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PresenceFM-iOS-Diagnostics.json")
        let data = try JSONEncoder.pretty.encode(snapshot.diagnostics); try data.write(to: url, options: .atomic); return url
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.pretty.encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder
    }
}
private extension JSONDecoder { static var companion: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder } }
