import AVFoundation

/// Converts arbitrary PCM buffers to 24 kHz mono Int16 chunks for the Realtime API
/// and reports an RMS level for visualization.
final class AudioChunker {
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000,
        channels: 1,
        interleaved: true
    )!

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var pendingPCM = Data()

    /// Keep WebSocket appends small and regular. Core Audio process taps may
    /// deliver several hundred milliseconds at once; forwarding that whole
    /// buffer makes the realtime model wait for the next large packet. 40 ms
    /// gives the streaming translator the earliest practical look at new
    /// speech while remaining comfortably above individual audio frames.
    private static let packetBytes = Int(targetFormat.sampleRate * 0.04)
        * MemoryLayout<Int16>.size

    func process(_ buffer: AVAudioPCMBuffer, onChunk: (Data) -> Void, onLevel: (Float) -> Void) {
        onLevel(Self.rmsLevel(of: buffer))

        if converter == nil || inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: Self.targetFormat)
        }
        guard let converter else { return }

        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData else { return }
        pendingPCM.append(
            Data(bytes: samples[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
        )

        while pendingPCM.count >= Self.packetBytes {
            onChunk(Data(pendingPCM.prefix(Self.packetBytes)))
            pendingPCM.removeFirst(Self.packetBytes)
        }
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        if let f = buffer.floatChannelData {
            for i in 0..<frames { sum += f[0][i] * f[0][i] }
        } else if let s = buffer.int16ChannelData {
            for i in 0..<frames {
                let v = Float(s[0][i]) / 32768
                sum += v * v
            }
        } else {
            return 0
        }
        // Map RMS to a 0…1 range that feels good for speech
        return min(1, sqrt(sum / Float(frames)) * 6)
    }
}
