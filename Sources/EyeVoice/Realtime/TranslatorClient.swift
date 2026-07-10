import Foundation

/// Common interface for both translation backends:
/// the streaming interpreter and the voice-agent (custom voice) pipeline.
protocol TranslatorClient: AnyObject {
    var onAudio: ((Data) -> Void)? { get set }
    var onTranscriptDelta: ((String) -> Void)? { get set }
    var onConnected: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    /// Fires when a new translated segment begins (voice mode only).
    var onSegmentStart: (() -> Void)? { get set }

    func connect()
    func disconnect()
    func sendAudio(_ pcm16: Data)
}
