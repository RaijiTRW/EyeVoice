import Foundation

/// WebSocket client for the OpenAI Realtime Translation API.
/// Streams source audio continuously and receives translated audio + transcript
/// deltas while the speaker is still talking (true simultaneous interpretation).
final class RealtimeClient: NSObject, TranslatorClient {
    private let apiKey: String
    private let model: String
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

    init(apiKey: String, model: String, targetLanguage: String) {
        self.apiKey = apiKey
        self.model = model
        self.targetLanguage = targetLanguage
    }

    func connect() {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime/translations?model=\(model)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveLoop()
    }

    func disconnect() {
        closed = true
        // ask the server to flush and close cleanly, then drop the socket
        sendJSON(["type": "session.close"])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) { [task, session] in
            task?.cancel(with: .normalClosure, reason: nil)
            session?.invalidateAndCancel()
        }
        task = nil
        self.session = nil
    }

    func sendAudio(_ pcm16: Data) {
        sendJSON([
            "type": "session.input_audio_buffer.append",
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

        case "session.output_audio.delta":
            if let b64 = json["delta"] as? String, let audio = Data(base64Encoded: b64) {
                onAudio?(audio)
            }

        case "session.output_transcript.delta":
            if let delta = json["delta"] as? String {
                onTranscriptDelta?(delta)
            }

        case "session.input_transcript.delta":
            onInputActivity?()

        case "session.closed":
            break

        case "error":
            let err = json["error"] as? [String: Any]
            let message = err?["message"] as? String ?? "unknown API error"
            onError?(message)

        default:
            break
        }
    }
}

extension RealtimeClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        sendJSON([
            "type": "session.update",
            "session": [
                "audio": [
                    "output": ["language": targetLanguage],
                ],
            ],
        ])
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
