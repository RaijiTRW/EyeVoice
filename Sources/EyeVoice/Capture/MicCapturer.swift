import AVFoundation

final class MicCapturer {
    private let engine = AVAudioEngine()
    private let chunker = AudioChunker()
    private var running = false

    func start(
        onChunk: @escaping (Data) -> Void,
        onLevel: @escaping (Float) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                onFailure("microphone access denied — enable it in System Settings → Privacy & Security")
                return
            }
            DispatchQueue.main.async {
                do {
                    let input = self.engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0 else {
                        onFailure("no audio input device found")
                        return
                    }
                    input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                        self.chunker.process(buffer, onChunk: onChunk, onLevel: onLevel)
                    }
                    try self.engine.start()
                    self.running = true
                } catch {
                    onFailure("mic engine failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
