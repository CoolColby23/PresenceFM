import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftData
import UserNotifications

@MainActor @Observable
final class AppModel {
    var snapshot = PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: .now, confidence: .high)
    var activeSession: PlaybackSession?
    var recentSessions: [PlaybackSession] = []
    var musicStatus: ServiceStatus = .connecting { didSet { recordHealth(playbackIntegrationID, musicStatus) } }
    var discordStatus: ServiceStatus = .disabled { didSet { recordHealth(.discord, discordStatus) } }
    var lastFMStatus: ServiceStatus = .disabled { didSet { recordHealth(.lastFM, lastFMStatus) } }
    var ytmDesktopStatus: ServiceStatus = .disabled { didSet { recordHealth(.youtubeMusic, ytmDesktopStatus) } }
    var persistenceIssue: String?
    var usingTemporaryStore = false
    var persistenceRecoveryStatus = ""
    var diagnosticCopyStatus = ""
    var onboardingPresented: Bool
    var selectedSection: DashboardSection = .nowPlaying
    var credentialDraft = CredentialDraft()
    var lastFMUsername = ""
    var hasStoredLastFMCredentials = false
    var artworkData: Data?
    var discordArtworkURL: URL?
    let preferences: Preferences

    @ObservationIgnored let store: PersistenceStore
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let credentials = CredentialStore()
    @ObservationIgnored private lazy var monitor = PlaybackMonitor(credentials: credentials, clock: clock)
    @ObservationIgnored private let tracker = PlaybackSessionTracker()
    @ObservationIgnored private lazy var artwork = ArtworkService(clock: clock)
    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private lazy var discord = DiscordPresenceClient(applicationID: preferences.discordApplicationID)
    @ObservationIgnored private lazy var lastFM = LastFMClient(credentials: credentials, clock: clock)
    @ObservationIgnored private let ytmDesktop = YTMDesktopClient()
    @ObservationIgnored private lazy var queue = ScrobbleQueue(store: store, client: lastFM, clock: clock)
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var privacyTask: Task<Void, Never>?
    @ObservationIgnored private var pendingScrobbleSessionIDs: Set<UUID> = []
    @ObservationIgnored private var sectionObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    init(
        store: PersistenceStore,
        preferences: Preferences = .shared,
        notifications: NotificationCoordinator = NotificationCoordinator(),
        clock: any AppClock = SystemAppClock()
    ) {
        self.store = store
        self.preferences = preferences
        self.notifications = notifications
        self.clock = clock
        onboardingPresented = !preferences.onboardingComplete
        discordStatus = preferences.discordEnabled ? .connecting : .disabled
        lastFMStatus = preferences.lastFMEnabled ? .connecting : .disabled
        schedulePrivacyExpiration()
        sectionObserver = NotificationCenter.default.addObserver(
            forName: .presenceFMOpenSection,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let name = notification.userInfo?["section"] as? String,
                  let section = DashboardSection(rawValue: name) else { return }
            Task { @MainActor in self?.selectedSection = section; NSApp.activate() }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        queue.onStuck = { [weak self] title in
            Task { @MainActor in
                await self?.notifications.notifyOnce(
                    key: "queue-stuck",
                    title: "Scrobble still queued",
                    body: "\(title) could not be submitted after several attempts.",
                    section: .queue
                )
            }
        }
        queue.onCapacity = { [weak self] message in
            Task { @MainActor in
                self?.persistenceIssue = message
                await self?.notifications.notifyOnce(
                    key: "queue-capacity", title: "Scrobble queue needs attention",
                    body: message, section: .queue
                )
            }
        }
        store.onError = { [weak self] error in self?.persistenceIssue = error.localizedDescription }
        queue.start()
        monitoringTask = Task {
            await monitor.setEnabledProviders(preferences.enabledPlaybackProviders)
            let stream = await monitor.snapshots()
            for await value in stream {
                let changedTrack = snapshot.track?.identity != value.track?.identity
                let previousArtworkData = artworkData
                snapshot = value
                if changedTrack {
                    artworkTask?.cancel()
                    artworkData = nil
                    discordArtworkURL = nil
                }
                musicStatus = value.confidence == .low ? .awaitingPermission : .connected
                await handle(
                    await tracker.ingest(value),
                    finalizedArtworkData: changedTrack ? previousArtworkData : artworkData
                )
                // Publish the new metadata immediately. Artwork is allowed to arrive in a
                // second update so a catalog lookup never delays the song transition.
                await updateDiscord()
                if changedTrack { await updateArtwork(for: value.track) }
                await updateOperationalNotifications()
            }
        }
        Task { await loadCredentials(); await queue.process() }
    }

    func shutdown() {
        guard started else { return }
        started = false
        monitoringTask?.cancel()
        artworkTask?.cancel()
        queue.stop()
        privacyTask?.cancel()
        Task {
            if let session = await tracker.shutdown() {
                await MainActor.run { finalize(session, artworkData: artworkData) }
            }
            await discord.clear(); await monitor.stop()
        }
    }

    func setPrivate(until: Date?) {
        preferences.privateMode = true
        preferences.privateUntil = until
        schedulePrivacyExpiration()
        Task { await discord.clear() }
    }

    func endPrivateMode() {
        privacyTask?.cancel()
        preferences.privateMode = false; preferences.privateUntil = nil
        Task { await updateDiscord(); await updateOperationalNotifications() }
    }

    func saveCredentials() async {
        do {
            preferences.discordApplicationID = credentialDraft.discordApplicationID
            await discord.setApplicationID(credentialDraft.discordApplicationID)
            let key = credentialDraft.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = credentialDraft.lastFMSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { try await credentials.set(key, for: .lastFMAPIKey) }
            if !secret.isEmpty { try await credentials.set(secret, for: .lastFMSecret) }
            let storedKey = await credentials.value(for: .lastFMAPIKey)
            let storedSecret = await credentials.value(for: .lastFMSecret)
            hasStoredLastFMCredentials = storedKey?.isEmpty == false && storedSecret?.isEmpty == false
            store.log("security", "Credentials updated")
        } catch { store.log("security", error.localizedDescription) }
    }

    func beginLastFMAuthorization() async {
        await saveCredentials()
        do { NSWorkspace.shared.open(try await lastFM.beginAuthorization()); lastFMStatus = .connecting }
        catch { updateLastFMStatus(for: error) }
    }

    func completeLastFMAuthorization() async {
        do {
            lastFMUsername = try await lastFM.completeAuthorization()
            preferences.lastFMEnabled = true
            lastFMStatus = .connected
            queue.start()
            await queue.process()
        }
        catch { updateLastFMStatus(for: error) }
    }

    func disconnectLastFM() async {
        try? await credentials.remove(.lastFMAuthToken)
        try? await credentials.remove(.lastFMSessionKey)
        try? await credentials.remove(.lastFMUsername)
        lastFMUsername = ""
        preferences.lastFMEnabled = false
        lastFMStatus = .disabled
        store.log("lastfm", "Account disconnected")
    }

    func connectYTMDesktop() async {
        ytmDesktopStatus = .connecting
        do {
            let token = try await ytmDesktop.authorize()
            try await credentials.set(token, for: .ytmDesktopToken)
            ytmDesktopStatus = .connected
            store.log("youtube-music", "YTMDesktop connected")
        } catch {
            ytmDesktopStatus = .failed(error.localizedDescription)
            store.log("youtube-music", error.localizedDescription)
        }
    }

    func disconnectYTMDesktop() async {
        try? await credentials.remove(.ytmDesktopToken)
        ytmDesktopStatus = .disabled
        store.log("youtube-music", "YTMDesktop disconnected")
    }

    func completeOnboarding() {
        preferences.onboardingComplete = true
        onboardingPresented = false
        if preferences.privateMode { endPrivateMode() }
    }

    func requestNotifications() async {
        _ = await notifications.requestAuthorization()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            preferences.launchAtLogin = enabled
        } catch { store.log("login", error.localizedDescription) }
    }

    private func loadCredentials() async {
        credentialDraft.discordApplicationID = preferences.discordApplicationID
        credentialDraft.lastFMAPIKey = await credentials.value(for: .lastFMAPIKey) ?? ""
        let storedSecret = await credentials.value(for: .lastFMSecret)
        hasStoredLastFMCredentials = !credentialDraft.lastFMAPIKey.isEmpty && storedSecret?.isEmpty == false
        lastFMUsername = await credentials.value(for: .lastFMUsername) ?? ""
        discordStatus = (credentialDraft.discordApplicationID.isEmpty && !ReleaseConfiguration.hasDiscordConfiguration) ? .disabled : .connecting
        lastFMStatus = preferences.lastFMEnabled ? (lastFMUsername.isEmpty ? .authorizationExpired : .connected) : .disabled
        ytmDesktopStatus = await credentials.value(for: .ytmDesktopToken) == nil ? .disabled : .connected
    }

    private func handle(
        _ events: [PlaybackSessionTracker.Event],
        finalizedArtworkData: Data?
    ) async {
        for event in events {
            switch event {
            case .started(let session):
                activeSession = session
                if preferences.lastFMEnabled && preferences.sendNowPlaying && !isPrivate {
                    Task { [weak self] in
                        guard let self else { return }
                        do { try await self.lastFM.updateNowPlaying(session); self.lastFMStatus = .connected }
                        catch { self.updateLastFMStatus(for: error) }
                    }
                }
            case .updated(let session): activeSession = session
            // Reaching Last.fm's eligibility threshold marks the listen as ready, but
            // submitting while the same track is still "now playing" makes Last.fm
            // render duplicate rows. Submit once playback actually finishes instead.
            case .eligible(let session):
                activeSession = session
                if preferences.lastFMEnabled && !isPrivate {
                    pendingScrobbleSessionIDs.insert(session.id)
                }
            case .finalized(let session): finalize(session, artworkData: finalizedArtworkData)
            case .none: break
            }
        }
    }

    private func finalize(_ session: PlaybackSession, artworkData: Data?) {
        let wasApprovedAtEligibility = pendingScrobbleSessionIDs.remove(session.id) != nil
        if session.outcome == .played, wasApprovedAtEligibility,
           preferences.lastFMEnabled, !isPrivate {
            queue.enqueue(session)
        }
        activeSession = nil; recentSessions.insert(session, at: 0)
        if recentSessions.count > 200 { recentSessions.removeLast() }
        store.record(session, artworkData: artworkData)
    }

    private func updateDiscord() async {
        guard preferences.discordEnabled, !isPrivate,
              snapshot.state == .playing, snapshot.confidence != .low, let session = activeSession else {
            await discord.clear(); discordStatus = preferences.discordEnabled ? .connecting : .disabled; return
        }
        let album = preferences.showAlbum ? (session.track.album ?? "") : ""
        let lineOne = preferences.discordLineOne == .custom ? preferences.discordCustomLineOne : preferences.discordLineOne.value(title: session.track.title, artist: session.track.artist, album: album)
        let lineTwo = preferences.discordLineTwo == .custom ? preferences.discordCustomLineTwo : preferences.discordLineTwo.value(title: session.track.title, artist: session.track.artist, album: album)
        let presence = DiscordPresence(title: DiscordTemplate.render(lineOne, title: session.track.title, artist: session.track.artist, album: album, platform: session.track.platform),
                                       state: DiscordTemplate.render(lineTwo, title: session.track.title, artist: session.track.artist, album: album, platform: session.track.platform),
                                       startedAt: preferences.showTimer ? session.startedAt : nil,
                                       endsAt: preferences.showTimer ? session.startedAt.addingTimeInterval(session.track.duration) : nil,
                                       appleMusicURL: preferences.showLink ? session.track.appleMusicURL : nil,
                                       artworkURL: discordArtworkURL,
                                       buttonLabel: preferences.discordButtonLabel,
                                       platform: session.track.platform,
                                       smallImage: preferences.discordSmallImage)
        do { try await discord.publish(presence); discordStatus = .connected }
        catch let error as DiscordError {
            discordStatus = error == .unavailable ? .offline : .failed(error.localizedDescription)
        } catch { discordStatus = .failed(error.localizedDescription) }
    }

    func retryScrobble(id: UUID) { notifications.reset("queue-stuck"); queue.retry(id: id) }
    func removeScrobble(id: UUID) { queue.remove(id: id) }
    func clearListeningHistory() { store.clearActivity() }
    func applyHistoryRetention() { store.applyHistoryRetention(days: preferences.historyRetentionDays) }

    func setDiscordEnabled(_ enabled: Bool) {
        preferences.discordEnabled = enabled
        Task { enabled ? await updateDiscord() : await discord.clear() }
        discordStatus = enabled ? .connecting : .disabled
    }

    func setLastFMEnabled(_ enabled: Bool) {
        preferences.lastFMEnabled = enabled
        lastFMStatus = enabled ? (lastFMUsername.isEmpty ? .authorizationExpired : .connected) : .disabled
    }

    func refreshDiscord() { Task { await discord.disconnect(); await updateDiscord() } }

    func refreshPresenceOptions() { Task { await discord.clear(); await updateDiscord() } }

    func setPlaybackProvider(_ provider: PlaybackProviderID, enabled: Bool) {
        if enabled { preferences.enabledPlaybackProviders.insert(provider) }
        else { preferences.enabledPlaybackProviders.remove(provider) }
        Task { await monitor.setEnabledProviders(preferences.enabledPlaybackProviders) }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func copyDiagnosticReport() {
        let descriptor = FetchDescriptor<DiagnosticRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let records = (try? store.context.fetch(descriptor)) ?? []
        let report = DiagnosticReport.make(
            appVersion: ReleaseConfiguration.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            playbackPlatform: playbackServiceName,
            musicStatus: musicStatus, discordStatus: discordStatus, lastFMStatus: lastFMStatus,
            ytmDesktopStatus: ytmDesktopStatus, records: records
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        diagnosticCopyStatus = "Copied a privacy-redacted report. Review it before sharing."
    }

    func restoreLatestDatabaseBackup() {
        guard usingTemporaryStore else { return }
        do {
            try PersistenceRecovery.restoreLatestBackup()
            persistenceRecoveryStatus = "The latest automatic database backup was restored. Restart PresenceFM to open it."
        } catch { persistenceRecoveryStatus = error.localizedDescription }
    }

    func prepareFreshDatabase() {
        guard usingTemporaryStore else { return }
        do {
            try PersistenceRecovery.prepareFreshStore()
            persistenceRecoveryStatus = "The failed database was preserved. Restart PresenceFM to create a new local store."
        } catch { persistenceRecoveryStatus = error.localizedDescription }
    }

    func restartApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "presencefm-restart", Bundle.main.bundlePath]
        do {
            try process.run()
            shutdown()
            NSApp.terminate(nil)
        } catch { persistenceRecoveryStatus = "Quit and reopen PresenceFM to retry. \(error.localizedDescription)" }
    }

    var scrobblePresentation: ScrobblePresentationState? { activeSession?.scrobblePresentation }
    var playbackServiceName: String { snapshot.track?.platform.rawValue ?? "Music playback" }

    var privateUntil: Date? { isPrivate ? preferences.privateUntil : nil }

    private func updateLastFMStatus(for error: Error) {
        if case LastFMError.unauthenticated = error { lastFMStatus = .authorizationExpired }
        else if case LastFMError.api(let code, _) = error, code == 9 { lastFMStatus = .authorizationExpired }
        else if case LastFMError.transport = error { lastFMStatus = .offline }
        else { lastFMStatus = .failed(error.localizedDescription) }
    }

    private func updateArtwork(for track: TrackMetadata?) async {
        guard let track else {
            artworkTask?.cancel(); artworkData = nil; discordArtworkURL = nil
            return
        }
        let identity = track.identity
        let data = await artwork.artwork(for: track)
        guard snapshot.track?.identity == identity else { return }
        artworkData = data
        if let data {
            store.backfillArtwork(for: identity.persistentID, artworkData: data)
        }
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let publicURL = await self.artwork.publicArtworkURL(for: track)
            let downloadedData: Data?
            if data == nil, let publicURL {
                downloadedData = await self.artwork.downloadedArtwork(from: publicURL, for: identity)
            } else {
                downloadedData = nil
            }
            guard !Task.isCancelled, self.snapshot.track?.identity == identity else { return }
            if let downloadedData {
                self.artworkData = downloadedData
                self.store.backfillArtwork(for: identity.persistentID, artworkData: downloadedData)
            }
            self.discordArtworkURL = publicURL
            await self.updateDiscord()
        }
    }

    private func schedulePrivacyExpiration() {
        privacyTask?.cancel()
        guard preferences.privateMode, let until = preferences.privateUntil else { return }
        if until <= clock.now { endPrivateMode(); return }
        privacyTask = Task { [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(until: until)
            guard !Task.isCancelled else { return }
            self.endPrivateMode()
        }
    }

    /// Provides a deterministic synchronization point for lifecycle tests without
    /// exposing or polling the underlying task's scheduling state.
    func waitForPendingPrivacyExpiration() async {
        await privacyTask?.value
    }

    private func updateOperationalNotifications() async {
        if musicStatus == .awaitingPermission {
            await notifications.notifyOnce(
                key: "music-permission",
                title: "Apple Music access needed",
                body: "Open PresenceFM to restore Automation permission.",
                section: .diagnostics
            )
        } else { notifications.reset("music-permission") }

        if lastFMStatus == .authorizationExpired {
            await notifications.notifyOnce(
                key: "lastfm-authorization",
                title: "Reconnect Last.fm",
                body: "Your Last.fm authorization expired. Open PresenceFM to reconnect.",
                section: .settings
            )
        } else { notifications.reset("lastfm-authorization") }
    }

    var isPrivate: Bool {
        preferences.privateMode && (preferences.privateUntil == nil || preferences.privateUntil! > clock.now)
    }

    var integrationHealth: [IntegrationHealth] {
        [
            health(playbackIntegrationID, musicStatus),
            health(.youtubeMusic, ytmDesktopStatus),
            health(.discord, discordStatus),
            health(.lastFM, lastFMStatus)
        ]
    }

    private var playbackIntegrationID: IntegrationID {
        switch snapshot.track?.platform {
        case .spotify: .spotify
        case .youtubeMusic: .youtubeMusic
        case .tidal: .tidal
        case .appleMusic, nil: .appleMusic
        }
    }

    private func health(_ id: IntegrationID, _ status: ServiceStatus) -> IntegrationHealth {
        let action: RecoveryAction? = switch (id, status) {
        case (.appleMusic, .awaitingPermission): .openAutomationSettings
        case (.discord, .offline), (.discord, .failed): .reconnectDiscord
        case (.lastFM, .authorizationExpired), (.lastFM, .failed): .reconnectLastFM
        case (.youtubeMusic, .failed): .reconnectYouTubeMusic
        default: nil
        }
        return IntegrationHealth(
            integration: id, state: status.integrationState, summary: status.label,
            lastSuccessfulAt: store.lastSuccessfulIntegrationDate(id), recoveryAction: action
        )
    }

    private func recordHealth(_ id: IntegrationID, _ status: ServiceStatus) {
        store.recordHealth(id, state: status.integrationState, at: clock.now)
    }
}

struct CredentialDraft { var discordApplicationID = ""; var lastFMAPIKey = ""; var lastFMSecret = "" }

enum DashboardSection: String, CaseIterable, Identifiable {
    case nowPlaying = "Now Playing", history = "Listening History", queue = "Queue", diagnostics = "Diagnostics", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self { case .nowPlaying: "music.note"; case .history: "chart.bar.xaxis"; case .queue: "tray.full"; case .diagnostics: "stethoscope"; case .settings: "gear" }
    }
}

@MainActor @Observable
final class Preferences {
    static let shared = Preferences()
    @ObservationIgnored private let defaults: UserDefaults
    var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") } }
    var discordEnabled: Bool { didSet { defaults.set(discordEnabled, forKey: "discordEnabled") } }
    var lastFMEnabled: Bool { didSet { defaults.set(lastFMEnabled, forKey: "lastFMEnabled") } }
    var sendNowPlaying: Bool { didSet { defaults.set(sendNowPlaying, forKey: "sendNowPlaying") } }
    var privateMode: Bool { didSet { defaults.set(privateMode, forKey: "privateMode") } }
    var privateUntil: Date? { didSet { defaults.set(privateUntil, forKey: "privateUntil") } }
    var showAlbum: Bool { didSet { defaults.set(showAlbum, forKey: "showAlbum") } }
    var showTimer: Bool { didSet { defaults.set(showTimer, forKey: "showTimer") } }
    var showLink: Bool { didSet { defaults.set(showLink, forKey: "showLink") } }
    var discordLineOne: DiscordLineFormat { didSet { defaults.set(discordLineOne.rawValue, forKey: "discordLineOne") } }
    var discordLineTwo: DiscordLineFormat { didSet { defaults.set(discordLineTwo.rawValue, forKey: "discordLineTwo") } }
    var discordCustomLineOne: String { didSet { defaults.set(discordCustomLineOne, forKey: "discordCustomLineOne") } }
    var discordCustomLineTwo: String { didSet { defaults.set(discordCustomLineTwo, forKey: "discordCustomLineTwo") } }
    var discordButtonLabel: String { didSet { defaults.set(discordButtonLabel, forKey: "discordButtonLabel") } }
    var discordSmallImage: DiscordSmallImage { didSet { defaults.set(discordSmallImage.rawValue, forKey: "discordSmallImage") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var historyRetentionDays: Int { didSet { defaults.set(historyRetentionDays, forKey: "historyRetentionDays") } }
    var discordApplicationID: String { didSet { defaults.set(discordApplicationID, forKey: "discordApplicationID") } }
    var lastBackupAt: Date? { didSet { defaults.set(lastBackupAt, forKey: "lastBackupAt") } }
    var enabledPlaybackProviders: Set<PlaybackProviderID> {
        didSet { defaults.set(enabledPlaybackProviders.map(\.rawValue).sorted(), forKey: "enabledPlaybackProviders") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        discordEnabled = defaults.bool(forKey: "discordEnabled")
        lastFMEnabled = defaults.bool(forKey: "lastFMEnabled")
        sendNowPlaying = defaults.object(forKey: "sendNowPlaying") as? Bool ?? true
        privateMode = defaults.object(forKey: "privateMode") as? Bool ?? true
        privateUntil = defaults.object(forKey: "privateUntil") as? Date
        showAlbum = defaults.object(forKey: "showAlbum") as? Bool ?? true
        showTimer = defaults.object(forKey: "showTimer") as? Bool ?? true
        showLink = defaults.object(forKey: "showLink") as? Bool ?? true
        discordLineOne = DiscordLineFormat(rawValue: defaults.string(forKey: "discordLineOne") ?? "") ?? .title
        discordLineTwo = DiscordLineFormat(rawValue: defaults.string(forKey: "discordLineTwo") ?? "") ?? .artistAndAlbum
        discordCustomLineOne = defaults.string(forKey: "discordCustomLineOne") ?? "Listening to {artist}"
        discordCustomLineTwo = defaults.string(forKey: "discordCustomLineTwo") ?? "{title} • {album}"
        discordButtonLabel = defaults.string(forKey: "discordButtonLabel") ?? ""
        discordSmallImage = DiscordSmallImage(rawValue: defaults.string(forKey: "discordSmallImage") ?? "") ?? .playbackPlatform
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        historyRetentionDays = defaults.object(forKey: "historyRetentionDays") as? Int ?? 365
        discordApplicationID = defaults.string(forKey: "discordApplicationID") ?? ""
        lastBackupAt = defaults.object(forKey: "lastBackupAt") as? Date
        if let raw = defaults.stringArray(forKey: "enabledPlaybackProviders") {
            enabledPlaybackProviders = Set(raw.compactMap(PlaybackProviderID.init(rawValue:)))
        } else {
            enabledPlaybackProviders = Set(PlaybackProviderID.allCases)
        }
    }
}

enum DiscordLineFormat: String, CaseIterable, Identifiable {
    case title = "Track title"
    case artist = "Artist"
    case album = "Album"
    case artistAndAlbum = "Artist • Album"
    case custom = "Custom"
    var id: Self { self }

    func value(title: String, artist: String, album: String) -> String {
        switch self {
        case .title: title
        case .artist: artist
        case .album: album.isEmpty ? artist : album
        case .artistAndAlbum: album.isEmpty ? artist : "\(artist) • \(album)"
        case .custom: title
        }
    }
}

enum DiscordTemplate {
    static func render(_ template: String, title: String, artist: String, album: String, platform: PlaybackPlatform) -> String {
        var value = template
        let replacements = [
            "{title}": title, "{artist}": artist, "{album}": album,
            "{platform}": platform.rawValue
        ]
        for (token, replacement) in replacements { value = value.replacingOccurrences(of: token, with: replacement) }
        // Avoid dangling separators when optional album metadata is unavailable.
        value = value.replacingOccurrences(of: #"\s*[•|–—-]\s*(?=\s*$)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
