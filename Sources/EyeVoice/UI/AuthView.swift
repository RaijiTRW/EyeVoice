import AppKit
import SwiftUI

private enum AuthMode {
    case login
    case signup
}

struct AuthView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var auth: SupabaseAuthManager

    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var errorMessage: String?
    @State private var confirmationEmail: String?
    @State private var confirmationCode = ""
    @State private var confirmationNotice: String?
    @State private var resendAvailableAt = Date.distantPast
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
        case code
    }

    private var isRussian: Bool { state.uiLanguage == .ru }
    private var isSignup: Bool { mode == .signup }
    private var canSubmit: Bool {
        email.contains("@")
            && password.count >= 8
            && (!isSignup || acceptedTerms)
            && !auth.isWorking
    }
    private var canVerifyCode: Bool {
        confirmationCode.count == 6 && !auth.isWorking
    }

    var body: some View {
        ZStack {
            authAtmosphere
            AuthSideSignalField()

            VStack(spacing: 0) {
                authHeader

                ScrollView {
                    VStack(spacing: -18) {
                        AnimatedAsciiEye(
                            width: 560,
                            height: isSignup ? 166 : 188,
                            columns: 66,
                            rows: 30
                        )
                        .frame(maxWidth: .infinity)

                        Group {
                            if let confirmationEmail {
                                confirmationView(email: confirmationEmail)
                            } else {
                                authForm
                            }
                        }
                        .frame(maxWidth: 410)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, isSignup ? 0 : 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    private var authHeader: some View {
        HStack {
            HStack(spacing: 10) {
                EyeGlyph(width: 25, color: Theme.accent)
                Text("EYEVOICE")
                    .font(Theme.mono(13, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(Theme.text)
            }
            Spacer()
            authLanguageToggle
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var authAtmosphere: some View {
        HStack(spacing: 0) {
            RadialGradient(
                colors: [Theme.accent.opacity(0.12), Theme.accent.opacity(0.025), .clear],
                center: .leading,
                startRadius: 4,
                endRadius: 330
            )
            .frame(maxWidth: 310)

            Spacer(minLength: 220)

            RadialGradient(
                colors: [Color.white.opacity(0.055), Theme.accent.opacity(0.035), .clear],
                center: .trailing,
                startRadius: 6,
                endRadius: 340
            )
            .frame(maxWidth: 320)
        }
        .allowsHitTesting(false)
    }

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isSignup ? copy("Регистрация", "Create account") : copy("Вход", "Log in"))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text)
                .tracking(-0.7)

            Text(isSignup
                 ? copy("Создайте аккаунт EyeVoice", "Create your EyeVoice account")
                 : copy("Продолжите работу в EyeVoice", "Continue to EyeVoice"))
                .font(Theme.mono(10))
                .foregroundColor(Theme.dim)
                .padding(.top, 7)

            VStack(spacing: 16) {
                authFieldLabel("EMAIL", field: .email) {
                    TextField(focusedField == .email ? "" : "you@example.com", text: $email)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.text)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                }

                authFieldLabel(copy("ПАРОЛЬ", "PASSWORD"), field: .password) {
                    SecureField(
                        focusedField == .password
                            ? ""
                            : copy("Минимум 8 символов", "At least 8 characters"),
                        text: $password
                    )
                        .textFieldStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.text)
                        .focused($focusedField, equals: .password)
                        .onSubmit { submit() }
                }
            }
            .padding(.top, 28)

            if isSignup {
                consentControl
                    .padding(.top, 16)
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(errorMessage)
                        .font(Theme.mono(9))
                        .lineSpacing(3)
                }
                .foregroundColor(Theme.accent)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.055))
                .panelCard(radius: 8, color: Theme.accent.opacity(0.32))
                .padding(.top, 14)
            }

            Button(action: submit) {
                HStack(spacing: 9) {
                    if auth.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.bg)
                    }
                    Text(auth.isWorking
                         ? copy("ПОДКЛЮЧЕНИЕ", "CONNECTING")
                         : (isSignup ? copy("СОЗДАТЬ АККАУНТ", "CREATE ACCOUNT") : copy("ВОЙТИ", "LOG IN")))
                        .font(Theme.mono(11, weight: .bold))
                }
                .foregroundColor(Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(canSubmit ? Theme.accent : Theme.accent.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.top, 18)

            HStack(spacing: 5) {
                Text(isSignup
                     ? copy("Уже есть аккаунт?", "Already have an account?")
                     : copy("Нет аккаунта?", "No account yet?"))
                    .foregroundColor(Theme.faint)
                Button(isSignup ? copy("Войти", "Log in") : copy("Регистрация", "Sign up")) {
                    switchMode()
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.text)
                .underline()
            }
            .font(Theme.mono(9))
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
        }
        .padding(27)
        .authGlassCard(radius: 24)
    }

    private func authFieldLabel<Content: View>(
        _ title: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.mono(8, weight: .medium))
                .tracking(1.2)
                .foregroundColor(Theme.faint)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 43)
                .background(Color.black.opacity(0.2))
                .panelCard(radius: 9, color: Color.white.opacity(0.14))
                .contentShape(Rectangle())
                .textInputCursor()
                .onTapGesture { focusedField = field }
        }
    }

    private var consentControl: some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    acceptedTerms.toggle()
                    errorMessage = nil
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(acceptedTerms ? Theme.accent : Color.clear)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(acceptedTerms ? Theme.accent : Theme.border, lineWidth: 1)
                    if acceptedTerms {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(Theme.bg)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(.init(consentMarkdown))
                .font(Theme.mono(8))
                .foregroundColor(Theme.faint)
                .tint(Theme.accent)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(acceptedTerms ? Theme.accent.opacity(0.04) : Color.black.opacity(0.14))
        .panelCard(
            radius: 9,
            color: acceptedTerms ? Theme.accent.opacity(0.38) : Color.white.opacity(0.1)
        )
    }

    private func confirmationView(email: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accent.opacity(0.1))
                    Image(systemName: "number")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 6) {
                    Text(copy("Код подтверждения", "Confirmation code"))
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Text(copy("ШАГ 2 ИЗ 2", "STEP 2 OF 2"))
                        .font(Theme.mono(8, weight: .medium))
                        .tracking(1.4)
                        .foregroundColor(Theme.accent)
                }
            }

            Text(copy(
                "Введите шестизначный код, отправленный на \(email). После подтверждения вы сразу войдёте в EyeVoice.",
                "Enter the six-digit code sent to \(email). You will enter EyeVoice immediately after confirmation."
            ))
            .font(Theme.mono(10))
            .foregroundColor(Theme.dim)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(copy("КОД ИЗ ПИСЬМА", "CODE FROM EMAIL"))
                    .font(Theme.mono(8, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(Theme.faint)

                TextField("000000", text: Binding(
                    get: { confirmationCode },
                    set: { value in
                        confirmationCode = String(value.filter(\.isNumber).prefix(6))
                        errorMessage = nil
                        confirmationNotice = nil
                    }
                ))
                .textFieldStyle(.plain)
                .font(Theme.mono(22, weight: .bold))
                .tracking(8)
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.text)
                .focused($focusedField, equals: .code)
                .onSubmit { verifyConfirmationCode(email: email) }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(Color.black.opacity(0.2))
                .panelCard(
                    radius: 10,
                    color: focusedField == .code ? Theme.accent.opacity(0.55) : Color.white.opacity(0.14)
                )
                .contentShape(Rectangle())
                .textInputCursor()
                .onTapGesture { focusedField = .code }
            }
            .padding(.top, 24)

            if let errorMessage {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(errorMessage)
                        .font(Theme.mono(9))
                        .lineSpacing(3)
                }
                .foregroundColor(Theme.accent)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.055))
                .panelCard(radius: 8, color: Theme.accent.opacity(0.32))
                .padding(.top, 14)
            } else if let confirmationNotice {
                Text(confirmationNotice)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.dim)
                    .padding(.top, 12)
            }

            Button { verifyConfirmationCode(email: email) } label: {
                HStack(spacing: 9) {
                    if auth.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.bg)
                    }
                    Text(auth.isWorking
                         ? copy("ПРОВЕРКА", "VERIFYING")
                         : copy("ПОДТВЕРДИТЬ И ВОЙТИ", "CONFIRM AND ENTER"))
                        .font(Theme.mono(10, weight: .bold))
                }
                .foregroundColor(Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(canVerifyCode ? Theme.accent : Theme.accent.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canVerifyCode)
            .padding(.top, 18)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let seconds = max(0, Int(ceil(resendAvailableAt.timeIntervalSince(timeline.date))))
                HStack(spacing: 5) {
                    Text(copy("Не пришёл код?", "Didn't receive the code?"))
                        .foregroundColor(Theme.faint)
                    Button(seconds > 0
                           ? copy("Повторить через \(seconds) с", "Resend in \(seconds)s")
                           : copy("Отправить снова", "Send again")) {
                        resendConfirmationCode(email: email)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(seconds > 0 ? Theme.faint : Theme.text)
                    .underline(seconds == 0)
                    .disabled(seconds > 0 || auth.isWorking)
                }
                .font(Theme.mono(9))
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 16)

            Button(copy("ИЗМЕНИТЬ EMAIL", "CHANGE EMAIL")) {
                confirmationEmail = nil
                confirmationCode = ""
                confirmationNotice = nil
                errorMessage = nil
                focusedField = .email
            }
            .buttonStyle(.plain)
            .font(Theme.mono(8, weight: .medium))
            .tracking(1)
            .foregroundColor(Theme.faint)
            .frame(maxWidth: .infinity)
            .padding(.top, 13)
        }
        .padding(27)
        .authGlassCard(radius: 24)
    }

    private var authLanguageToggle: some View {
        HStack(spacing: 6) {
            authLanguageButton("RU", .ru)
            authLanguageButton("EN", .en)
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private func authLanguageButton(_ title: String, _ language: UILanguage) -> some View {
        let selected = state.uiLanguage == language
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { state.uiLanguage = language }
        } label: {
            HStack(spacing: 6) {
                LanguageFlag(language: language, width: 19)
                Text(title)
                    .font(Theme.mono(9, weight: .bold))
            }
            .foregroundColor(selected ? Theme.bg : Theme.dim)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(selected ? Theme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var consentMarkdown: String {
        if isRussian {
            return "Я принимаю [политику конфиденциальности](\(AppLinks.privacyURL.absoluteString)) и [условия использования](\(AppLinks.termsURL.absoluteString))."
        }
        return "I accept the [privacy policy](\(AppLinks.privacyURL.absoluteString)) and [terms of use](\(AppLinks.termsURL.absoluteString))."
    }

    private func submit() {
        guard canSubmit else {
            if isSignup && !acceptedTerms {
                errorMessage = copy(
                    "Примите политику конфиденциальности и условия использования.",
                    "Accept the privacy policy and terms of use."
                )
            }
            return
        }

        errorMessage = nil
        Task {
            do {
                if isSignup {
                    let outcome = try await auth.signUp(email: email, password: password)
                    if case .confirmationRequired(let email) = outcome {
                        confirmationEmail = email
                        confirmationCode = ""
                        confirmationNotice = nil
                        resendAvailableAt = Date().addingTimeInterval(60)
                        focusedField = .code
                    }
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = humanized(error)
            }
        }
    }

    private func verifyConfirmationCode(email: String) {
        guard canVerifyCode else { return }
        errorMessage = nil
        confirmationNotice = nil

        Task {
            do {
                try await auth.verifySignupOTP(email: email, code: confirmationCode)
            } catch {
                errorMessage = humanized(error)
            }
        }
    }

    private func resendConfirmationCode(email: String) {
        guard resendAvailableAt <= Date(), !auth.isWorking else { return }
        errorMessage = nil
        confirmationNotice = nil

        Task {
            do {
                try await auth.resendSignupOTP(email: email)
                confirmationCode = ""
                resendAvailableAt = Date().addingTimeInterval(60)
                confirmationNotice = copy(
                    "Новый код отправлен. Проверьте входящие и папку «Спам».",
                    "A new code was sent. Check your inbox and spam folder."
                )
                focusedField = .code
            } catch {
                errorMessage = humanized(error)
            }
        }
    }

    private func switchMode() {
        withAnimation(.easeOut(duration: 0.2)) {
            mode = isSignup ? .login : .signup
            password = ""
            acceptedTerms = false
            errorMessage = nil
            confirmationEmail = nil
            confirmationCode = ""
            confirmationNotice = nil
            resendAvailableAt = .distantPast
        }
        focusedField = email.isEmpty ? .email : .password
    }

    private func humanized(_ error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let value = raw.lowercased()

        if value.contains("invalid login credentials") {
            return copy("Неверный email или пароль.", "Incorrect email or password.")
        }
        if value.contains("email not confirmed") {
            return copy("Сначала подтвердите email по ссылке из письма.", "Confirm your email using the link we sent.")
        }
        if value.contains("already registered") || value.contains("user already exists") {
            return copy("Аккаунт с таким email уже существует.", "An account with this email already exists.")
        }
        if value.contains("rate limit") || value.contains("too many") {
            return copy("Слишком много попыток. Повторите позже.", "Too many attempts. Try again later.")
        }
        if value.contains("token has expired")
            || value.contains("token is invalid")
            || value.contains("otp expired")
            || value.contains("invalid otp") {
            return copy(
                "Код неверный или истёк. Проверьте его либо запросите новый.",
                "The code is incorrect or expired. Check it or request a new one."
            )
        }
        if value.contains("password") && (value.contains("short") || value.contains("least")) {
            return copy("Пароль должен содержать минимум 8 символов.", "Password must contain at least 8 characters.")
        }
        if error is SupabaseAuthError {
            return copy("Не удалось подключиться к аккаунту. Проверьте данные и интернет.", "Could not connect to your account. Check your details and connection.")
        }
        return raw
    }

    private func copy(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}

struct AuthSessionLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            EyeStatusView(status: .connecting, width: 52)
            Text("EYEVOICE")
                .font(Theme.mono(12, weight: .bold))
                .tracking(1.6)
                .foregroundColor(Theme.text)
            Text("•  •  •")
                .font(Theme.mono(9))
                .foregroundColor(Theme.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AuthGlassCardModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(Color(white: 0.08).opacity(0.26))
                    }
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.08),
                            Theme.accent.opacity(0.2),
                            Color.white.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 132, height: 1)
                    .blur(radius: 0.4)
                    .padding(.top, 1)
            }
            .shadow(color: Color.black.opacity(0.55), radius: 28, y: 18)
            .shadow(color: Theme.accent.opacity(0.08), radius: 32, y: 10)
    }
}

private extension View {
    func authGlassCard(radius: CGFloat) -> some View {
        modifier(AuthGlassCardModifier(radius: radius))
    }
}
