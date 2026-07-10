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

    func toggle(voice: String, language: String, apiKey: String) {
        switch state {
        case .playing, .loading:
            stop()
        case .idle:
            play(voice: voice, language: language, apiKey: apiKey)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        state = .idle
    }

    private func play(voice: String, language: String, apiKey: String) {
        // samples for all voices ship inside the app bundle — no API call needed
        if let bundled = Bundle.main.url(forResource: "voice-\(voice)-\(language)", withExtension: "mp3") {
            playFile(bundled, voice: voice)
            return
        }

        // fallback for voices without a bundled sample: fetch once, cache on disk
        let file = cacheDir.appendingPathComponent("voice-\(voice)-\(language).mp3")
        if FileManager.default.fileExists(atPath: file.path) {
            playFile(file, voice: voice)
            return
        }

        state = .loading(voice)
        let phrase = language == "ru"
            ? "Привет, я \(voice). Вот так будет звучать твой живой перевод."
            : "Hi, I'm \(voice). This is how your live translation will sound."
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": phrase,
            "response_format": "mp3",
        ])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self, self.state == .loading(voice) else { return }
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200 else {
                    self.state = .idle
                    return
                }
                try? data.write(to: file)
                self.playFile(file, voice: voice)
            }
        }.resume()
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
