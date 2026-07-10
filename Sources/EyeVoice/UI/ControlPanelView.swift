import SwiftUI
import AppKit

enum SourceTab: CaseIterable {
    case mic, system, apps
}

struct ControlPanelView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var auth = SupabaseAuthManager.shared
    @StateObject private var previewer = VoicePreviewer()
    @State private var tab: SourceTab = .mic
    @State private var hoveredID: String?
    @Namespace private var segmentNS

    private var loc: Strings { state.loc }

    var body: some View {
        Group {
            if auth.isCheckingSession {
                miniAuthLoading
            } else if auth.isAuthenticated {
                controls
            } else {
                miniSignedOut
            }
        }
        .frame(width: 340, height: 520)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            switch state.selectedSource {
            case .microphone: tab = .mic
            case .systemAudio: tab = .system
            case .app: tab = .apps
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            asciiRule
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourceSection
                    languageSection
                    if let error = state.errorMessage {
                        Text("ERR  \(error)")
                            .font(Theme.mono(10))
                            .foregroundColor(Theme.text)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.panel.opacity(0.6))
                            .panelCard(radius: 9)
                    }
                }
                .padding(16)
            }
            asciiRule
            footer
        }
    }

    private var miniAuthLoading: some View {
        VStack(spacing: 14) {
            EyeStatusView(status: .connecting, width: 42)
            Text("•  •  •")
                .font(Theme.mono(9))
                .foregroundColor(Theme.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var miniSignedOut: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                EyeGlyph(width: 18, color: Theme.accent)
                Text("EYEVOICE")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            .padding(16)

            asciiRule

            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RadialGradient(
                        colors: [Theme.accent.opacity(0.13), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 135
                    )
                    AnimatedAsciiEye(
                        width: 300,
                        height: 188,
                        columns: 48,
                        rows: 26
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(state.uiLanguage == .ru ? "Нужен аккаунт" : "Account required")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.text)

                    Text(state.uiLanguage == .ru
                         ? "Войдите или зарегистрируйтесь в основном окне EyeVoice, чтобы начать перевод."
                         : "Log in or create an account in the main EyeVoice window to start translating.")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.dim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    openMainWindow()
                } label: {
                    Text(state.uiLanguage == .ru ? "ОТКРЫТЬ ВХОД" : "OPEN LOGIN")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundColor(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func openMainWindow() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "EyeVoice" }) else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                EyeGlyph(width: 18)
                Text("EYEVOICE")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            Spacer()
            HStack(spacing: 6) {
                EyeStatusView(status: state.status)
                Text(state.statusLabel)
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.dim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var asciiRule: some View {
        Rectangle()
            .fill(Theme.border.opacity(0.5))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HoverScaleButton(disabled: state.apiKey.isEmpty) {
                state.toggle()
            } label: { hovered in
                Text(state.isRunning ? loc.stop : loc.start)
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundColor(state.isRunning || hovered ? Theme.bg : Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(state.isRunning || hovered ? Theme.text : Theme.bg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.text, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }

            HStack(spacing: 10) {
                languageToggle
                Spacer(minLength: 8)
                Button(loc.quit) { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.dim)
            }
        }
        .padding(16)
    }

    private var languageToggle: some View {
        HStack(spacing: 5) {
            langButton("RU", .ru)
            langButton("EN", .en)
        }
    }

    private func langButton(_ title: String, _ lang: UILanguage) -> some View {
        let selected = state.uiLanguage == lang
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { state.uiLanguage = lang }
        } label: {
            HStack(spacing: 6) {
                LanguageFlag(language: lang, width: 18)
                Text(title)
                    .font(Theme.mono(9, weight: .bold))
            }
            .foregroundColor(selected ? Theme.bg : Theme.dim)
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(selected ? Theme.accent : Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(lang == .ru ? "Русский" : "English")
    }

    // MARK: - Source

    private func tabTitle(_ t: SourceTab) -> String {
        switch t {
        case .mic: return loc.tabMic
        case .system: return loc.tabSystem
        case .apps: return loc.tabApps
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(loc.audioSource)
            segmentedTabs
            Group {
                switch tab {
                case .mic:
                    infoCard(systemImage: "mic.fill", title: loc.micTitle, subtitle: loc.micSub)
                case .system:
                    infoCard(systemImage: "speaker.wave.2.fill", title: loc.systemTitle, subtitle: loc.systemSub)
                case .apps:
                    appList
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
            Text(loc.permissionHint)
                .font(Theme.mono(9))
                .foregroundColor(Theme.faint)
        }
    }

    private var segmentedTabs: some View {
        HStack(spacing: 2) {
            ForEach(SourceTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        tab = t
                        selectTab(t)
                    }
                } label: {
                    Text(tabTitle(t))
                        .font(Theme.mono(10, weight: tab == t ? .bold : .regular))
                        .foregroundColor(tab == t ? Theme.bg : Theme.dim)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if tab == t {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.text)
                                    .matchedGeometryEffect(id: "segment", in: segmentNS)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.isRunning)
            }
        }
        .padding(3)
        .background(Theme.panel.opacity(0.6))
        .panelCard(radius: 9)
    }

    private func selectTab(_ t: SourceTab) {
        switch t {
        case .mic:
            state.selectedSourceID = "mic"
        case .system:
            state.selectedSourceID = "system"
        case .apps:
            state.refreshApps()
            // keep previous app selection if it still exists
            if !state.selectedSourceID.hasPrefix("app:"),
               let first = state.runningApps.first {
                state.selectedSourceID = first.id
            }
        }
    }

    private func infoCard(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.text)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(white: 0.13))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            Text("[x]")
                .font(Theme.mono(10))
                .foregroundColor(Theme.text)
        }
        .padding(12)
        .background(Theme.panel)
        .panelCard(radius: 10)
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.runningApps) { app in
                        appCard(app)
                    }
                }
                .padding(1)
            }
            .scrollIndicators(.hidden)

            if !state.browserTabs.isEmpty {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        tabRow(nil)
                        ForEach(state.browserTabs) { browserTab in
                            tabRow(browserTab)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .frame(height: 120)
                .background(Theme.panel.opacity(0.5))
                .panelCard(radius: 9)
                Text(loc.tabHint)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.faint)
            }
        }
    }

    private func tabRow(_ browserTab: BrowserTab?) -> some View {
        let selected = state.selectedTabID == browserTab?.id
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                state.selectedTabID = browserTab?.id
            }
        } label: {
            HStack(spacing: 8) {
                Text(selected ? "█" : "◦")
                    .font(Theme.mono(9))
                    .foregroundColor(selected ? Theme.text : Theme.faint)
                    .frame(width: 10)
                Text(browserTab?.title ?? loc.allTabs)
                    .font(Theme.mono(10, weight: selected ? .bold : .regular))
                    .foregroundColor(selected ? Theme.text : Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if selected {
                    Text("[x]")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.text)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Theme.panel : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isRunning)
    }

    private func appCard(_ app: AppInfo) -> some View {
        let id = app.id
        let selected = state.selectedSourceID == id
        let hovered = hoveredID == id
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                state.selectedSourceID = id
            }
        } label: {
            VStack(spacing: 7) {
                appIcon(for: app, size: 26)
                Text(app.name.uppercased())
                    .font(Theme.mono(8, weight: selected ? .bold : .regular))
                    .foregroundColor(selected || hovered ? Theme.text : Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 72)
            }
            .frame(width: 84, height: 68)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.panel : (hovered ? Color(white: 0.05) : Color.clear))
            )
            .panelCard(radius: 10, color: selected ? Theme.text : Theme.border)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Text("[x]")
                        .font(Theme.mono(8))
                        .foregroundColor(Theme.text)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isRunning)
        .scaleEffect(hovered && !state.isRunning ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { inside in
            hoveredID = inside ? id : (hoveredID == id ? nil : hoveredID)
        }
    }

    @ViewBuilder
    private func appIcon(for app: AppInfo, size: CGFloat = 18) -> some View {
        if let icon = NSRunningApplication(processIdentifier: app.pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.66))
                .foregroundColor(Theme.dim)
                .frame(width: size, height: size)
        }
    }

    // MARK: - Languages

    private static let flags: [String: String] = [
        "Auto": "🌐", "Russian": "🇷🇺", "English": "🇺🇸", "Spanish": "🇪🇸",
        "German": "🇩🇪", "French": "🇫🇷", "Italian": "🇮🇹", "Portuguese": "🇵🇹",
        "Chinese": "🇨🇳", "Japanese": "🇯🇵", "Korean": "🇰🇷", "Ukrainian": "🇺🇦",
        "Turkish": "🇹🇷", "Arabic": "🇸🇦", "Hindi": "🇮🇳",
    ]

    private func flag(_ language: String) -> String {
        Self.flags[language] ?? "⚑"
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(loc.translation)
            HStack(spacing: 8) {
                // source: auto-detected
                HStack(spacing: 6) {
                    Text("🌐")
                        .font(.system(size: 12))
                    Text(loc.languageName("Auto").lowercased())
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.dim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.panel.opacity(0.6))
                .panelCard(radius: 9)

                Text("→")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundColor(Theme.faint)

                // target language
                Menu {
                    ForEach(Array(AppState.languages.dropFirst()), id: \.self) { option in
                        Button("\(flag(option))  \(loc.languageName(option))") {
                            state.targetLanguage = option
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(flag(state.targetLanguage))
                            .font(.system(size: 12))
                        Text(loc.languageName(state.targetLanguage).lowercased())
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Spacer()
                        Text("▾")
                            .font(Theme.mono(9))
                            .foregroundColor(Theme.dim)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(state.isRunning)
                .background(Theme.panel.opacity(0.6))
                .panelCard(radius: 9)
            }
        }
    }

    // MARK: - Voice (parked: shown again when a custom voice pipeline lands)

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(loc.voice)
            HStack(spacing: 8) {
                previewButton
                Menu {
                    ForEach(AppState.voices, id: \.self) { option in
                        Button(option) {
                            previewer.stop()
                            state.voice = option
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.dim)
                        Text(state.voice)
                            .font(Theme.mono(11))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Text("▾")
                            .font(Theme.mono(9))
                            .foregroundColor(Theme.dim)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .border(Theme.border, width: 1)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(state.isRunning)
            }
        }
    }

    private var previewButton: some View {
        let symbol: String
        var pulsing = false
        switch previewer.state {
        case .idle: symbol = "▶"
        case .loading: symbol = "•"; pulsing = true
        case .playing: symbol = "■"
        }
        return Button {
            previewer.toggle(voice: state.voice, language: state.uiLanguage.rawValue, apiKey: state.apiKey)
        } label: {
            Text(symbol)
                .font(Theme.mono(11, weight: .bold))
                .foregroundColor(previewer.state == .idle ? Theme.dim : Theme.text)
                .frame(width: 30, height: 30)
                .border(Theme.border, width: 1)
                .contentShape(Rectangle())
                .opacity(pulsing ? 0.4 : 1)
                .animation(
                    pulsing
                        ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )
        }
        .buttonStyle(.plain)
        .help(loc.listenHint)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.mono(9, weight: .semibold))
            .foregroundColor(Theme.faint)
            .kerning(1.5)
    }
}

/// Plain button with a hover-tracked label builder.
private struct HoverScaleButton<Label: View>: View {
    var disabled = false
    let action: () -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label(hovered && !disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .scaleEffect(hovered && !disabled ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }
    }
}
