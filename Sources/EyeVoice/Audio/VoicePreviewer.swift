import AVFoundation

/// Plays a short TTS sample of a voice; samples are cached on disk after first fetch.
final class VoicePreviewer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum PreviewState: Equatable {
        case idle
        case loading(String)
        case playing(String)
    }

    @Published var state: PreviewState = .idle

    private var player: AVAudioPlayer?

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EyeVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func toggle(voice: String, language: String) {
        switch state {
        case .playing, .loading:
            stop()
        case .idle:
            play(voice: voice, language: language)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        state = .idle
    }

    private func play(voice: String, language: String) {
        // samples for all voices ship inside the app bundle — no API call needed
        if let bundled = Bundle.main.url(forResource: "voice-\(voice)-\(language)", withExtension: "mp3") {
            playFile(bundled, voice: voice)
            return
        }

        // Previously cached samples remain available without exposing a provider key.
        let file = cacheDir.appendingPathComponent("voice-\(voice)-\(language).mp3")
        if FileManager.default.fileExists(atPath: file.path) {
            playFile(file, voice: voice)
            return
        }
        state = .idle
    }

    private func playFile(_ url: URL, voice: String) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            state = .idle
            return
        }
        player.delegate = self
        self.player = player
        player.play()
        state = .playing(voice)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.player = nil
            self.state = .idle
        }
    }
}
