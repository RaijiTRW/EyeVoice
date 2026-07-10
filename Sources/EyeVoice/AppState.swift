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

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRunning = false
    @Published var status: EngineStatus = .idle
    @Published var inputLevel: Float = 0
    @Published var outputLevel: Float = 0
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
    let apiKey = Secrets.defaultAPIKey
    @Published var uiLanguage: UILanguage {
        didSet { UserDefaults.standard.set(uiLanguage.rawValue, forKey: "uiLang") }
    }
    @Published var mode: TranslationMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }

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

    // sound gate: sleep the connection during silence, wake instantly on sound
    private var suspended = false
    private var clientReady = false
    private var resumeBuffer: [Data] = []
    private var lastSoundAt = Date()
    private let soundGateLevel: Float = 0.04
    private let standbyAfterSilence: TimeInterval = 8
    private var micCapturer: MicCapturer?
    private var appCapturer: AppAudioCapturer?
    private var player: AudioPlayer?
    private let overlay = OverlayController()

    private var lastInputLevelPush = Date.distantPast
    private var lastOutputLevelPush = Date.distantPast
    private var activeUsageSegmentStartedAt: Date?
    private var currentSessionBecameActive = false
    private var currentSessionSourceID = "mic"
    private var currentSessionSourceName = "MICROPHONE"
    private var currentSessionSourceLanguage = "Auto"
    private var currentSessionTargetLanguage = "English"

    init() {
        let d = UserDefaults.standard
        selectedSourceID = d.string(forKey: "sourceID") ?? "mic"
        targetLanguage = d.string(forKey: "targetLanguage") ?? "English"
        sourceLanguage = d.string(forKey: "sourceLanguage") ?? "Auto"
        voice = d.string(forKey: "voice") ?? "marin"
        uiLanguage = UILanguage(rawValue: d.string(forKey: "uiLang") ?? "ru") ?? .ru
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
    }

    var availableSources: [CaptureSource] {
        [.microphone, .systemAudio] + runningApps.map { .app($0) }
    }

    var selectedSource: CaptureSource {
        availableSources.first { $0.id == selectedSourceID } ?? .microphone
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
        isRunning ? stop() : start()
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
        status = .connecting
        overlay.show(state: self)

        let player = AudioPlayer()
        player.onLevel = { [weak self] level in self?.pushOutputLevel(level) }
        self.player = player

        connectClient()

        // latency diagnostics: log the playback backlog while running
        backlogLogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isRunning, let player = self.player else { return }
            Self.logToFile("backlog: \(String(format: "%.2f", player.backlogSeconds))s status: \(self.status.rawValue)")
        }

        startCapture()
    }

    /// Builds and connects a translator client. Audio arriving before the session
    /// is ready is buffered and flushed on connect, so no speech is lost.
    private func connectClient() {
        clientReady = false

        let client: TranslatorClient
        switch mode {
        case .sync:
            client = RealtimeClient(
                apiKey: apiKey,
                model: Secrets.translateModel,
                targetLanguage: Self.languageCode(for: targetLanguage)
            )
        case .voice:
            client = VoiceRealtimeClient(
                apiKey: apiKey,
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
            DispatchQueue.main.async { self.markTranslating() }
        }
        client.onTranscriptDelta = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.transcript = String((self.transcript + text).suffix(160))
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
                for chunk in self.resumeBuffer {
                    self.client?.sendAudio(chunk)
                }
                self.resumeBuffer = []
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
        guard isRunning, !suspended, client != nil else { return }
        if clientReady {
            client?.sendAudio(data)
        } else {
            resumeBuffer.append(data)
            if resumeBuffer.count > 300 { resumeBuffer.removeFirst() }
        }
    }

    /// Silence for a while → close the connection (stops billing), keep capturing.
    private func standby() {
        guard isRunning, !suspended else { return }
        pauseActiveUsageSegment()
        suspended = true
        clientReady = false
        client?.disconnect()
        client = nil
        resumeBuffer = []
        status = .standby
        Self.logToFile("standby: \(Int(standbyAfterSilence))s of silence — connection closed")
    }

    /// Sound detected while sleeping → reconnect instantly, buffering the audio meanwhile.
    private func wake() {
        guard isRunning, suspended else { return }
        suspended = false
        status = .connecting
        Self.logToFile("wake: sound detected — reconnecting")
        connectClient()
    }

    func stop() {
        guard isRunning else { return }
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
        resumeBuffer = []
        inputLevel = 0
        outputLevel = 0
        overlay.hide()
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
            DispatchQueue.main.async { self?.handleChunk(data) }
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
            let cap = AppAudioCapturer(target: nil)
            appCapturer = cap
            cap.start(onChunk: onChunk, onLevel: onLevel) { [weak self] error in
                DispatchQueue.main.async { self?.fail(error) }
            }
        case .app(let info):
            let cap = AppAudioCapturer(target: info)
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
            self.inputLevel = level
            self.soundGate(level)
        }
    }

    /// Sound gate: wake on sound instantly, go to standby after sustained silence.
    private func soundGate(_ level: Float) {
        guard isRunning else { return }
        if level > soundGateLevel {
            lastSoundAt = Date()
            if suspended { wake() }
        } else if !suspended,
                  status != .translating,
                  Date().timeIntervalSince(lastSoundAt) > standbyAfterSilence {
            standby()
        }
    }

    private func pushOutputLevel(_ level: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastOutputLevelPush) > 0.033 else { return }
        lastOutputLevelPush = now
        DispatchQueue.main.async {
            self.outputLevel = level
            // translated speech playing counts as activity — don't doze mid-sentence
            if level > self.soundGateLevel {
                self.lastSoundAt = Date()
            }
        }
    }

}
