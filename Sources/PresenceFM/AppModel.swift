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

    @ObservationIgnored let store: PersistenceStore
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private let monitor = PlaybackMonitor()
    @ObservationIgnored private let tracker = PlaybackSessionTracker()
    @ObservationIgnored private lazy var discord = DiscordPresenceClient(keychain: keychain)
    @ObservationIgnored private lazy var lastFM = LastFMClient(keychain: keychain)
    @ObservationIgnored private lazy var queue = ScrobbleQueue(store: store, client: lastFM)
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(store: PersistenceStore) {
        self.store = store
        onboardingPresented = !Preferences.shared.onboardingComplete
    }

    func start() {
        guard !started else { return }
        started = true
        queue.start()
        monitoringTask = Task {
            let stream = await monitor.snapshots()
            for await value in stream {
                snapshot = value
                musicStatus = value.confidence == .low ? .awaitingPermission : .connected
                await handle(await tracker.ingest(value))
                await updateDiscord()
            }
        }
        Task { await loadCredentials(); await queue.process() }
    }

    func shutdown() {
        guard started else { return }
        started = false
        monitoringTask?.cancel()
        queue.stop()
        Task {
            if let session = await tracker.shutdown() { await MainActor.run { finalize(session) } }
            await discord.clear(); await monitor.stop()
        }
    }

    func setPrivate(until: Date?) {
        Preferences.shared.privateMode = true
        Preferences.shared.privateUntil = until
        Task { await discord.clear() }
    }

    func endPrivateMode() {
        Preferences.shared.privateMode = false; Preferences.shared.privateUntil = nil
        Task { await updateDiscord() }
    }

    func saveCredentials() async {
        do {
            try await keychain.set(credentialDraft.discordApplicationID, for: .discordApplicationID)
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
        Preferences.shared.lastFMEnabled = false
        lastFMStatus = .disabled
        store.log("lastfm", "Account disconnected")
    }

    func completeOnboarding() {
        Preferences.shared.onboardingComplete = true
        onboardingPresented = false
        if Preferences.shared.privateMode { endPrivateMode() }
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            Preferences.shared.launchAtLogin = enabled
        } catch { store.log("login", error.localizedDescription) }
    }

    private func loadCredentials() async {
        credentialDraft.discordApplicationID = await keychain.value(for: .discordApplicationID) ?? ""
        credentialDraft.lastFMAPIKey = await keychain.value(for: .lastFMAPIKey) ?? ""
        lastFMUsername = await keychain.value(for: .lastFMUsername) ?? ""
        discordStatus = (credentialDraft.discordApplicationID.isEmpty && !ReleaseConfiguration.hasDiscordConfiguration) ? .disabled : .connecting
        lastFMStatus = lastFMUsername.isEmpty ? .disabled : .connected
    }

    private func handle(_ events: [PlaybackSessionTracker.Event]) async {
        for event in events {
            switch event {
            case .started(let session):
                activeSession = session
                if Preferences.shared.lastFMEnabled && Preferences.shared.sendNowPlaying && !isPrivate {
                    do { try await lastFM.updateNowPlaying(session); lastFMStatus = .connected }
                    catch { updateLastFMStatus(for: error) }
                }
            case .updated(let session): activeSession = session
            case .eligible(let session): activeSession = session; if Preferences.shared.lastFMEnabled && !isPrivate { queue.enqueue(session) }
            case .finalized(let session): finalize(session)
            case .none: break
            }
        }
    }

    private func finalize(_ session: PlaybackSession) {
        activeSession = nil; recentSessions.insert(session, at: 0)
        if recentSessions.count > 200 { recentSessions.removeLast() }
        store.record(session)
    }

    private func updateDiscord() async {
        guard Preferences.shared.discordEnabled, !isPrivate,
              snapshot.state == .playing, snapshot.confidence != .low, let session = activeSession else {
            await discord.clear(); discordStatus = Preferences.shared.discordEnabled ? .connecting : .disabled; return
        }
        let state = Preferences.shared.showAlbum && session.track.album != nil
            ? "\(session.track.artist) • \(session.track.album!)" : session.track.artist
        let presence = DiscordPresence(title: session.track.title, state: state,
                                       startedAt: Preferences.shared.showTimer ? session.startedAt : nil,
                                       appleMusicURL: Preferences.shared.showLink ? session.track.appleMusicURL : nil)
        do { try await discord.publish(presence); discordStatus = .connected }
        catch let error as DiscordError {
            discordStatus = error == .unavailable ? .offline : .failed(error.localizedDescription)
        } catch { discordStatus = .failed(error.localizedDescription) }
    }

    func retryScrobble(id: UUID) { queue.retry(id: id) }
    func removeScrobble(id: UUID) { queue.remove(id: id) }

    private func updateLastFMStatus(for error: Error) {
        if case LastFMError.unauthenticated = error { lastFMStatus = .authorizationExpired }
        else if case LastFMError.api(let code, _) = error, code == 9 { lastFMStatus = .authorizationExpired }
        else if case LastFMError.transport = error { lastFMStatus = .offline }
        else { lastFMStatus = .failed(error.localizedDescription) }
    }

    var isPrivate: Bool {
        if let until = Preferences.shared.privateUntil, until <= .now {
            Preferences.shared.privateMode = false; Preferences.shared.privateUntil = nil
        }
        return Preferences.shared.privateMode
    }
}

struct CredentialDraft { var discordApplicationID = ""; var lastFMAPIKey = ""; var lastFMSecret = "" }

enum DashboardSection: String, CaseIterable, Identifiable {
    case nowPlaying = "Now Playing", recent = "Recent Activity", queue = "Queue", diagnostics = "Diagnostics", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self { case .nowPlaying: "music.note"; case .recent: "clock"; case .queue: "tray.full"; case .diagnostics: "stethoscope"; case .settings: "gear" }
    }
}

@MainActor
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    var onboardingComplete: Bool { get { defaults.bool(forKey: "onboardingComplete") } set { defaults.set(newValue, forKey: "onboardingComplete") } }
    var discordEnabled: Bool { get { defaults.bool(forKey: "discordEnabled") } set { defaults.set(newValue, forKey: "discordEnabled") } }
    var lastFMEnabled: Bool { get { defaults.bool(forKey: "lastFMEnabled") } set { defaults.set(newValue, forKey: "lastFMEnabled") } }
    var sendNowPlaying: Bool { get { defaults.object(forKey: "sendNowPlaying") as? Bool ?? true } set { defaults.set(newValue, forKey: "sendNowPlaying") } }
    var privateMode: Bool { get { defaults.object(forKey: "privateMode") as? Bool ?? true } set { defaults.set(newValue, forKey: "privateMode") } }
    var privateUntil: Date? { get { defaults.object(forKey: "privateUntil") as? Date } set { defaults.set(newValue, forKey: "privateUntil") } }
    var showAlbum: Bool { get { defaults.object(forKey: "showAlbum") as? Bool ?? true } set { defaults.set(newValue, forKey: "showAlbum") } }
    var showTimer: Bool { get { defaults.object(forKey: "showTimer") as? Bool ?? true } set { defaults.set(newValue, forKey: "showTimer") } }
    var showLink: Bool { get { defaults.object(forKey: "showLink") as? Bool ?? true } set { defaults.set(newValue, forKey: "showLink") } }
    var launchAtLogin: Bool { get { defaults.bool(forKey: "launchAtLogin") } set { defaults.set(newValue, forKey: "launchAtLogin") } }
}
