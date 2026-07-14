import AppKit
import AVFoundation
import Combine
import UserNotifications

struct AppInfo: Identifiable, Hashable {
    let pid: pid_t
    let bundleID: String
    let name: String
    var id: String { "app:\(pid)" }
}

enum CaptureSource: Hashable {
    case microphone
    case systemAudio
    case app(AppInfo)

    var id: String {
        switch self {
        case .microphone: return "mic"
        case .systemAudio: return "system"
        case .app(let info): return info.id
        }
    }

    var label: String {
        switch self {
        case .microphone: return "MICROPHONE"
        case .systemAudio: return "SYSTEM AUDIO"
        case .app(let info): return info.name.uppercased()
        }
    }
}

enum TranslationMode: String {
    case sync   // streaming interpreter: lowest latency, fixed voice
    case voice  // voice agent: selectable voice, phrase-by-phrase
}

enum EngineStatus: String {
    case idle = "IDLE"
    case connecting = "CONNECTING"
    case listening = "LISTENING"
    case translating = "TRANSLATING"
    case standby = "STANDBY"
    case error = "ERROR"
}

struct TranslationSessionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let sourceID: String
    let sourceName: String
    let sourceLanguage: String
    let targetLanguage: String
}

/// High-frequency audio levels live outside AppState so they do not invalidate
/// the entire dashboard 30 times per second.
final class AudioMeterState: ObservableObject {
    @Published var input: Float = 0
    @Published var output: Float = 0
}

final class AudioOutputSettings: ObservableObject {
    @Published var volume: Float

    init(volume: Float) {
        self.volume = min(1, max(0, volume))
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRunning = false
    @Published var status: EngineStatus = .idle
    @Published var transcript: String = ""
    @Published var errorMessage: String?
    @Published var runningApps: [AppInfo] = []
    @Published private(set) var completedSessionCount: Int
    @Published private(set) var totalTranslationSeconds: TimeInterval
    @Published private(set) var lastSessionAt: Date?
    @Published private(set) var currentSessionStartedAt: Date?
    @Published private(set) var currentSessionActiveSeconds: TimeInterval
    @Published private(set) var sessionHistory: [TranslationSessionRecord]

    @Published var selectedSourceID: String {
        didSet {
            UserDefaults.standard.set(selectedSourceID, forKey: "sourceID")
            if oldValue != selectedSourceID {
                selectedTabID = nil
                refreshTabs()
            }
        }
    }
    @Published var browserTabs: [BrowserTab] = []
    @Published var selectedTabID: String?
    @Published var targetLanguage: String {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: "targetLanguage") }
    }
    @Published var sourceLanguage: String {
        didSet { UserDefaults.standard.set(sourceLanguage, forKey: "sourceLanguage") }
    }
    @Published var voice: String {
        didSet { UserDefaults.standard.set(voice, forKey: "voice") }
    }
    @Published var uiLanguage: UILanguage {
        didSet { UserDefaults.standard.set(uiLanguage.rawValue, forKey: "uiLang") }
    }
    @Published var mode: TranslationMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    @Published var dimmingEnabled: Bool {
        didSet { UserDefaults.standard.set(dimmingEnabled, forKey: "dimmingEnabled") }
    }
    @Published var sourceAudioMuted: Bool {
        didSet {
            UserDefaults.standard.set(sourceAudioMuted, forKey: "sourceAudioMuted")
            appCapturer?.setSourceMuted(sourceAudioMuted)
        }
    }
    @Published var overlayCollapsed = false
    let meter = AudioMeterState()
    let outputSettings: AudioOutputSettings

    var loc: Strings { uiLanguage == .ru ? .ru : .en }

    var statusLabel: String {
        switch status {
        case .idle: return loc.statusIdle
        case .connecting: return loc.statusConnecting
        case .listening: return loc.statusListening
        case .translating: return loc.statusTranslating
        case .standby: return loc.statusStandby
        case .error: return loc.statusError
        }
    }

    static let languages = ["Auto", "Russian", "English", "Spanish", "German", "French", "Italian", "Portuguese", "Chinese", "Japanese", "Korean", "Ukrainian", "Turkish", "Arabic", "Hindi"]
    static let voices = ["marin", "cedar", "alloy", "ash", "coral", "echo", "sage", "shimmer", "verse"]

    private var client: TranslatorClient?
    private var backlogLogTimer: Timer?
    private var tokenTask: Task<Void, Never>?
    private var outputSettingsCancellable: AnyCancellable?

    // Keep the realtime connection warm while translation is running. Closing
    // it after a short silence used to add 5–6 seconds before the next phrase.
    private var suspended = false
    private var clientReady = false
    private var lastSoundAt = Date()
    private let soundGateLevel: Float = 0.04
    private var micCapturer: MicCapturer?
    private var appCapturer: AppAudioCapturer?
    private var player: AudioPlayer?
    private let overlay = OverlayController()
    private let inputQueue = DispatchQueue(label: "eyevoice.realtime-input", qos: .userInitiated)

    private var lastInputLevelPush = Date.distantPast
    private var lastOutputLevelPush = Date.distantPast
    private var lastInputTelemetryAt = Date.distantPast
    private var lastServerInputLogAt = Date.distantPast
    private var sentAudioBytesSinceTelemetry = 0
    private var liveCaptureStartedAt: Date?
    private var firstOutputLogged = false
    private var activeUsageSegmentStartedAt: Date?
    private var currentSessionBecameActive = false
    private var currentSessionSourceID = "mic"
    private var currentSessionSourceName = "MICROPHONE"
    private var currentSessionSourceLanguage = "Auto"
    private var currentSessionTargetLanguage = "English"
    private var isSyncingUsage = false
    private var lifecycleTransitionInProgress = false

    init() {
        let d = UserDefaults.standard
        selectedSourceID = d.string(forKey: "sourceID") ?? "mic"
        targetLanguage = d.string(forKey: "targetLanguage") ?? "English"
        sourceLanguage = d.string(forKey: "sourceLanguage") ?? "Auto"
        voice = d.string(forKey: "voice") ?? "marin"
        uiLanguage = UILanguage(rawValue: d.string(forKey: "uiLang") ?? "ru") ?? .ru
        dimmingEnabled = d.object(forKey: "dimmingEnabled") as? Bool ?? true
        sourceAudioMuted = d.bool(forKey: "sourceAudioMuted")
        let legacyVolume = d.object(forKey: "translationVolume") == nil
            ? 1
            : d.float(forKey: "translationVolume")
        let savedVolume: Float
        if d.integer(forKey: "translationVolumeScaleVersion") < 2 {
            // Preserve the exact old loudness: the former 100% is the new 20%.
            savedVolume = min(1, max(0, legacyVolume / 5))
            d.set(savedVolume, forKey: "translationVolume")
            d.set(2, forKey: "translationVolumeScaleVersion")
        } else {
            savedVolume = legacyVolume
        }
        outputSettings = AudioOutputSettings(volume: savedVolume)
        completedSessionCount = d.integer(forKey: "completedSessionCount")
        totalTranslationSeconds = d.double(forKey: "totalTranslationSeconds")
        lastSessionAt = d.object(forKey: "lastSessionAt") as? Date
        currentSessionStartedAt = nil
        currentSessionActiveSeconds = 0
        if let historyData = d.data(forKey: "translationSessionHistory"),
           let decoded = try? JSONDecoder().decode([TranslationSessionRecord].self, from: historyData) {
            sessionHistory = decoded
        } else {
            sessionHistory = []
        }
        // voice mode is parked until we build our own voice pipeline — sync only for now
        mode = .sync

        outputSettingsCancellable = outputSettings.$volume
            .removeDuplicates()
            .sink { [weak self] volume in
                let clamped = min(1, max(0, volume))
                UserDefaults.standard.set(clamped, forKey: "translationVolume")
                self?.player?.setVolume(clamped)
            }
    }

    var availableSources: [CaptureSource] {
        [.microphone, .systemAudio] + runningApps.map { .app($0) }
    }

    var selectedSource: CaptureSource {
        availableSources.first { $0.id == selectedSourceID } ?? .microphone
    }

    var canMuteSourceAudio: Bool {
        if case .microphone = selectedSource { return false }
        return true
    }

    func refreshApps() {
        let me = ProcessInfo.processInfo.processIdentifier
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .compactMap { app in
                guard let name = app.localizedName else { return nil }
                return AppInfo(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "", name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        refreshTabs()
    }

    /// Loads the tab list when the selected source is a browser.
    func refreshTabs() {
        guard case .app(let info) = selectedSource, TabLister.isBrowser(info) else {
            browserTabs = []
            return
        }
        TabLister.listTabs(for: info) { [weak self] tabs in
            guard let self,
                  case .app(let current) = self.selectedSource,
                  current.pid == info.pid else { return }
            self.browserTabs = tabs
            if let id = self.selectedTabID, !tabs.contains(where: { $0.id == id }) {
                self.selectedTabID = nil
            }
        }
    }

    // MARK: - Lifecycle

    func toggle() {
        guard !lifecycleTransitionInProgress else { return }
        lifecycleTransitionInProgress = true
        isRunning ? stop() : start()

        // Core Audio creates/destroys its process tap on a worker queue. Keep a
        // second click from starting another tap while that transition settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            self?.lifecycleTransitionInProgress = false
        }
    }

    func start() {
        guard !isRunning else { return }
        errorMessage = nil
        transcript = ""
        isRunning = true
        currentSessionStartedAt = Date()
        currentSessionActiveSeconds = 0
        activeUsageSegmentStartedAt = nil
        currentSessionBecameActive = false
        currentSessionSourceID = selectedSource.id
        currentSessionSourceName = selectedSource.label
        currentSessionSourceLanguage = sourceLanguage
        currentSessionTargetLanguage = targetLanguage
        suspended = false
        lastSoundAt = Date()
        lastInputTelemetryAt = Date()
        lastServerInputLogAt = .distantPast
        sentAudioBytesSinceTelemetry = 0
        liveCaptureStartedAt = nil
        firstOutputLogged = false
        overlayCollapsed = false
        status = .connecting
        overlay.show(state: self)

        let player = AudioPlayer()
        player.onLevel = { [weak self] level in self?.pushOutputLevel(level) }
        player.setVolume(outputSettings.volume)
        self.player = player

        requestClientAndConnect()

        // Latency diagnostics: log the playback backlog while running.
        backlogLogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isRunning, let player = self.player else { return }
            Self.logToFile("backlog: \(String(format: "%.2f", player.backlogSeconds))s status: \(self.status.rawValue)")
        }
    }

    /// Builds and connects a translator client. Capture starts only after the
    /// realtime session is ready. Buffering audio during token/WebSocket setup
    /// permanently puts a live translation several seconds behind the source.
    private func requestClientAndConnect() {
        clientReady = false
        tokenTask?.cancel()

        tokenTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 1...3 {
                do {
                    let token = try await SupabaseAuthManager.shared.realtimeClientSecret(
                        mode: self.mode,
                        targetLanguage: Self.languageCode(for: self.targetLanguage),
                        voice: self.voice
                    )
                    guard !Task.isCancelled, self.isRunning, !self.suspended else { return }
                    self.connectClient(using: token)
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    if attempt == 3 {
                        self.fail(error.localizedDescription)
                        return
                    }
                    Self.logToFile(
                        "realtime token attempt \(attempt) failed: \(error.localizedDescription); retrying"
                    )
                    try? await Task.sleep(for: .milliseconds(350 * attempt))
                }
            }
        }
    }

    private func connectClient(using clientSecret: String) {
        clientReady = false

        let client: TranslatorClient
        switch mode {
        case .sync:
            client = RealtimeClient(
                apiKey: clientSecret,
                model: Secrets.translateModel,
                targetLanguage: Self.languageCode(for: targetLanguage)
            )
        case .voice:
            client = VoiceRealtimeClient(
                apiKey: clientSecret,
                model: Secrets.voiceModel,
                voice: voice,
                targetLanguage: targetLanguage
            )
        }
        client.onAudio = { [weak self] data in
            guard let self else { return }
            // safety valve: if we somehow fall far behind live, skip the stale tail
            if let player = self.player, player.backlogSeconds > 10 {
                Self.logToFile("backlog \(String(format: "%.1f", player.backlogSeconds))s > 10s — flushed")
                player.flush()
            }
            self.player?.enqueue(pcm16: data)
            DispatchQueue.main.async {
                if !self.firstOutputLogged, let startedAt = self.liveCaptureStartedAt {
                    self.firstOutputLogged = true
                    Self.logToFile(
                        "latency: first translated audio after "
                            + String(format: "%.2f", Date().timeIntervalSince(startedAt))
                            + "s of live capture"
                    )
                }
                self.markTranslating()
            }
        }
        client.onTranscriptDelta = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.transcript = String((self.transcript + text).suffix(160))
            }
        }
        client.onInputActivity = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                let now = Date()
                if now.timeIntervalSince(self.lastServerInputLogAt) > 5 {
                    self.lastServerInputLogAt = now
                    Self.logToFile("realtime: server is receiving source speech")
                }
            }
        }
        client.onSegmentStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                // voice mode: drop a stale queue when a fresh segment begins
                if let player = self.player, player.backlogSeconds > 6 {
                    player.flush()
                }
                self.transcript = ""
            }
        }
        client.onConnected = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isRunning, !self.suspended else { return }
                self.clientReady = true
                self.beginActiveUsageSegment()
                if self.micCapturer == nil, self.appCapturer == nil {
                    self.liveCaptureStartedAt = Date()
                    Self.logToFile("realtime ready: starting live capture without startup backlog")
                    self.startCapture()
                }
                self.setStatus(.listening)
            }
        }
        client.onError = { [weak self] message in
            DispatchQueue.main.async { self?.fail(message) }
        }
        self.client = client
        client.connect()
    }

    /// Called for every captured audio chunk (main thread).
    private func handleChunk(_ data: Data) {
        guard isRunning, !suspended else { return }
        if clientReady {
            client?.sendAudio(data)
            sentAudioBytesSinceTelemetry += data.count
            let now = Date()
            if now.timeIntervalSince(lastInputTelemetryAt) >= 5 {
                let kilobytes = sentAudioBytesSinceTelemetry / 1024
                Self.logToFile("input: sent \(kilobytes) KB PCM16 in the last 5s")
                sentAudioBytesSinceTelemetry = 0
                lastInputTelemetryAt = now
            }
        }
    }

    /// Legacy explicit standby support. Automatic standby is intentionally
    /// disabled because reconnecting is much slower than the 1–2 second target.
    private func standby() {
        guard isRunning, !suspended else { return }
        pauseActiveUsageSegment()
        suspended = true
        clientReady = false
        tokenTask?.cancel()
        tokenTask = nil
        client?.disconnect()
        client = nil
        status = .standby
        Self.logToFile("standby: connection closed")
    }

    /// Sound detected while sleeping → reconnect instantly, buffering the audio meanwhile.
    private func wake() {
        guard isRunning, suspended else { return }
        suspended = false
        status = .connecting
        Self.logToFile("wake: sound detected — reconnecting")
        requestClientAndConnect()
    }

    func stop() {
        guard isRunning else { return }
        tokenTask?.cancel()
        tokenTask = nil
        pauseActiveUsageSegment()
        if let currentSessionStartedAt, currentSessionBecameActive {
            let finishedAt = Date()
            let sessionDuration = max(0, currentSessionActiveSeconds)
            totalTranslationSeconds += sessionDuration
            completedSessionCount += 1
            lastSessionAt = finishedAt

            let record = TranslationSessionRecord(
                id: UUID(),
                startedAt: currentSessionStartedAt,
                endedAt: finishedAt,
                duration: sessionDuration,
                sourceID: currentSessionSourceID,
                sourceName: currentSessionSourceName,
                sourceLanguage: currentSessionSourceLanguage,
                targetLanguage: currentSessionTargetLanguage
            )
            sessionHistory.insert(record, at: 0)
            if sessionHistory.count > 500 {
                sessionHistory.removeLast(sessionHistory.count - 500)
            }

            let defaults = UserDefaults.standard
            defaults.set(totalTranslationSeconds, forKey: "totalTranslationSeconds")
            defaults.set(completedSessionCount, forKey: "completedSessionCount")
            defaults.set(finishedAt, forKey: "lastSessionAt")
            if let encoded = try? JSONEncoder().encode(sessionHistory) {
                defaults.set(encoded, forKey: "translationSessionHistory")
            }
            syncUsageWithAccount()
        }
        currentSessionStartedAt = nil
        currentSessionActiveSeconds = 0
        activeUsageSegmentStartedAt = nil
        currentSessionBecameActive = false
        isRunning = false
        status = .idle
        translatingRevert?.cancel(); translatingRevert = nil
        backlogLogTimer?.invalidate(); backlogLogTimer = nil
        micCapturer?.stop(); micCapturer = nil
        appCapturer?.stop(); appCapturer = nil
        client?.disconnect(); client = nil
        player?.stop(); player = nil
        suspended = false
        clientReady = false
        meter.input = 0
        meter.output = 0
        overlay.hide()
    }

    func syncUsageWithAccount() {
        guard !sessionHistory.isEmpty, !isSyncingUsage else { return }
        let records = sessionHistory
        isSyncingUsage = true

        Task { @MainActor [weak self] in
            defer { self?.isSyncingUsage = false }
            do {
                try await SupabaseAuthManager.shared.uploadTranslationSessions(records)
            } catch {
                Self.logToFile("usage sync failed: \(error.localizedDescription)")
            }
        }
    }

    func currentSessionUsage(at date: Date = Date()) -> TimeInterval {
        currentSessionActiveSeconds
            + (activeUsageSegmentStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    private func beginActiveUsageSegment() {
        guard isRunning, activeUsageSegmentStartedAt == nil else { return }
        currentSessionBecameActive = true
        activeUsageSegmentStartedAt = Date()
    }

    private func pauseActiveUsageSegment() {
        guard let activeUsageSegmentStartedAt else { return }
        currentSessionActiveSeconds += max(0, Date().timeIntervalSince(activeUsageSegmentStartedAt))
        self.activeUsageSegmentStartedAt = nil
    }

    private func fail(_ message: String) {
        guard isRunning else { return }
        errorMessage = message
        Self.logToFile("ERROR: \(message)")
        status = .error
        stop()
        status = .error
    }

    static func logToFile(_ message: String) {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/EyeVoice.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func setStatus(_ s: EngineStatus) {
        guard isRunning else { return }
        status = s
    }

    private func startCapture() {
        // bring the chosen browser tab to front before capturing
        if case .app(let info) = selectedSource,
           let tabID = selectedTabID,
           let tab = browserTabs.first(where: { $0.id == tabID }) {
            TabLister.activate(tab, in: info)
        }

        let onChunk: (Data) -> Void = { [weak self] data in
            self?.inputQueue.async { [weak self] in
                self?.handleChunk(data)
            }
        }
        let onLevel: (Float) -> Void = { [weak self] level in self?.pushInputLevel(level) }

        switch selectedSource {
        case .microphone:
            let mic = MicCapturer()
            micCapturer = mic
            mic.start(onChunk: onChunk, onLevel: onLevel) { [weak self] error in
                DispatchQueue.main.async { self?.fail(error) }
            }
        case .systemAudio:
            let cap = AppAudioCapturer(target: nil, sourceMuted: sourceAudioMuted)
            appCapturer = cap
            cap.start(onChunk: onChunk, onLevel: onLevel) { [weak self] error in
                DispatchQueue.main.async { self?.fail(error) }
            }
        case .app(let info):
            let cap = AppAudioCapturer(target: info, sourceMuted: sourceAudioMuted)
            appCapturer = cap
            cap.start(onChunk: onChunk, onLevel: onLevel) { [weak self] error in
                DispatchQueue.main.async { self?.fail(error) }
            }
        }
    }

    private static let languageCodes: [String: String] = [
        "Russian": "ru", "English": "en", "Spanish": "es", "German": "de",
        "French": "fr", "Italian": "it", "Portuguese": "pt", "Chinese": "zh",
        "Japanese": "ja", "Korean": "ko", "Ukrainian": "uk", "Turkish": "tr",
        "Arabic": "ar", "Hindi": "hi",
    ]

    static func languageCode(for name: String) -> String {
        languageCodes[name] ?? "en"
    }

    /// Translated audio is flowing: show TRANSLATING, fall back to LISTENING after a pause.
    private var translatingRevert: DispatchWorkItem?

    private func markTranslating() {
        guard isRunning else { return }
        status = .translating
        translatingRevert?.cancel()
        let revert = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.status == .translating else { return }
            self.status = .listening
        }
        translatingRevert = revert
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: revert)
    }

    // Throttle level updates to ~30 Hz on the main thread
    private func pushInputLevel(_ level: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastInputLevelPush) > 0.033 else { return }
        lastInputLevelPush = now
        DispatchQueue.main.async {
            self.meter.input = level
            self.soundGate(level)
        }
    }

    /// Track speech activity without tearing down the warmed realtime session.
    private func soundGate(_ level: Float) {
        guard isRunning else { return }
        if level > soundGateLevel {
            lastSoundAt = Date()
            if suspended { wake() }
        }
    }

    private func pushOutputLevel(_ level: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastOutputLevelPush) > 0.033 else { return }
        lastOutputLevelPush = now
        DispatchQueue.main.async {
            self.meter.output = level
            // translated speech playing counts as activity — don't doze mid-sentence
            if level > self.soundGateLevel {
                self.lastSoundAt = Date()
            }
        }
    }

}
