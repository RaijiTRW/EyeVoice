import AVFoundation

/// Plays 24 kHz mono PCM16 chunks streamed from the Realtime API.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let gainUnit = AVAudioUnitEQ(numberOfBands: 0)
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private let queue = DispatchQueue(label: "eyevoice.audio-output", qos: .userInitiated)
    private var started = false
    private let lock = NSLock()
    private var pendingSeconds: Double = 0

    var onLevel: ((Float) -> Void)?

    /// Seconds of translation audio scheduled but not played yet (the live lag).
    var backlogSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return pendingSeconds
    }

    init() {
        engine.attach(node)
        engine.attach(gainUnit)
        engine.connect(node, to: gainUnit, format: format)
        engine.connect(gainUnit, to: engine.mainMixerNode, format: format)
    }

    func enqueue(pcm16 data: Data) {
        queue.async { [weak self] in
            self?.enqueueOnAudioQueue(pcm16: data)
        }
    }

    func setVolume(_ volume: Float) {
        queue.async { [weak self] in
            guard let self else { return }
            let normalized = min(1, max(0, volume))
            if normalized <= 0.001 {
                self.node.volume = 0
                self.gainUnit.globalGain = 0
                return
            }

            // The former maximum is now the 20% reference point. Above it,
            // apply clean floating-point gain in the audio graph up to 5×
            // (+13.98 dB) at 100% instead of clipping PCM16 samples manually.
            let linearGain = normalized / 0.2
            self.node.volume = 1
            self.gainUnit.globalGain = 20 * log10(linearGain)
        }
    }

    private func enqueueOnAudioQueue(pcm16 data: Data) {
        let frames = data.count / MemoryLayout<Int16>.size
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        var sum: Float = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            let out = buffer.floatChannelData![0]
            for i in 0..<frames {
                let v = Float(samples[i]) / 32768
                out[i] = v
                sum += v * v
            }
        }
        onLevel?(min(1, sqrt(sum / Float(frames)) * 6))

        let duration = Double(frames) / format.sampleRate
        lock.lock()
        pendingSeconds += duration
        lock.unlock()

        startIfNeeded()
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.pendingSeconds = max(0, self.pendingSeconds - duration)
            self.lock.unlock()
        }
        if !node.isPlaying { node.play() }
    }

    /// Drop everything queued — used to skip stale translation and jump back to "live".
    func flush() {
        queue.async { [weak self] in
            guard let self, self.started else { return }
            self.node.stop()
            self.lock.lock()
            self.pendingSeconds = 0
            self.lock.unlock()
            self.node.play()
            self.onLevel?(0)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.started {
                self.node.stop()
                self.engine.stop()
                self.started = false
            }
            self.lock.lock()
            self.pendingSeconds = 0
            self.lock.unlock()
            self.onLevel?(0)
        }
    }

    private func startIfNeeded() {
        guard !started else { return }
        do {
            try engine.start()
            started = true
        } catch {
            NSLog("EyeVoice: audio output failed to start: \(error)")
        }
    }
}
