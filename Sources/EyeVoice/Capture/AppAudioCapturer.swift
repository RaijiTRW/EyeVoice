import AVFoundation
import ScreenCaptureKit

/// Captures audio of a single application (or all system audio) via ScreenCaptureKit.
/// Requires the Screen Recording permission.
final class AppAudioCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    private let target: AppInfo?
    private var stream: SCStream?
    private let chunker = AudioChunker()
    private let queue = DispatchQueue(label: "eyevoice.appcapture")

    private var onChunk: ((Data) -> Void)?
    private var onLevel: ((Float) -> Void)?
    private var onFailure: ((String) -> Void)?

    init(target: AppInfo?) {
        self.target = target
    }

    func start(
        onChunk: @escaping (Data) -> Void,
        onLevel: @escaping (Float) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        self.onChunk = onChunk
        self.onLevel = onLevel
        self.onFailure = onFailure

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    onFailure("no display found")
                    return
                }

                let filter: SCContentFilter
                if let target {
                    guard let app = content.applications.first(where: { $0.processID == target.pid }) else {
                        onFailure("app \"\(target.name)\" not capturable — is it still running?")
                        return
                    }
                    filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                } else {
                    filter = SCContentFilter(display: display, excludingWindows: [])
                }

                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 24000
                config.channelCount = 1
                // We only consume audio; keep the mandatory video leg as tiny as possible
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 5)

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                try await stream.startCapture()
                self.stream = stream
            } catch {
                onFailure("audio capture failed: \(error.localizedDescription)\nCheck Screen Recording permission in System Settings → Privacy & Security.")
            }
        }
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        onChunk = nil
        onLevel = nil
        onFailure = nil
        Task { try? await stream?.stopCapture() }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              let onChunk, let onLevel,
              let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        chunker.process(pcm, onChunk: onChunk, onLevel: onLevel)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure?("capture stopped: \(error.localizedDescription)")
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}
