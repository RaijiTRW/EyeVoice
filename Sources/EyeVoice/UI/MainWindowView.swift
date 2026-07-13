import AppKit
import SwiftUI

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case profile
    case statistics
    case subscription
    case payments

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .profile: return "person.crop.square"
        case .statistics: return "chart.bar.xaxis"
        case .subscription: return "creditcard"
        case .payments: return "list.bullet.rectangle"
        }
    }
}

private struct DailyUsagePoint: Identifiable {
    let date: Date
    let seconds: TimeInterval
    var id: Date { date }
}

private struct SubscriptionPlan: Identifiable {
    let id: String
    let name: String
    let price: String
    let allowance: String
    let features: [String]
}

struct MainWindowView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var auth = SupabaseAuthManager.shared
    @StateObject private var avatarStore = ProfileAvatarStore.shared
    @StateObject private var updates = UpdateManager.shared
    @State private var selection: DashboardSection = .overview
    @State private var isAvatarHovered = false
    @State private var planUpdateError: String?
    @AppStorage("dashboardProfileName") private var profileName = ""

    private var isRussian: Bool { state.uiLanguage == .ru }
    private var currentPlanID: String {
        let plan = auth.usageBalance?.planID.lowercased()
            ?? auth.user?.userMetadata?.plan?.lowercased()
            ?? "free"
        return ["free", "start", "pro"].contains(plan) ? plan : "free"
    }

    private var subscriptionPlans: [SubscriptionPlan] {
        [
            SubscriptionPlan(
                id: "free",
                name: "FREE",
                price: copy("0 ₽", "$0"),
                allowance: copy("30 минут / мес", "30 min / mo"),
                features: [
                    copy("Все источники звука", "All audio sources"),
                    copy("14 языков", "14 languages"),
                    copy("Обновляется каждый месяц", "Renews every month"),
                    copy("Без карты", "No card required"),
                ]
            ),
            SubscriptionPlan(
                id: "start",
                name: "START",
                price: copy("1 990 ₽ / мес", "$19 / mo"),
                allowance: copy("5 часов / мес", "5 hours / mo"),
                features: [
                    copy("Всё из FREE", "Everything in FREE"),
                    copy("Покупка дополнительных часов", "Additional hours available"),
                    copy("Перенос до 5 часов", "Roll over up to 5 hours"),
                ]
            ),
            SubscriptionPlan(
                id: "pro",
                name: "PRO",
                price: copy("4 990 ₽ / мес", "$49 / mo"),
                allowance: copy("15 часов / мес", "15 hours / mo"),
                features: [
                    copy("Всё из START", "Everything in START"),
                    copy("Скидка на дополнительные часы", "Discounted additional hours"),
                    copy("Перенос до 15 часов", "Roll over up to 15 hours"),
                ]
            ),
        ]
    }
    private var currentSubscriptionPlan: SubscriptionPlan {
        subscriptionPlans.first { $0.id == currentPlanID } ?? subscriptionPlans[0]
    }

    var body: some View {
        Group {
            if auth.isCheckingSession {
                AuthSessionLoadingView()
            } else if auth.isAuthenticated {
                dashboard
            } else {
                AuthView(auth: auth)
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        .background(DashboardBackground())
        .overlay(alignment: .topTrailing) {
            UpdateBanner(updates: updates)
                .environmentObject(state)
                .padding(18)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if auth.isAuthenticated { state.syncUsageWithAccount() }
        }
        .task(id: auth.user?.id) {
            if auth.isAuthenticated { await auth.refreshUsageBalance() }
        }
        .onChange(of: auth.user?.id) { _, userID in
            if userID != nil { state.syncUsageWithAccount() }
        }
    }

    private var dashboard: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1)
            sectionContent
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                EyeGlyph(width: 28, color: Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EYEVOICE")
                        .font(Theme.mono(14, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(copy("ЛИЧНЫЙ КАБИНЕТ", "ACCOUNT"))
                        .font(Theme.mono(8, weight: .medium))
                        .tracking(1.4)
                        .foregroundColor(Theme.faint)
                }
            }
            .padding(.bottom, 34)

            Text(copy("РАЗДЕЛЫ", "SECTIONS"))
                .font(Theme.mono(8, weight: .medium))
                .tracking(1.4)
                .foregroundColor(Theme.faint)
                .padding(.horizontal, 12)
                .padding(.bottom, 9)

            VStack(spacing: 5) {
                ForEach(DashboardSection.allCases) { section in
                    navigationButton(section)
                }
            }

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 14) {
                sidebarLanguageControl

                Text(copy("СОСТОЯНИЕ", "STATUS"))
                    .font(Theme.mono(8, weight: .medium))
                    .tracking(1.1)
                    .foregroundColor(Theme.faint)
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isRunning ? Theme.accent : Theme.faint)
                        .frame(width: 7, height: 7)
                        .shadow(color: state.isRunning ? Theme.accent.opacity(0.55) : .clear, radius: 5)
                    Text(state.statusLabel)
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundColor(state.isRunning ? Theme.text : Theme.dim)
                }
                Text(copy("Управление доступно в menu bar", "Controls are available in the menu bar"))
                    .font(Theme.mono(8))
                    .foregroundColor(Theme.faint)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(copy("ВЕРСИЯ", "VERSION"))
                        .tracking(1.1)
                    Spacer(minLength: 8)
                    Text(appVersion)
                        .foregroundColor(Theme.dim)
                }
                .font(Theme.mono(8, weight: .medium))
                .foregroundColor(Theme.faint)
                .padding(.top, 11)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(20)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bg.opacity(0.94))
    }

    private var sidebarLanguageControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.accent)
                Text(copy("ЯЗЫК ИНТЕРФЕЙСА", "INTERFACE LANGUAGE"))
                    .font(Theme.mono(8, weight: .medium))
                    .tracking(0.8)
                    .foregroundColor(Theme.faint)
            }

            HStack(spacing: 6) {
                languageButton("RU", .ru)
                languageButton("EN", .en)
            }
        }
        .padding(.bottom, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func navigationButton(_ section: DashboardSection) -> some View {
        let selected = selection == section
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                Text(sectionTitle(section))
                    .font(Theme.mono(10, weight: selected ? .bold : .medium))
            }
            .foregroundColor(selected ? Theme.text : Theme.faint)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
            .background(selected ? Theme.accent.opacity(0.09) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 2, height: 22)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sectionContent: some View {
        ScrollView {
            Group {
                switch selection {
                case .overview:
                    overviewSection
                case .profile:
                    profileSection
                case .statistics:
                    statisticsSection
                case .subscription:
                    subscriptionSection
                case .payments:
                    paymentsSection
                }
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                copy("Обзор", "Overview"),
                copy("Состояние EyeVoice и данные вашего аккаунта", "EyeVoice status and account data")
            )

            HStack(alignment: .top, spacing: 18) {
                DashboardSurface {
                    HStack(spacing: 20) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.accent.opacity(0.08))
                            EyeStatusView(status: state.status, width: 64)
                        }
                        .frame(width: 112, height: 132)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(state.isRunning
                                 ? copy("Перевод активен", "Translation is active")
                                 : copy("Готов к переводу", "Ready to translate"))
                                .font(.system(size: 23, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.text)
                                .lineLimit(2)
                            Text(copy(
                                "Быстрое управление источником, языком и голосом находится в панели с глазом в menu bar.",
                                "Source, language and voice controls remain in the eye panel in the menu bar."
                            ))
                            .font(Theme.mono(11))
                            .foregroundColor(Theme.dim)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 16) {
                                infoPair(copy("ИСТОЧНИК", "SOURCE"), sourceName)
                                infoPair(copy("ЯЗЫК", "LANGUAGE"), languageRoute)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 196, maxHeight: 196)

                currentPlanCard
                    .frame(width: 270, height: 196)
            }

            HStack(spacing: 14) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    metricCard(
                        copy("ВРЕМЯ ПЕРЕВОДА", "TRANSLATION TIME"),
                        formatDuration(totalUsage(at: context.date)),
                        "waveform"
                    )
                }
                metricCard(
                    copy("ЗАВЕРШЁННЫЕ СЕАНСЫ", "COMPLETED SESSIONS"),
                    "\(state.completedSessionCount)",
                    "checkmark.square"
                )
                metricCard(
                    copy("ПОСЛЕДНИЙ СЕАНС", "LAST SESSION"),
                    lastSessionText,
                    "clock"
                )
            }

            activityCard
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                copy("Профиль", "Profile"),
                copy("Аккаунт Supabase и данные профиля EyeVoice", "Your Supabase account and EyeVoice profile")
            )

            HStack(alignment: .top, spacing: 18) {
                DashboardSurface {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 16) {
                            profileAvatar

                            VStack(alignment: .leading, spacing: 5) {
                                Text(profileName.isEmpty ? copy("Профиль EyeVoice", "EyeVoice profile") : profileName)
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.text)
                                Text(auth.user?.email ?? "—")
                                    .font(Theme.mono(10))
                                    .foregroundColor(Theme.dim)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button {
                                Task { await auth.signOut() }
                            } label: {
                                Text(auth.isWorking ? "• • •" : copy("ВЫЙТИ", "SIGN OUT"))
                                    .font(Theme.mono(8, weight: .bold))
                                    .foregroundColor(Theme.dim)
                                    .padding(.horizontal, 11)
                                    .frame(height: 32)
                                    .background(Color.white.opacity(0.045))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(auth.isWorking)
                        }

                        profileField(copy("ИМЯ", "NAME"), copy("Введите имя", "Enter your name"), text: $profileName)
                        profileReadOnlyField("EMAIL", auth.user?.email ?? "—")

                        Text(copy(
                            "Email связан с аккаунтом Supabase. Имя и фотография пока сохраняются только на этом Mac.",
                            "Your email is linked to Supabase. Your name and photo are currently stored only on this Mac."
                        ))
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.faint)
                        .lineSpacing(3)
                    }
                }

                DashboardSurface {
                    VStack(alignment: .leading, spacing: 16) {
                        cardTitle(copy("Это устройство", "This device"), "desktopcomputer")
                        detailRow(copy("MAC", "MAC"), Host.current().localizedName ?? "Mac")
                        detailRow(copy("ВЕРСИЯ", "VERSION"), appVersion)
                        detailRow(copy("СИСТЕМА", "SYSTEM"), ProcessInfo.processInfo.operatingSystemVersionString)
                    }
                }
                .frame(width: 320)
            }
        }
    }

    private var profileAvatar: some View {
        Button {
            avatarStore.chooseImage()
        } label: {
            ZStack {
                if let image = avatarStore.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipped()
                } else {
                    Theme.accent
                    EyeGlyph(width: 42, color: Theme.bg)
                }

                if isAvatarHovered {
                    Color.black.opacity(0.48)
                    Image(systemName: "pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        isAvatarHovered ? Theme.accent.opacity(0.9) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.16)) {
                isAvatarHovered = hovered
            }
        }
        .help(copy("Изменить фото профиля", "Change profile photo"))
        .accessibilityLabel(copy("Изменить фото профиля", "Change profile photo"))
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                copy("Статистика", "Statistics"),
                copy("Локальная статистика переводов на этом Mac", "Local translation statistics on this Mac")
            )

            HStack(spacing: 14) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    metricCard(
                        copy("ОБЩЕЕ ВРЕМЯ", "TOTAL TIME"),
                        formatDuration(totalUsage(at: context.date)),
                        "timer"
                    )
                }
                metricCard(copy("СЕАНСЫ", "SESSIONS"), "\(state.completedSessionCount)", "waveform.path")
                metricCard(copy("ТЕКУЩИЙ СТАТУС", "CURRENT STATUS"), state.statusLabel, "dot.radiowaves.left.and.right")
            }

            DashboardSurface {
                VStack(alignment: .leading, spacing: 20) {
                    cardTitle(copy("Активность", "Activity"), "chart.bar.xaxis")
                    activityChart
                    Text(state.completedSessionCount == 0
                         ? copy("График заполнится после первых завершённых сеансов.", "The chart will fill after your first completed sessions.")
                         : copy("Фактическое активное время перевода за последние 12 дней.", "Actual active translation time over the last 12 days."))
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.faint)
                }
            }

            activityCard
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                copy("Подписка", "Subscription"),
                copy("Текущий тариф и будущие планы EyeVoice", "Your current plan and upcoming EyeVoice plans")
            )

            usageBalanceCard

            HStack(alignment: .top, spacing: 14) {
                ForEach(subscriptionPlans) { plan in
                    planCard(plan, current: currentPlanID == plan.id)
                }
            }

            if let planUpdateError {
                Text(planUpdateError)
                    .font(Theme.mono(9))
                    .foregroundColor(Color(red: 1, green: 0.38, blue: 0.56))
            } else {
                Text(copy(
                    "Выбор и оплата тарифа проходят в защищённом профиле EyeVoice на сайте.",
                    "Plan selection and payment take place in your secure EyeVoice web profile."
                ))
                .font(Theme.mono(9))
                .foregroundColor(Theme.faint)
            }
        }
    }

    private var usageBalanceCard: some View {
        let balance = auth.usageBalance
        let total = max(balance?.totalSeconds ?? 0, 1)
        let progress = min(max((balance?.usedSeconds ?? 0) / total, 0), 1)

        return DashboardSurface(accented: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(copy("ИСПОЛЬЗОВАНО", "USED"))
                            .font(Theme.mono(8, weight: .medium))
                            .tracking(1)
                            .foregroundColor(Theme.faint)
                        Text(balance.map { formatBalanceHours($0.usedSeconds) } ?? "—")
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.text)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(copy("ОСТАЛОСЬ", "REMAINING"))
                            .font(Theme.mono(8, weight: .medium))
                            .tracking(1)
                            .foregroundColor(Theme.faint)
                        Text(balance.map { formatBalanceHours($0.remainingSeconds) } ?? "—")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.accent)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 7)

                HStack(spacing: 20) {
                    balanceMetric(copy("В ТАРИФЕ", "INCLUDED"), balance?.baseSeconds)
                    balanceMetric(copy("ПЕРЕНЕСЕНО", "ROLLED OVER"), balance?.rolloverSeconds)
                    balanceMetric(copy("ДОКУПЛЕНО", "PURCHASED"), balance?.addonSeconds)
                    Spacer(minLength: 0)
                    Button {
                        planUpdateError = nil
                        if !NSWorkspace.shared.open(AppLinks.limitsURL) {
                            planUpdateError = copy(
                                "Не удалось открыть сайт EyeVoice.",
                                "Could not open the EyeVoice website."
                            )
                        }
                    } label: {
                        Text(balance?.canPurchaseExtraHours == true
                             ? copy("ДОКУПИТЬ ЧАСЫ  →", "BUY EXTRA HOURS  →")
                             : copy("ОТКРЫТЬ ЛИМИТЫ  →", "OPEN LIMITS  →"))
                            .font(Theme.mono(8, weight: .bold))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func balanceMetric(_ label: String, _ seconds: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.mono(7, weight: .medium))
                .tracking(0.8)
                .foregroundColor(Theme.faint)
            Text(seconds.map(formatBalanceHours) ?? "—")
                .font(Theme.mono(9, weight: .bold))
                .foregroundColor(Theme.dim)
        }
    }

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                copy("Платежи", "Payments"),
                copy("История операций и документы", "Transaction history and documents")
            )

            DashboardSurface {
                VStack(spacing: 0) {
                    HStack {
                        tableHeader(copy("ДАТА", "DATE"), width: 150)
                        tableHeader(copy("ОПИСАНИЕ", "DESCRIPTION"), width: nil)
                        tableHeader(copy("СУММА", "AMOUNT"), width: 130)
                        tableHeader(copy("СТАТУС", "STATUS"), width: 120)
                    }
                    .padding(.bottom, 14)

                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 1)

                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(Theme.faint)
                        Text(copy("Платежей пока нет", "No payments yet"))
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.text)
                        Text(copy(
                            "Здесь появятся оплаты, возвраты и документы после подключения платной подписки.",
                            "Payments, refunds and documents will appear here after a paid subscription is connected."
                        ))
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.dim)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                }
            }
        }
    }

    private var currentPlanCard: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(copy("ПОДПИСКА", "SUBSCRIPTION"))
                        .font(Theme.mono(9, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Theme.faint)
                    Spacer()
                    Text(currentSubscriptionPlan.name)
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Spacer()
                Text(copy(
                    "Тариф \(currentSubscriptionPlan.name)",
                    "\(currentSubscriptionPlan.name) plan"
                ))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text(currentSubscriptionPlan.allowance)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.dim)
                    .padding(.top, 6)
                Spacer()
                Button {
                    selection = .subscription
                } label: {
                    Text(copy("ПОСМОТРЕТЬ ПЛАНЫ  →", "VIEW PLANS  →"))
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activityCard: some View {
        DashboardSurface {
            VStack(alignment: .leading, spacing: 16) {
                cardTitle(copy("Последняя активность", "Recent activity"), "clock.arrow.circlepath")
                if !state.sessionHistory.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(state.sessionHistory.prefix(3))) { session in
                            sessionRow(session)
                            if session.id != state.sessionHistory.prefix(3).last?.id {
                                Rectangle()
                                    .fill(Color.white.opacity(0.07))
                                    .frame(height: 1)
                                    .padding(.leading, 56)
                            }
                        }
                    }
                } else {
                    Text(copy(
                        "Завершённые сеансы появятся здесь после первого запуска перевода.",
                        "Completed sessions will appear here after your first translation."
                    ))
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.dim)
                    .padding(.vertical, 18)
                }
            }
        }
    }

    private var activityChart: some View {
        let points = dailyUsagePoints
        let maximum = points.map(\.seconds).max() ?? 0

        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(points) { point in
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(point.seconds > 0 ? Theme.accent : Color.white.opacity(0.07))
                        .frame(maxWidth: .infinity)
                        .frame(height: chartHeight(point.seconds, maximum: maximum))
                    Text(dayLabel(point.date))
                        .font(Theme.mono(7, weight: .medium))
                        .foregroundColor(point.seconds > 0 ? Theme.dim : Theme.faint.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 112, alignment: .bottom)
    }

    private func sessionRow(_ session: TranslationSessionRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                Image(systemName: "waveform")
                    .foregroundColor(Theme.accent)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(sourceLabel(session))  ·  \(formatDuration(session.duration))")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("\(state.loc.languageName(session.sourceLanguage)) → \(state.loc.languageName(session.targetLanguage))")
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            Text(relativeDate(session.endedAt))
                .font(Theme.mono(9))
                .foregroundColor(Theme.faint)
        }
        .padding(.vertical, 8)
    }

    private func metricCard(_ label: String, _ value: String, _ icon: String) -> some View {
        DashboardSurface {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(Theme.mono(8, weight: .medium))
                        .tracking(0.9)
                        .foregroundColor(Theme.faint)
                    Text(value)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func planCard(_ plan: SubscriptionPlan, current: Bool) -> some View {
        DashboardSurface(accented: current) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(plan.name)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(current ? Theme.accent : Theme.text)
                    Spacer()
                    Text(current
                         ? copy("ТЕКУЩИЙ ПЛАН", "CURRENT PLAN")
                         : plan.allowance.uppercased())
                        .font(Theme.mono(8, weight: .bold))
                        .foregroundColor(current ? Theme.accent : Theme.faint)
                        .multilineTextAlignment(.trailing)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.price)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Text(plan.allowance)
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.dim)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.09))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(plan.features, id: \.self) { feature in
                        HStack(spacing: 9) {
                            Text(current ? "[x]" : "[·]")
                                .font(Theme.mono(9, weight: .bold))
                                .foregroundColor(current ? Theme.accent : Theme.faint)
                            Text(feature)
                                .font(Theme.mono(9))
                                .foregroundColor(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 4)

                Button {
                    guard !current else { return }
                    planUpdateError = nil
                    if !NSWorkspace.shared.open(AppLinks.subscriptionURL(planID: plan.id)) {
                        planUpdateError = copy(
                            "Не удалось открыть сайт EyeVoice.",
                            "Could not open the EyeVoice website."
                        )
                    }
                } label: {
                    Text(current
                            ? copy("ТЕКУЩИЙ ПЛАН", "CURRENT PLAN")
                            : copy("ВЫБРАТЬ ПЛАН", "SELECT PLAN"))
                        .font(Theme.mono(8, weight: .bold))
                        .foregroundColor(current ? Theme.faint : Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(current ? Color.white.opacity(0.025) : Theme.accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(current ? Color.white.opacity(0.07) : Theme.accent.opacity(0.48), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(current)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func profileField(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.mono(8, weight: .medium))
                .tracking(1.1)
                .foregroundColor(Theme.faint)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.black.opacity(0.22))
                .panelCard(radius: 8, color: Theme.border.opacity(0.5))
                .contentShape(Rectangle())
                .textInputCursor()
        }
    }

    private func profileReadOnlyField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.mono(8, weight: .medium))
                .tracking(1.1)
                .foregroundColor(Theme.faint)
            HStack(spacing: 9) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.accent)
                Text(value)
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.black.opacity(0.14))
            .panelCard(radius: 8, color: Theme.border.opacity(0.35))
        }
    }

    private func languageButton(_ title: String, _ language: UILanguage) -> some View {
        let selected = state.uiLanguage == language
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                state.uiLanguage = language
            }
        } label: {
            HStack(spacing: 8) {
                LanguageFlag(language: language, width: 23)
                Text(title)
                    .font(Theme.mono(10, weight: .bold))
            }
            .foregroundColor(selected ? Theme.bg : Theme.dim)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(selected ? Theme.accent : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language == .ru ? "Русский" : "English")
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text)
            Text(subtitle)
                .font(Theme.mono(10))
                .foregroundColor(Theme.dim)
        }
        .padding(.bottom, 4)
    }

    private func cardTitle(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.accent)
            Text(title)
                .font(Theme.mono(10, weight: .bold))
                .foregroundColor(Theme.text)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.mono(8, weight: .medium))
                .tracking(1)
                .foregroundColor(Theme.faint)
            Spacer()
            Text(value)
                .font(Theme.mono(9))
                .foregroundColor(Theme.dim)
                .lineLimit(1)
        }
    }

    private func infoPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.mono(8, weight: .medium))
                .tracking(0.8)
                .foregroundColor(Theme.faint)
            Text(value)
                .font(Theme.mono(9, weight: .bold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
        }
    }

    private func tableHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(Theme.mono(8, weight: .medium))
            .tracking(1)
            .foregroundColor(Theme.faint)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .frame(width: width, alignment: .leading)
    }

    private var sourceName: String {
        switch state.selectedSource {
        case .microphone: return copy("Микрофон", "Microphone")
        case .systemAudio: return copy("Система", "System")
        case .app(let app): return app.name
        }
    }

    private var languageRoute: String {
        "\(state.loc.languageName(state.sourceLanguage)) → \(state.loc.languageName(state.targetLanguage))"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.2"
    }

    private var lastSessionText: String {
        guard let lastSessionAt = state.lastSessionAt else {
            return copy("Нет данных", "No data")
        }
        return relativeDate(lastSessionAt)
    }

    private func totalUsage(at date: Date) -> TimeInterval {
        state.totalTranslationSeconds + state.currentSessionUsage(at: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 {
            return "\(totalSeconds) \(copy("сек", "sec"))"
        }
        let totalMinutes = totalSeconds / 60
        if totalMinutes < 60 {
            return "\(totalMinutes) \(copy("мин", "min"))"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours) \(copy("ч", "h")) \(minutes) \(copy("мин", "min"))"
    }

    private func formatBalanceHours(_ seconds: Double) -> String {
        let hours = max(0, seconds) / 3600
        if hours < 10 {
            return String(format: "%.1f %@", hours, copy("ч", "h"))
        }
        return "\(Int(hours.rounded())) \(copy("ч", "h"))"
    }

    private var dailyUsagePoints: [DailyUsagePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<12).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today),
                  let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
                return nil
            }
            let seconds = state.sessionHistory
                .filter { $0.endedAt >= date && $0.endedAt < nextDate }
                .reduce(0) { $0 + $1.duration }
            return DailyUsagePoint(date: date, seconds: seconds)
        }
    }

    private func chartHeight(_ seconds: TimeInterval, maximum: TimeInterval) -> CGFloat {
        guard maximum > 0, seconds > 0 else { return 4 }
        return max(8, CGFloat(seconds / maximum) * 76)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isRussian ? "ru_RU" : "en_US")
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func sourceLabel(_ session: TranslationSessionRecord) -> String {
        switch session.sourceID {
        case "mic": return copy("Микрофон", "Microphone")
        case "system": return copy("Система", "System")
        default: return session.sourceName
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: isRussian ? "ru_RU" : "en_US")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sectionTitle(_ section: DashboardSection) -> String {
        switch section {
        case .overview: return copy("Обзор", "Overview")
        case .profile: return copy("Профиль", "Profile")
        case .statistics: return copy("Статистика", "Statistics")
        case .subscription: return copy("Подписка", "Subscription")
        case .payments: return copy("Платежи", "Payments")
        }
    }

    private func copy(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}

private struct DashboardSurface<Content: View>: View {
    var accented = false
    @ViewBuilder let content: Content

    init(accented: Bool = false, @ViewBuilder content: () -> Content) {
        self.accented = accented
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.055).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accented ? Theme.accent.opacity(0.62) : Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct DashboardBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [Theme.accent.opacity(0.08), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
            Canvas { context, size in
                let spacing: CGFloat = 30
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}
