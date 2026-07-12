import Foundation

/// Voice-agent pipeline (gpt-realtime-2.1-mini): translates phrase by phrase with
/// a selectable voice. Slightly higher latency than the streaming interpreter.
final class VoiceRealtimeClient: NSObject, TranslatorClient {
    private let apiKey: String
    private let model: String
    private let voice: String
    private let targetLanguage: String
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var closed = false

    var onAudio: ((Data) -> Void)?
    var onTranscriptDelta: ((String) -> Void)?
    var onInputActivity: (() -> Void)?
    var onConnected: (() -> Void)?
    var onError: ((String) -> Void)?
    var onSegmentStart: (() -> Void)?

    init(apiKey: String, model: String, voice: String, targetLanguage: String) {
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.targetLanguage = targetLanguage
    }

    func connect() {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveLoop()
    }

    private func configureSession() {
        let instructions = """
        You are a professional simultaneous interpreter. \
        Translate everything you hear into \(targetLanguage). \
        Speak ONLY the translation — natural, fluent, preserving the speaker's tone and intent. \
        Never answer questions, never comment, never add anything of your own. \
        If the input is already in \(targetLanguage), stay silent.
        """

        sendJSON([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "output_modalities": ["audio"],
                "instructions": instructions,
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 250,
                            "create_response": true,
                            "interrupt_response": false,
                        ],
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "voice": voice,
                        "speed": 1.1,
                    ],
                ],
            ],
        ])
    }

    func disconnect() {
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    func sendAudio(_ pcm16: Data) {
        sendJSON([
            "type": "input_audio_buffer.append",
            "audio": pcm16.base64EncodedString(),
        ])
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if error != nil, let self, !self.closed {
                self.onError?("connection lost while sending audio")
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .failure(let error):
                self.onError?("connection lost: \(error.localizedDescription)")
            case .success(let message):
                if case .string(let text) = message, let data = text.data(using: .utf8) {
                    self.handle(data)
                }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.created":
            break

        case "session.updated":
            onConnected?()

        case "input_audio_buffer.speech_started", "conversation.item.input_audio_transcription.delta":
            onInputActivity?()

        case "response.output_audio.delta", "response.audio.delta":
            if let b64 = json["delta"] as? String, let audio = Data(base64Encoded: b64) {
                onAudio?(audio)
            }

        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                onTranscriptDelta?(delta)
            }

        case "response.created":
            onSegmentStart?()

        case "error":
            let err = json["error"] as? [String: Any]
            let message = err?["message"] as? String ?? "unknown API error"
            if (err?["code"] as? String) == "response_cancel_not_active" { return }
            onError?(message)

        default:
            break
        }
    }
}

extension VoiceRealtimeClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        configureSession()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard !closed else { return }
        let detail = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        onError?("socket closed (\(closeCode.rawValue)) \(detail)")
    }
}
