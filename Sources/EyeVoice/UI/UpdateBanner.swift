import SwiftUI

struct UpdateBanner: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var updates: UpdateManager

    var body: some View {
        if let version = updates.availableVersion {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.uiLanguage == .ru ? "ДОСТУПНО ОБНОВЛЕНИЕ" : "UPDATE AVAILABLE")
                        .font(Theme.mono(8, weight: .bold))
                        .tracking(1)
                        .foregroundColor(Theme.faint)
                    Text("EyeVoice \(version)")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundColor(Theme.text)
                }

                Spacer(minLength: 8)

                Button(state.uiLanguage == .ru ? "ПОЗЖЕ" : "LATER") {
                    withAnimation(.easeOut(duration: 0.18)) {
                        updates.remindLater()
                    }
                }
                .buttonStyle(UpdateBannerSecondaryButtonStyle())

                Button(state.uiLanguage == .ru ? "ОБНОВИТЬ" : "UPDATE") {
                    updates.installAvailableUpdate()
                }
                .buttonStyle(UpdateBannerPrimaryButtonStyle())
            }
            .padding(12)
            .frame(width: 440)
            .background(Color(red: 0.055, green: 0.052, blue: 0.055).opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.34), radius: 22, y: 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}

private struct UpdateBannerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(8, weight: .bold))
            .foregroundColor(Theme.bg)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct UpdateBannerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(8, weight: .bold))
            .foregroundColor(Theme.dim)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .opacity(configuration.isPressed ? 0.58 : 1)
    }
}
