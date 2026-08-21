import BackgroundTasks
import Foundation
import MusicKit
import Observation
import PresenceFMCore
import UIKit

@MainActor @Observable
final class CompanionAppModel {
    private(set) var snapshot = CompanionSnapshot.empty
    private(set) var nowPlaying: PlaybackEvidence?
    private(set) var lastFMUsername: String?
    private(set) var musicAuthorization = MusicAuthorization.currentStatus
    private(set) var cloudStatus = "Preparing"
    private(set) var hasLastFMCredentials = false
    private(set) var hasPendingLastFMAuthorization = false
    var statusMessage: String?
    var presentedEditor: CanonicalListen?
    var diagnosticsURL: URL?

    private let configuration = CompanionBuildConfiguration.current
    private let keychain = CompanionKeychain()
    private let store = CompanionStore()
    private var source: AppleMusicEvidenceSource?
    private var lastFM: CompanionLastFMClient?
    private var cloud: CloudSubmissionCoordinator?
    private var pollTask: Task<Void, Never>?
    private var lastNowPlayingID: String?

    var history: [CanonicalListen] {
        snapshot.listens.filter { $0.state != .dismissed }.sorted {
            ($0.canonicalMetadata.startedAt ?? .distantPast) > ($1.canonicalMetadata.startedAt ?? .distantPast)
        }
    }
    var reviewItems: [CanonicalListen] { history.filter { $0.state == .review } }
    var needsOnboarding: Bool { lastFMUsername == nil }
    var isReadyForCapture: Bool { lastFMUsername != nil && musicAuthorization == .authorized }

    func start() async {
        let deviceID: UUID
        do {
            deviceID = try await keychain.stableDeviceID()
        } catch {
            show(error)
            return
        }
        let source = AppleMusicEvidenceSource(deviceID: deviceID); self.source = source
        let credentials = await storedLastFMCredentials()
        hasLastFMCredentials = credentials.isConfigured
        let lastFM = CompanionLastFMClient(credentials: credentials, keychain: keychain); self.lastFM = lastFM
        hasPendingLastFMAuthorization = await lastFM.hasPendingAuthorization()
        let cloud = CloudSubmissionCoordinator(
            containerIdentifier: configuration.cloudContainerIdentifier, deviceID: deviceID, localOnly: !configuration.isCloudConfigured
        ) { [keychain] in await keychain.value(for: .lastFMUsername) }
        self.cloud = cloud
        snapshot = await store.current(); lastFMUsername = await lastFM.username()
        do {
            try await cloud.prepare()
            cloudStatus = configuration.isCloudConfigured ? "Connected" : "Local only"
        } catch {
            cloudStatus = "Unavailable — using local queue"
            try? await store.log("cloud", "Cloud coordination unavailable during startup.")
        }
        await source.beginNotifications { [weak self] in Task { @MainActor in await self?.captureNow() } }
        guard lastFMUsername != nil else { return }
        if musicAuthorization == .authorized {
            do { try await establishBaselineAndReconcile() } catch { try? await store.log("reconcile", "Startup reconciliation deferred.") }
        }
        scheduleBackgroundRefresh()
        await drainQueue()
        startPolling()
    }

    func requestMusicAccess() async {
        guard let source else { return }; musicAuthorization = await source.requestAuthorization()
        if musicAuthorization == .authorized { do { try await establishBaselineAndReconcile() } catch { show(error) } }
    }

    func captureNow() async {
        guard musicAuthorization == .authorized, let source, let evidence = await source.currentEvidence() else { nowPlaying = nil; return }
        nowPlaying = evidence
        do {
            let listen = try await store.ingest(evidence); try await cloud?.sync(evidence: evidence, listen: listen)
            try await store.log("capture", "Observed \(evidence.sourceTrackID ?? "metadata-only") as \(listen.state.rawValue).")
            if lastNowPlayingID != listen.id { lastNowPlayingID = listen.id; try? await lastFM?.updateNowPlaying(listen.canonicalMetadata) }
            if listen.state == .queued { await submit(listen) }
            await reload()
        } catch { show(error) }
    }

    func reconcile() async { do { try await establishBaselineAndReconcile() } catch { show(error) } }

    func approve(_ listen: CanonicalListen) async {
        do {
            try await store.setState(.queued, for: listen.id); await reload();
            if let updated = history.first(where: { $0.id == listen.id }) { await submit(updated) }
        } catch { show(error) }
    }
    func dismiss(_ listen: CanonicalListen) async { do { try await store.setState(.dismissed, for: listen.id); await reload() } catch { show(error) } }
    func approveAll() async { for item in reviewItems where item.canonicalMetadata.startedAt != nil { await approve(item) } }
    func dismissAll() async { for item in reviewItems { await dismiss(item) } }
    func saveCorrection(id: String, title: String, artist: String, album: String?) async {
        do { try await store.correct(id: id, title: title, artist: artist, album: album); await reload(); presentedEditor = nil } catch { show(error) }
    }

    func setPrivateMode(_ enabled: Bool) async {
        let date = Date()
        do { try await cloud?.setPrivateMode(enabled, effectiveAt: date); try await store.setPrivateMode(enabled, effectiveAt: date); await reload() } catch {
            show(error)
        }
    }

    func connectLastFM() async {
        guard let lastFM else { return }
        do {
            let url = try await lastFM.authorizationURL()
            hasPendingLastFMAuthorization = true
            await UIApplication.shared.open(url)
        } catch { show(error) }
    }

    func handleLastFMCallback(_ url: URL) async {
        guard let lastFM else { return }
        do {
            try await lastFM.acceptCallback(url)
            hasPendingLastFMAuthorization = true
            await finishLastFMConnection()
        } catch { show(error) }
    }

    func saveLastFMCredentials(apiKey: String, sharedSecret: String) async -> Bool {
        let credentials = CompanionLastFMCredentials(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            sharedSecret: sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard credentials.isConfigured else {
            statusMessage = "Enter both the Last.fm API key and shared secret."
            return false
        }
        do {
            try await keychain.set(credentials.apiKey, for: .lastFMAPIKey)
            try await keychain.set(credentials.sharedSecret, for: .lastFMSharedSecret)
            await lastFM?.updateCredentials(credentials)
            hasLastFMCredentials = true
            return true
        } catch {
            show(error)
            return false
        }
    }

    func clearLastFMCredentials() async {
        do {
            try await disconnectLastFM()
            try await keychain.set(nil, for: .lastFMAPIKey)
            try await keychain.set(nil, for: .lastFMSharedSecret)
            await lastFM?.updateCredentials(.init(apiKey: "", sharedSecret: ""))
            hasLastFMCredentials = false
        } catch { show(error) }
    }

    func finishLastFMConnection() async {
        do {
            lastFMUsername = try await lastFM?.completeAuthorization()
            hasPendingLastFMAuthorization = false
            statusMessage = "Connected to Last.fm."
            if musicAuthorization == .authorized { try await establishBaselineAndReconcile() }
            scheduleBackgroundRefresh()
            await drainQueue()
            startPolling()
        } catch { show(error) }
    }
    func disconnectLastFM() async {
        do {
            try await lastFM?.disconnect(); lastFMUsername = nil; hasPendingLastFMAuthorization = false
        } catch { show(error) }
    }
    func exportDiagnostics() async { do { diagnosticsURL = try await store.diagnosticsExport() } catch { show(error) } }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "fm.presence.companion.refresh")
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func establishBaselineAndReconcile() async throws {
        guard let source else { return }
        if snapshot.baseline == nil { try await store.establishBaselineIfNeeded(try await source.establishBaseline()) }
        await reload(); let cursor = snapshot.cursor ?? .init(lastCheckedAt: snapshot.baseline?.establishedAt ?? .now)
        let result = try await source.reconcile(since: cursor)
        for evidence in result.evidence { _ = try await store.ingest(evidence) }
        try await store.setCursor(result.cursor); try await store.log("reconcile", "Processed \(result.evidence.count) recently played candidates.")
        await reload()
        scheduleBackgroundRefresh()
        await drainQueue()
    }

    private func drainQueue() async {
        await reload()
        for listen in snapshot.listens.filter({ $0.state == .queued }) { await submit(listen) }
    }

    private func submit(_ listen: CanonicalListen) async {
        guard !snapshot.privateMode, let cloud, let lastFM else { return }
        do {
            let lease = try await cloud.acquireLease(for: listen.id); try await store.setState(.submitting, for: listen.id)
            do {
                try await lastFM.scrobble(listen.canonicalMetadata); let date = Date()
                try await cloud.complete(lease, result: .accepted(date)); try await store.setState(.submitted, for: listen.id, submittedAt: date)
            } catch {
                try? await cloud.complete(lease, result: .deferred("Submission failed; retry is required.")); try await store.setState(.queued, for: listen.id)
                throw error
            }
            await reload()
        } catch { try? await store.log("submission", "Deferred \(listen.id): \(String(describing: type(of: error)))."); show(error) }
    }

    private func startPolling() {
        pollTask?.cancel();
        pollTask = Task { [weak self] in
            while !Task.isCancelled { await self?.captureNow(); try? await Task.sleep(for: .seconds(1)) }
        }
    }
    private func storedLastFMCredentials() async -> CompanionLastFMCredentials {
        let stored = CompanionLastFMCredentials(
            apiKey: await keychain.value(for: .lastFMAPIKey) ?? "",
            sharedSecret: await keychain.value(for: .lastFMSharedSecret) ?? ""
        )
        if stored.isConfigured { return stored }
        return .init(apiKey: configuration.apiKey, sharedSecret: configuration.sharedSecret)
    }
    private func reload() async { snapshot = await store.current() }
    private func show(_ error: Error) {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            statusMessage = description
        } else {
            let description = (error as NSError).localizedDescription
            statusMessage =
                description == "The operation couldn’t be completed. (Swift.Error error 1.)"
                ? "PresenceFM could not complete that action. Try again, then export diagnostics if it continues."
                : description
        }
    }
}
