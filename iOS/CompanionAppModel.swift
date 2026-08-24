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
    private(set) var lastFMTracks: [CompanionLastFMTrack] = []
    private(set) var isLoadingLastFMHistory = false
    private(set) var isImportingAppleMusicHistory = false
    private(set) var lastAppleMusicImportCount: Int?
    private(set) var captureIssue: String?
    private(set) var readinessAcknowledged = false
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
    var historicalImportItems: [CanonicalListen] {
        reviewItems.filter { $0.reviewReason == .historicalImport }
    }
    var needsOnboarding: Bool { lastFMUsername == nil || !readinessAcknowledged }
    var isReadyForCapture: Bool { lastFMUsername != nil && musicAuthorization == .authorized }

    var captureStatus: CaptureStatusPresentation {
        if lastFMUsername == nil {
            return CaptureStatusPresentation(
                status: .needsAttention,
                headline: "Connect Last.fm",
                explanation: "Connect an account before PresenceFM can submit scrobbles.",
                recoveryAction: .reconnectLastFM
            )
        }
        if musicAuthorization != .authorized {
            // Once access is denied, `MusicAuthorization.request()` resolves to
            // denied again without prompting, so the only real fix is Settings.
            let denied = musicAuthorization == .denied || musicAuthorization == .restricted
            return CaptureStatusPresentation(
                status: .needsAttention,
                headline: "Apple Music access needed",
                explanation: denied
                    ? "Music access is turned off for PresenceFM. Turn it back on in Settings so plays can be identified."
                    : "Allow Music access so PresenceFM can identify and qualify plays.",
                recoveryAction: denied ? .openSettings : .grantPlaybackPermission
            )
        }
        if snapshot.privateMode {
            return CaptureStatusPresentation(
                status: .privateMode,
                headline: "Private Mode is on",
                explanation: "PresenceFM can detect playback, but nothing is sent to Last.fm.",
                recoveryAction: .disablePrivateMode
            )
        }
        if let captureIssue {
            return CaptureStatusPresentation(
                status: .needsAttention,
                headline: "Capture needs attention",
                explanation: captureIssue,
                recoveryAction: .recheckNow
            )
        }
        guard let evidence = nowPlaying else {
            if let submitted = history.first(where: { $0.state == .submitted }) {
                return CaptureStatusPresentation(
                    status: .submitted,
                    headline: "Last scrobble submitted",
                    explanation: "Open PresenceFM while listening for the strongest capture. iOS may pause background observation.",
                    timestamp: submitted.submittedAt ?? submitted.canonicalMetadata.startedAt
                )
            }
            return CaptureStatusPresentation(
                status: .detecting,
                headline: "Ready for playback",
                explanation: "No song is detected right now. iOS background suspension is normal, and recent plays are checked when the app runs."
            )
        }
        let listen = history.first { item in
            item.evidence.contains { prior in
                prior.id == evidence.id || (prior.sourceTrackID != nil && prior.sourceTrackID == evidence.sourceTrackID)
            }
        }
        switch listen?.state {
        case .queued, .submitting:
            return CaptureStatusPresentation(
                status: .queued,
                headline: "Scrobble queued",
                explanation: "The play is safe on this iPhone and will be retried automatically.",
                progress: 1,
                timestamp: evidence.capturedAt,
                recoveryAction: .retryQueue
            )
        case .submitted:
            return CaptureStatusPresentation(
                status: .submitted,
                headline: "Scrobbled to Last.fm",
                explanation: "This play was accepted by Last.fm.",
                progress: 1,
                timestamp: listen?.submittedAt ?? evidence.capturedAt
            )
        case .privateListen:
            return CaptureStatusPresentation(
                status: .privateMode,
                headline: "This play stayed private",
                explanation: "Private Mode prevented submission to Last.fm.",
                timestamp: evidence.capturedAt,
                recoveryAction: .disablePrivateMode
            )
        case .review:
            return CaptureStatusPresentation(
                status: .needsAttention,
                headline: "This play needs review",
                explanation: reviewExplanation(listen?.reviewReason),
                timestamp: evidence.capturedAt,
                recoveryAction: .recheckNow
            )
        case .failed:
            if let reason = listen?.failureReason {
                return CaptureStatusPresentation(
                    status: .excluded,
                    headline: "Last.fm would not accept this play",
                    explanation: "\(reason) Editing the track details lets PresenceFM try again.",
                    timestamp: evidence.capturedAt
                )
            }
            return CaptureStatusPresentation(
                status: .needsAttention,
                headline: "Submission failed",
                explanation: "The play is still stored locally and can be retried.",
                timestamp: evidence.capturedAt,
                recoveryAction: .retryQueue
            )
        case .dismissed:
            return CaptureStatusPresentation(
                status: .excluded,
                headline: "This play will not scrobble",
                explanation: "The track did not meet Last.fm eligibility requirements.",
                timestamp: evidence.capturedAt
            )
        case .listening, .none:
            let baseline = snapshot.baseline ?? CaptureBaseline(establishedAt: evidence.capturedAt)
            switch ScrobbleEligibilityPolicy.evaluate(evidence, baseline: baseline) {
            case .listening(let progress, let remaining):
                return CaptureStatusPresentation(
                    status: .progressing,
                    headline: "Listening toward a scrobble",
                    explanation: "Keep playing for \(Self.durationText(remaining)) to make this track eligible.",
                    progress: progress,
                    timestamp: evidence.capturedAt
                )
            case .eligible:
                return CaptureStatusPresentation(status: .queued, headline: "Ready to scrobble", explanation: "The listening threshold has been reached.", progress: 1, timestamp: evidence.capturedAt)
            case .ineligible(let reason):
                return CaptureStatusPresentation(status: .excluded, headline: "This play will not scrobble", explanation: reason, timestamp: evidence.capturedAt)
            case .review(let reason):
                return CaptureStatusPresentation(status: .needsAttention, headline: "This play needs review", explanation: reviewExplanation(reason), timestamp: evidence.capturedAt, recoveryAction: .recheckNow)
            }
        }
    }

    var recentCaptureActivity: [CaptureStatusPresentation] {
        history.prefix(5).map { listen in
            let explanation: String
            let status: CaptureStatusPresentation.Status
            switch listen.state {
            case .submitted: status = .submitted; explanation = "Submitted to Last.fm"
            case .failed where listen.failureReason != nil:
                status = .excluded; explanation = listen.failureReason ?? ""
            case .queued, .submitting, .failed: status = .queued; explanation = "Saved locally for retry"
            case .review: status = .needsAttention; explanation = reviewExplanation(listen.reviewReason)
            case .privateListen: status = .privateMode; explanation = "Kept private"
            case .dismissed: status = .excluded; explanation = "Did not meet eligibility requirements"
            case .listening: status = .progressing; explanation = "Listening activity detected"
            }
            return CaptureStatusPresentation(
                status: status,
                headline: listen.canonicalMetadata.title,
                explanation: explanation,
                timestamp: listen.submittedAt ?? listen.canonicalMetadata.startedAt
            )
        }
    }

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
        if let stored = UserDefaults.standard.object(forKey: "companionReadinessAcknowledged") as? Bool {
            readinessAcknowledged = stored
        } else {
            readinessAcknowledged = lastFMUsername != nil
        }
        do {
            try await cloud.prepare()
            cloudStatus = configuration.isCloudConfigured ? "Connected" : "Local only"
        } catch {
            cloudStatus = "Unavailable — using local queue"
            try? await store.log("cloud", "Cloud coordination unavailable during startup.")
        }
        await source.beginNotifications { [weak self] in Task { @MainActor in await self?.captureNow() } }
        guard lastFMUsername != nil else { return }
        await refreshLastFMHistory()
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
            captureIssue = nil
        } catch {
            captureIssue = friendlyDescription(for: error)
            try? await store.log("capture", "Passive capture deferred: \(String(describing: type(of: error))).")
        }
    }

    func reconcile(reportErrors: Bool = true) async {
        do {
            try await establishBaselineAndReconcile()
            captureIssue = nil
        } catch {
            captureIssue = friendlyDescription(for: error)
            try? await store.log("reconcile", "Passive reconciliation deferred: \(String(describing: type(of: error))).")
            if reportErrors { show(error) }
        }
    }

    func approve(_ listen: CanonicalListen, refreshHistory: Bool = true) async {
        do {
            try await store.setState(.queued, for: listen.id); await reload();
            if let updated = history.first(where: { $0.id == listen.id }) {
                await submit(updated, refreshHistory: refreshHistory)
            }
        } catch { show(error) }
    }
    func dismiss(_ listen: CanonicalListen) async { do { try await store.setState(.dismissed, for: listen.id); await reload() } catch { show(error) } }
    func approveAll() async { for item in reviewItems where item.canonicalMetadata.startedAt != nil { await approve(item) } }
    func approveHistoricalImports(ids: Set<String>) async {
        for item in historicalImportItems where ids.contains(item.id) {
            await approve(item, refreshHistory: false)
        }
        await refreshLastFMHistory()
    }
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
            await disconnectLastFM()
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
            await refreshLastFMHistory()
            if musicAuthorization == .authorized { try await establishBaselineAndReconcile() }
            scheduleBackgroundRefresh()
            await drainQueue()
            startPolling()
        } catch { show(error) }
    }
    func refreshLastFMHistory() async {
        guard let username = lastFMUsername, let lastFM, !isLoadingLastFMHistory else { return }
        isLoadingLastFMHistory = true
        defer { isLoadingLastFMHistory = false }
        do {
            lastFMTracks = try await lastFM.recentTracks(username: username)
        } catch {
            if lastFMTracks.isEmpty { show(error) }
        }
    }
    func disconnectLastFM() async {
        do {
            try await lastFM?.disconnect(); lastFMUsername = nil; hasPendingLastFMAuthorization = false
            readinessAcknowledged = false
            UserDefaults.standard.set(false, forKey: "companionReadinessAcknowledged")
        } catch { show(error) }
    }
    func exportDiagnostics() async { do { diagnosticsURL = try await store.diagnosticsExport() } catch { show(error) } }

    func importAvailableAppleMusicHistory() async {
        guard !isImportingAppleMusicHistory else { return }
        if musicAuthorization != .authorized {
            await requestMusicAccess()
            guard musicAuthorization == .authorized else { return }
        }
        guard let source else { return }
        isImportingAppleMusicHistory = true
        defer { isImportingAppleMusicHistory = false }
        do {
            let existingIDs = Set(snapshot.listens.map(\.id))
            let result = try await source.reconcile(since: .init(lastCheckedAt: .distantPast))
            for evidence in result.evidence { _ = try await store.ingest(evidence) }
            try await store.setCursor(result.cursor)
            await reload()
            await refreshLastFMHistory()
            let remoteDuplicates = historicalImportItems.filter(isLikelyOnLastFM)
            for duplicate in remoteDuplicates { try await store.setState(.dismissed, for: duplicate.id) }
            await reload()
            lastAppleMusicImportCount = Set(historicalImportItems.map(\.id)).subtracting(existingIDs).count
            try await store.log("history-import", "Found \(result.evidence.count) MusicKit history candidates.")
        } catch {
            captureIssue = friendlyDescription(for: error)
            show(error)
        }
    }

    func completeReadiness() {
        readinessAcknowledged = true
        UserDefaults.standard.set(true, forKey: "companionReadinessAcknowledged")
    }

    func performCaptureRecovery(_ action: CaptureStatusPresentation.RecoveryAction) async {
        switch action {
        case .grantPlaybackPermission:
            await requestMusicAccess()
        case .reconnectLastFM:
            await connectLastFM()
        case .retryQueue:
            await drainQueue()
        case .disablePrivateMode:
            await setPrivateMode(false)
        case .recheckNow:
            await reconcile()
        case .openSettings:
            // Nothing in-app to open: the states that offer this are resolved in
            // iOS Settings, so the button is only shown when it can lead there.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
    }

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

    private func submit(_ listen: CanonicalListen, refreshHistory: Bool = true) async {
        guard !snapshot.privateMode, let cloud, let lastFM else { return }
        do {
            let lease = try await cloud.acquireLease(for: listen.id); try await store.setState(.submitting, for: listen.id)
            do {
                try await lastFM.scrobble(listen.canonicalMetadata); let date = Date()
                try await cloud.complete(lease, result: .accepted(date)); try await store.setState(.submitted, for: listen.id, submittedAt: date)
                if refreshHistory { await refreshLastFMHistory() }
            } catch let rejection as CompanionLastFMError where rejection.isTerminal {
                // Retrying cannot change the outcome, so the play stops here with
                // the reason attached instead of cycling through the queue forever.
                try? await cloud.complete(lease, result: .deferred(rejection.localizedDescription))
                try await store.setState(.failed, for: listen.id, failureReason: rejection.localizedDescription)
                throw rejection
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
        statusMessage = friendlyDescription(for: error)
    }
    private func friendlyDescription(for error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription,
            !description.isEmpty, description != "Unknown error"
        {
            return description
        }
        let description = (error as NSError).localizedDescription
        if description == "Unknown error" || description == "The operation couldn’t be completed. (Swift.Error error 1.)" {
            return "Apple Music history is temporarily unavailable. PresenceFM will retry automatically."
        }
        return description
    }

    private func reviewExplanation(_ reason: ReviewReason?) -> String {
        switch reason {
        case .missingTimestamp: "A reliable play time was unavailable."
        case .missingDuration: "The track duration was unavailable."
        case .insufficientPlayTime: "PresenceFM could not verify enough listening time."
        case .ambiguousDuplicate: "This play may duplicate another captured play."
        case .conflictingMetadata: "Music reported conflicting track details."
        case .beforeBaseline: "The play began before capture was established."
        case .historicalImport: "Apple Music reports this as recently played. Select it to scrobble it."
        case .unrecognized: "This play was flagged by a newer version of PresenceFM."
        case .none: "PresenceFM needs confirmation before submitting this play."
        }
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    private func isLikelyOnLastFM(_ listen: CanonicalListen) -> Bool {
        guard let startedAt = listen.canonicalMetadata.startedAt else { return false }
        let title = listen.canonicalMetadata.title.presenceNormalized
        let artist = listen.canonicalMetadata.artist.presenceNormalized
        let tolerance = max(180, (listen.canonicalMetadata.duration ?? 0) + 120)
        return lastFMTracks.contains { track in
            guard !track.isNowPlaying, let playedAt = track.playedAt else { return false }
            return track.title.presenceNormalized == title
                && track.artist.presenceNormalized == artist
                && abs(playedAt.timeIntervalSince(startedAt)) <= tolerance
        }
    }
}
