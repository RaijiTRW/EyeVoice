import SwiftUI

/// Interactive bottom island: live waveform, session controls and transcript.
struct IslandView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.overlayCollapsed {
                collapseButton
            } else {
                VStack(spacing: 4) {
                    panel
                        .frame(height: 94)
                    collapseButton
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 6)
        .clipped()
        .animation(.easeOut(duration: 0.18), value: state.overlayCollapsed)
    }

    private var collapseButton: some View {
        Button {
            state.overlayCollapsed.toggle()
        } label: {
            Image(systemName: state.overlayCollapsed ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 52, height: 20)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.9))
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .help(state.overlayCollapsed ? "Показать панель перевода" : "Скрыть панель перевода")
        .accessibilityLabel(state.overlayCollapsed ? "Показать панель" : "Скрыть панель")
    }

    private var panel: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                EyeStatusView(status: state.status)

                WaveformView()
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)

                SessionTimerView(state: state)

                Text(state.statusLabel)
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundColor(state.status == .translating ? Theme.text : Theme.dim)
                    .frame(width: 76, alignment: .trailing)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        state.dimmingEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: state.dimmingEnabled ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12, weight: .semibold))
                        Text("DIM")
                            .font(Theme.mono(8, weight: .semibold))
                    }
                    .foregroundStyle(state.dimmingEnabled ? Theme.accent : Theme.dim)
                    .frame(height: 26)
                    .padding(.horizontal, 7)
                    .background(controlBackground)
                }
                .buttonStyle(.plain)
                .help(state.dimmingEnabled ? "Выключить затемнение" : "Включить затемнение")
                .accessibilityLabel("Затемнение экрана")
                .accessibilityValue(state.dimmingEnabled ? "Включено" : "Выключено")

                Button {
                    state.sourceAudioMuted.toggle()
                } label: {
                    ZStack {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .semibold))
                        if state.sourceAudioMuted {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: 15, height: 1.5)
                                .rotationEffect(.degrees(-45))
                        }
                    }
                    .foregroundStyle(state.sourceAudioMuted ? Theme.accent : Theme.text)
                    .frame(width: 28, height: 26)
                    .background(controlBackground)
                }
                .buttonStyle(.plain)
                .disabled(!state.canMuteSourceAudio)
                .opacity(state.canMuteSourceAudio ? 1 : 0.35)
                .help(
                    state.sourceAudioMuted
                        ? "Включить оригинальный звук"
                        : "Слышать только перевод"
                )
                .accessibilityLabel("Оригинальный звук приложения")
                .accessibilityValue(state.sourceAudioMuted ? "Выключен" : "Включен")

                VolumeHoverControl(settings: state.outputSettings)

                Button {
                    state.toggle()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 28, height: 26)
                        .background(controlBackground)
                }
                .buttonStyle(.plain)
                .help("Остановить перевод")
                .accessibilityLabel("Остановить перевод")
            }

            Text(state.transcript.isEmpty ? "· · ·" : state.transcript)
                .font(Theme.mono(9))
                .foregroundColor(Theme.dim)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.border, lineWidth: 1)
                )
        )
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

private struct VolumeHoverControl: View {
    @ObservedObject var settings: AudioOutputSettings
    @State private var isPresented = false
    @State private var dismissWorkItem: DispatchWorkItem?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: speakerIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(settings.volume > 0 ? Theme.text : Theme.dim)
                .frame(width: 28, height: 26)
                .background(controlBackground)
        }
        .buttonStyle(.plain)
        .onHover(perform: handleButtonHover)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                Slider(value: $settings.volume, in: 0...1)
                    .tint(Theme.accent)
                    .frame(width: 118)

                Text("\(Int((settings.volume * 100).rounded()))%")
                    .font(Theme.mono(9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.96))
            .onHover { hovering in
                if hovering {
                    present()
                } else {
                    scheduleDismiss()
                }
            }
        }
        .help("Громкость перевода")
        .accessibilityLabel("Громкость перевода")
        .accessibilityValue("\(Int((settings.volume * 100).rounded())) процентов")
    }

    private var speakerIcon: String {
        switch settings.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    private func handleButtonHover(_ hovering: Bool) {
        if hovering {
            present()
        } else {
            scheduleDismiss()
        }
    }

    private func present() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        isPresented = true
    }

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isPresented = false
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
    }
}

private struct SessionTimerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.formatted(state.currentSessionUsage(at: context.date)))
                .font(Theme.mono(9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(width: 46, alignment: .trailing)
        }
        .accessibilityLabel("Время перевода")
    }

    private static func formatted(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Symmetric bar waveform driven by input (listening) or output (translating) level.
struct WaveformView: View {
    @EnvironmentObject private var meter: AudioMeterState
    @State private var history: [Float] = Array(repeating: 0, count: 38)

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { context, size in
            let count = history.count
            let step = size.width / CGFloat(count)
            let barWidth = max(1.5, step * 0.45)
            for (i, level) in history.enumerated() {
                let height = max(2, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(i) * step + (step - barWidth) / 2,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let alpha = 0.25 + 0.75 * Double(level)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .onReceive(timer) { _ in
            let raw = max(meter.input, meter.output)
            let jitter = raw > 0.02 ? Float.random(in: 0.85...1.15) : 1
            history.removeFirst()
            history.append(min(1, raw * jitter))
        }
    }
}
