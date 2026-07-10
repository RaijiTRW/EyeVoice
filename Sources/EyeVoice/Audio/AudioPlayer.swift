import AVFoundation

/// Plays 24 kHz mono PCM16 chunks streamed from the Realtime API.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
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
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    /// Catch-up: play slightly faster (pitch-preserved) while a backlog exists,
    /// so the translation stays glued to the live audio.
    private func adjustRate() {
        let backlog: Double
        lock.lock()
        backlog = pendingSeconds
        lock.unlock()

        let rate: Float
        switch backlog {
        case ..<0.5: rate = 1.0
        case ..<1.2: rate = 1.07
        case ..<2.5: rate = 1.15
        default: rate = 1.25
        }
        if timePitch.rate != rate {
            timePitch.rate = rate
        }
    }

    func enqueue(pcm16 data: Data) {
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
        adjustRate()
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.pendingSeconds = max(0, self.pendingSeconds - duration)
            self.lock.unlock()
            self.adjustRate()
        }
        if !node.isPlaying { node.play() }
    }

    /// Drop everything queued — used to skip stale translation and jump back to "live".
    func flush() {
        guard started else { return }
        node.stop()
        lock.lock()
        pendingSeconds = 0
        lock.unlock()
        node.play()
        onLevel?(0)
    }

    func stop() {
        if started {
            node.stop()
            engine.stop()
            started = false
        }
        onLevel?(0)
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
