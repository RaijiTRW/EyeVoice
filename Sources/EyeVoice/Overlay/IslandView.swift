import SwiftUI

/// Bottom island: waveform reacting to sound + status + live transcript.
struct IslandView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                EyeStatusView(status: state.status)

                WaveformView()
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)

                Text(state.statusLabel)
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundColor(state.status == .translating ? Theme.text : Theme.dim)
                    .frame(width: 92, alignment: .trailing)
            }

            Text(state.transcript.isEmpty ? "· · ·" : state.transcript)
                .font(Theme.mono(10))
                .foregroundColor(Theme.dim)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.border, lineWidth: 1)
                )
        )
        .padding(6)
        .allowsHitTesting(false)
    }
}

/// Symmetric bar waveform driven by input (listening) or output (translating) level.
struct WaveformView: View {
    @EnvironmentObject var state: AppState
    @State private var history: [Float] = Array(repeating: 0, count: 46)

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { context, size in
            let count = history.count
            let step = size.width / CGFloat(count)
            let barWidth = max(1.5, step * 0.45)
            for (i, level) in history.enumerated() {
                let h = max(2, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(i) * step + (step - barWidth) / 2,
                    y: (size.height - h) / 2,
                    width: barWidth,
                    height: h
                )
                let alpha = 0.25 + 0.75 * Double(level)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .onReceive(timer) { _ in
            let raw = max(state.inputLevel, state.outputLevel)
            // slight jitter so quiet speech still looks alive
            let jitter = raw > 0.02 ? Float.random(in: 0.85...1.15) : 1
            let value = min(1, raw * jitter)
            history.removeFirst()
            history.append(value)
        }
    }
}
