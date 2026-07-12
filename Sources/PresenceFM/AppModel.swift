import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

@MainActor @Observable
final class AppModel {
    var snapshot = PlaybackSnapshot(track: nil, state: .stopped, position: 0, observedAt: .now, confidence: .high)
    var activeSession: PlaybackSession?
    var recentSessions: [PlaybackSession] = []
    var musicStatus: ServiceStatus = .connecting
    var discordStatus: ServiceStatus = .disabled
    var lastFMStatus: ServiceStatus = .disabled
    var onboardingPresented: Bool
    var selectedSection: DashboardSection = .nowPlaying
    var credentialDraft = CredentialDraft()
    var lastFMUsername = ""
    var artworkData: Data?
    var discordArtworkURL: URL?
    let preferences: Preferences

    @ObservationIgnored let store: PersistenceStore
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private let monitor = PlaybackMonitor()
    @ObservationIgnored private let tracker = PlaybackSessionTracker()
    @ObservationIgnored private let artwork = ArtworkService()
    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private lazy var discord = DiscordPresenceClient(applicationID: preferences.discordApplicationID)
    @ObservationIgnored private lazy var lastFM = LastFMClient(keychain: keychain)
    @ObservationIgnored private lazy var queue = ScrobbleQueue(store: store, client: lastFM)
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var privacyTask: Task<Void, Never>?
    @ObservationIgnored private var sectionObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    init(
        store: PersistenceStore,
        preferences: Preferences = .shared,
        notifications: NotificationCoordinator = NotificationCoordinator()
    ) {
        self.store = store
        self.preferences = preferences
        self.notifications = notifications
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
        queue.start()
        monitoringTask = Task {
            let stream = await monitor.snapshots()
            for await value in stream {
                let changedTrack = snapshot.track?.identity != value.track?.identity
                snapshot = value
                if changedTrack {
                    artworkTask?.cancel()
                    artworkData = nil
                    discordArtworkURL = nil
                }
                musicStatus = value.confidence == .low ? .awaitingPermission : .connected
                await handle(await tracker.ingest(value))
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
            if let session = await tracker.shutdown() { await MainActor.run { finalize(session) } }
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
            try await keychain.set(credentialDraft.lastFMAPIKey, for: .lastFMAPIKey)
            try await keychain.set(credentialDraft.lastFMSecret, for: .lastFMSecret)
            store.log("security", "Credentials updated")
        } catch { store.log("security", error.localizedDescription) }
    }

    func beginLastFMAuthorization() async {
        await saveCredentials()
        do { NSWorkspace.shared.open(try await lastFM.beginAuthorization()); lastFMStatus = .connecting }
        catch { updateLastFMStatus(for: error) }
    }

    func completeLastFMAuthorization() async {
        do { lastFMUsername = try await lastFM.completeAuthorization(); lastFMStatus = .connected }
        catch { updateLastFMStatus(for: error) }
    }

    func disconnectLastFM() async {
        await keychain.remove(.lastFMSessionKey)
        await keychain.remove(.lastFMUsername)
        lastFMUsername = ""
        preferences.lastFMEnabled = false
        lastFMStatus = .disabled
        store.log("lastfm", "Account disconnected")
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
        credentialDraft.lastFMAPIKey = await keychain.value(for: .lastFMAPIKey) ?? ""
        lastFMUsername = await keychain.value(for: .lastFMUsername) ?? ""
        discordStatus = (credentialDraft.discordApplicationID.isEmpty && !ReleaseConfiguration.hasDiscordConfiguration) ? .disabled : .connecting
        lastFMStatus = preferences.lastFMEnabled ? (lastFMUsername.isEmpty ? .authorizationExpired : .connected) : .disabled
    }

    private func handle(_ events: [PlaybackSessionTracker.Event]) async {
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
            case .eligible(let session): activeSession = session; if preferences.lastFMEnabled && !isPrivate { queue.enqueue(session) }
            case .finalized(let session): finalize(session)
            case .none: break
            }
        }
    }

    private func finalize(_ session: PlaybackSession) {
        activeSession = nil; recentSessions.insert(session, at: 0)
        if recentSessions.count > 200 { recentSessions.removeLast() }
        store.record(session, artworkData: artworkData)
    }

    private func updateDiscord() async {
        guard preferences.discordEnabled, !isPrivate,
              snapshot.state == .playing, snapshot.confidence != .low, let session = activeSession else {
            await discord.clear(); discordStatus = preferences.discordEnabled ? .connecting : .disabled; return
        }
        let album = session.track.album ?? ""
        let presence = DiscordPresence(title: preferences.discordLineOne.value(title: session.track.title, artist: session.track.artist, album: album),
                                       state: preferences.discordLineTwo.value(title: session.track.title, artist: session.track.artist, album: album),
                                       startedAt: preferences.showTimer ? session.startedAt : nil,
                                       appleMusicURL: preferences.showLink ? session.track.appleMusicURL : nil,
                                       artworkURL: discordArtworkURL,
                                       buttonLabel: preferences.discordButtonLabel)
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

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    var scrobblePresentation: ScrobblePresentationState? { activeSession?.scrobblePresentation }

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
            if let downloadedData { self.artworkData = downloadedData }
            self.discordArtworkURL = publicURL
            await self.updateDiscord()
        }
    }

    private func schedulePrivacyExpiration() {
        privacyTask?.cancel()
        guard preferences.privateMode, let until = preferences.privateUntil else { return }
        if until <= .now { endPrivateMode(); return }
        privacyTask = Task { [weak self] in
            let duration = max(0, until.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.endPrivateMode()
        }
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
        preferences.privateMode && (preferences.privateUntil == nil || preferences.privateUntil! > .now)
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
    var discordButtonLabel: String { didSet { defaults.set(discordButtonLabel, forKey: "discordButtonLabel") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var historyRetentionDays: Int { didSet { defaults.set(historyRetentionDays, forKey: "historyRetentionDays") } }
    var discordApplicationID: String { didSet { defaults.set(discordApplicationID, forKey: "discordApplicationID") } }

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
        discordButtonLabel = defaults.string(forKey: "discordButtonLabel") ?? "Listen on Apple Music"
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        historyRetentionDays = defaults.object(forKey: "historyRetentionDays") as? Int ?? 365
        discordApplicationID = defaults.string(forKey: "discordApplicationID") ?? ""
    }
}

enum DiscordLineFormat: String, CaseIterable, Identifiable {
    case title = "Track title"
    case artist = "Artist"
    case album = "Album"
    case artistAndAlbum = "Artist • Album"
    var id: Self { self }

    func value(title: String, artist: String, album: String) -> String {
        switch self {
        case .title: title
        case .artist: artist
        case .album: album.isEmpty ? artist : album
        case .artistAndAlbum: album.isEmpty ? artist : "\(artist) • \(album)"
        }
    }
}
