import AudioToolbox
import AVFoundation
import CoreAudio
import Darwin

/// Captures one application, or the whole system mix, with a Core Audio
/// process tap. Unlike ScreenCaptureKit this is audio-only and therefore does
/// not require Screen Recording access.
final class AppAudioCapturer {
    private let target: AppInfo?
    private var sourceMuted: Bool
    private let chunker = AudioChunker()
    private let queue = DispatchQueue(label: "eyevoice.core-audio-tap", qos: .userInitiated)

    private var processTapID = AudioObjectID(kAudioObjectUnknown)
    private var tapDescription: CATapDescription?
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?

    private var onChunk: ((Data) -> Void)?
    private var onLevel: ((Float) -> Void)?
    private var onFailure: ((String) -> Void)?

    init(target: AppInfo?, sourceMuted: Bool = false) {
        self.target = target
        self.sourceMuted = sourceMuted
    }

    func start(
        onChunk: @escaping (Data) -> Void,
        onLevel: @escaping (Float) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        self.onChunk = onChunk
        self.onLevel = onLevel
        self.onFailure = onFailure

        guard #available(macOS 14.2, *) else {
            onFailure("system audio capture requires macOS 14.2 or newer")
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.prepareAndStart()
            } catch {
                self.teardown()
                onFailure("audio capture failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        onChunk = nil
        onLevel = nil
        onFailure = nil
        queue.async { [weak self] in self?.teardown() }
    }

    /// Changes only local playback of the tapped source. The process tap keeps
    /// receiving the same audio, so translation continues while the original
    /// application becomes silent for the user.
    func setSourceMuted(_ muted: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            guard #available(macOS 14.2, *) else { return }
            guard self.sourceMuted != muted else { return }
            self.sourceMuted = muted

            // AudioHardwareCreateProcessTap copies CATapDescription. Mutating
            // the description afterwards does not update the live tap, so
            // recreate only the Core Audio leg while keeping the Realtime
            // connection and all capture callbacks alive.
            guard self.processTapID != kAudioObjectUnknown else { return }
            self.teardown()
            do {
                try self.prepareAndStart()
                AppState.logToFile(
                    muted
                        ? "capture: original source playback muted"
                        : "capture: original source playback restored"
                )
            } catch {
                self.teardown()
                self.onFailure?("audio output switch failed: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        teardown()
    }

    @available(macOS 14.2, *)
    private func prepareAndStart() throws {
        let tapDescription: CATapDescription
        if let target {
            let processIDs = try Self.processObjectIDs(for: target)
            tapDescription = CATapDescription(monoMixdownOfProcesses: processIDs)
            AppState.logToFile(
                "capture: \(target.name) process tree, \(processIDs.count) capturable process(es)"
            )
        } else {
            let ownProcessID = try? Self.processObjectID(for: ProcessInfo.processInfo.processIdentifier)
            tapDescription = CATapDescription(
                monoGlobalTapButExcludeProcesses: ownProcessID.map { [$0] } ?? []
            )
        }

        tapDescription.name = target.map { "EyeVoice – \($0.name)" } ?? "EyeVoice – System Audio"
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = sourceMuted ? .muted : .unmuted
        self.tapDescription = tapDescription

        try Self.check(
            AudioHardwareCreateProcessTap(tapDescription, &processTapID),
            operation: "create Core Audio process tap"
        )

        var tapASBD: AudioStreamBasicDescription = try Self.read(
            objectID: processTapID,
            selector: kAudioTapPropertyFormat,
            defaultValue: AudioStreamBasicDescription()
        )
        guard let tapFormat = AVAudioFormat(streamDescription: &tapASBD) else {
            throw CaptureError.message("Core Audio returned an invalid tap format")
        }

        let outputDevice: AudioDeviceID = try Self.read(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            defaultValue: AudioDeviceID(kAudioObjectUnknown)
        )
        guard outputDevice != kAudioObjectUnknown else {
            throw CaptureError.message("no system output audio device found")
        }
        let outputUID: CFString = try Self.read(
            objectID: outputDevice,
            selector: kAudioDevicePropertyDeviceUID,
            defaultValue: "" as CFString
        )

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EyeVoice Audio Tap",
            kAudioAggregateDeviceUIDKey: "com.aleksey.eyevoice.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        try Self.check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID),
            operation: "create Core Audio aggregate device"
        )

        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inputData, _, _, _ in
            guard let self,
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: tapFormat,
                    bufferListNoCopy: inputData,
                    deallocator: nil
                  ) else { return }

            self.chunker.process(
                buffer,
                onChunk: { [weak self] data in self?.onChunk?(data) },
                onLevel: { [weak self] level in self?.onLevel?(level) }
            )
        }

        try Self.check(
            AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock),
            operation: "create Core Audio I/O callback"
        )
        try Self.check(
            AudioDeviceStart(aggregateDeviceID, deviceProcID),
            operation: "start Core Audio process tap"
        )
    }

    private func teardown() {
        guard #available(macOS 14.2, *) else { return }
        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if let deviceProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                self.deviceProcID = nil
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if processTapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(processTapID)
            processTapID = AudioObjectID(kAudioObjectUnknown)
        }
        tapDescription = nil
    }

    private static func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let objectID: AudioObjectID = try read(
            objectID: system,
            selector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            defaultValue: AudioObjectID(kAudioObjectUnknown),
            qualifier: pid
        )
        guard objectID != kAudioObjectUnknown else {
            throw CaptureError.message("application process is not producing capturable audio")
        }
        return objectID
    }

    /// Chromium-based browsers and many media apps render audio in helper processes.
    /// Capture the selected app plus its current descendant process tree so tab/video
    /// audio is included instead of tapping only the silent UI process.
    private static func processObjectIDs(for target: AppInfo) throws -> [AudioObjectID] {
        let processIDs = descendantProcessIDs(of: target.pid)
        let audioObjects = processIDs.compactMap { try? processObjectID(for: $0) }
        let uniqueObjects = Array(Set(audioObjects))

        guard !uniqueObjects.isEmpty else {
            throw CaptureError.message("\(target.name) is not producing capturable audio")
        }
        return uniqueObjects
    }

    private static func descendantProcessIDs(of rootPID: pid_t) -> [pid_t] {
        var discovered: [pid_t] = [rootPID]
        var pending: [pid_t] = [rootPID]
        var seen: Set<pid_t> = [rootPID]

        while !pending.isEmpty {
            let parent = pending.removeFirst()
            let estimatedCount = Int(proc_listchildpids(parent, nil, 0))
            guard estimatedCount > 0 else { continue }

            var children = [pid_t](repeating: 0, count: estimatedCount)
            let actualCount = children.withUnsafeMutableBytes { bytes in
                Int(proc_listchildpids(parent, bytes.baseAddress, Int32(bytes.count)))
            }

            for child in children.prefix(max(0, min(actualCount, children.count))) where child > 0 {
                if seen.insert(child).inserted {
                    discovered.append(child)
                    pending.append(child)
                }
            }
        }

        return discovered
    }

    private static func read<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        defaultValue: T
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        try check(status, operation: "read Core Audio property \(selector)")
        return value
    }

    private static func read<T, Q>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        defaultValue: T,
        qualifier: Q
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var qualifier = qualifier
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
            withUnsafeMutablePointer(to: &value) { valuePointer in
                AudioObjectGetPropertyData(
                    objectID,
                    &address,
                    UInt32(MemoryLayout<Q>.size),
                    qualifierPointer,
                    &size,
                    valuePointer
                )
            }
        }
        try check(status, operation: "translate process identifier")
        return value
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw CaptureError.message("\(operation) failed (OSStatus \(status))")
        }
    }
}

private enum CaptureError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
