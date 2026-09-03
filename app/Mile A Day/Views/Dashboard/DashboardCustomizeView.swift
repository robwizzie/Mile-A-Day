import SwiftUI

/// The dashboard's movable cards, in the user's order. Both bodies mount
/// this right below their day's cards (hero, start, steps and medals — the
/// part that never moves). A card whose data is empty (no competition, no
/// weekly challenge yet) says so quietly rather than rendering nothing — a
/// switch the user just flipped must show SOMETHING.
struct DashboardCardsBlock: View {
    let style: DashboardStyle
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var friendService: FriendService
    @EnvironmentObject private var competitionService: CompetitionService
    @ObservedObject private var weeklyChallengeService = WeeklyChallengeService.shared
    @AppStorage(DashboardCards.funKey) private var funRaw = ""
    @AppStorage(DashboardCards.modernKey) private var modernRaw = ""
    @State private var showWorkouts = false

    private var raw: String { style == .fun ? funRaw : modernRaw }

    var body: some View {
        ForEach(DashboardCards.ordered(in: raw, for: style)) { card in
            switch card {
            case .dailyChallenge:
                NavigationLink {
                    DailyChallengesView(healthManager: healthManager, userManager: userManager)
                } label: {
                    if style == .fun {
                        DailyChallengeCard(healthManager: healthManager, userManager: userManager)
                    } else {
                        ModernChallengeRow(healthManager: healthManager, userManager: userManager)
                    }
                }
                .buttonStyle(.plain)
            case .streakTokens:
                StreakTokensCard()
            case .friendActivity:
                FriendActivityStripView(friendService: friendService)
            case .treats:
                TreatsCard(healthManager: healthManager)
            case .weekChart:
                WeeklyMileChartView(healthManager: healthManager, userManager: userManager)
            case .recentWorkouts:
                RecentWorkoutsPreviewCard(healthManager: healthManager, showWorkouts: $showWorkouts)
                    .navigationDestination(isPresented: $showWorkouts) {
                        WorkoutsView(healthManager: healthManager)
                    }
            case .competitions:
                competitionsCard
            case .weeklyChallenge:
                weeklyChallengeCard
            case .streakHistory:
                HallOfStreaksSection(userId: userManager.currentUser.backendUserId, isSelf: true)
            case .routeMap:
                RouteMapCard(style: style)
            }
        }
    }

    @ViewBuilder
    private var competitionsCard: some View {
        let active = competitionService.competitions.filter { $0.status == .active }
        if active.isEmpty {
            DashboardQuietCard(
                style: style, icon: "trophy.fill", tint: .orange,
                title: "No competitions right now",
                subtitle: "Start or join one from the Compete tab and it shows up here.")
        } else {
            ForEach(active, id: \.competition_id) { competition in
                ActiveCompetitionBannerCard(competition: competition)
            }
        }
    }

    @ViewBuilder
    private var weeklyChallengeCard: some View {
        if let weekly = weeklyChallengeService.current {
            NavigationLink {
                WeeklyChallengeDetailView(response: weekly, service: weeklyChallengeService)
            } label: {
                WeeklyChallengeHeroCard(response: weekly, compact: true) {}
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
        } else {
            DashboardQuietCard(
                style: style, icon: "calendar.badge.checkmark", tint: MADTheme.Colors.madRed,
                title: "No weekly challenge yet",
                subtitle: "A new one lands every Sunday.")
        }
    }
}

/// A doorway card: one tap opens the personal route heatmap, which is a
/// full-screen map and too heavy to live inline on the dashboard.
struct RouteMapCard: View {
    let style: DashboardStyle
    @State private var showMap = false

    var body: some View {
        Button {
            MADHaptics.tap()
            showMap = true
        } label: {
            DashboardQuietCard(
                style: style, icon: "map.fill", tint: .blue,
                title: "Your routes",
                subtitle: "Every walk and run you've mapped, on one map",
                chevron: true)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMap) { RouteHeatmapView() }
    }
}

/// The quiet one-row card both styles use for doorways and empty states.
struct DashboardQuietCard: View {
    let style: DashboardStyle
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var chevron: Bool = false

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(DashboardCardSurface(style: style))
    }
}

/// The quiet card background each style uses for its secondary cards.
struct DashboardCardSurface: View {
    let style: DashboardStyle

    var body: some View {
        switch style {
        case .fun:
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.05))
        case .modern:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }
    }
}

/// The quiet row at the bottom of the dashboard: "Customize dashboard".
/// Lives OUTSIDE the style-switched bodies (DashboardView mounts it after
/// them) so a style change made from its sheet can't tear it — and the
/// sheet — down. Presentation state is shared (`DashboardCustomizeState`)
/// so the dashboard can keep this row in view under the sheet.
struct DashboardCustomizeRow: View {
    let style: DashboardStyle

    @AppStorage(DashboardCards.funKey) private var funRaw = ""
    @AppStorage(DashboardCards.modernKey) private var modernRaw = ""

    var body: some View {
        let count = DashboardCards.ordered(in: style == .fun ? funRaw : modernRaw, for: style).count
        Button {
            MADHaptics.tap()
            DashboardCustomizeState.shared.isPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                Text("Customize dashboard")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(count == 1 ? "1 card" : "\(count) cards")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DashboardCardSurface(style: style))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: Binding(
            get: { DashboardCustomizeState.shared.isPresented },
            set: { DashboardCustomizeState.shared.isPresented = $0 }
        )) {
            DashboardCustomizeView()
        }
    }
}

/// Look first, then the cards on the dashboard — in YOUR order, dragged by
/// the handle — then the ones you could add. The day's cards up top aren't
/// listed: they never move. Switching the look changes the dashboard live
/// behind the sheet and leaves the sheet up.
///
/// A PLAIN list with its own grouped chrome: the inset-grouped style clips
/// every row to its section's corner radius, which is what chopped the
/// corners off the Look tiles. Here each row paints its own background with
/// the right corners rounded, so nothing is ever clipped.
struct DashboardCustomizeView: View {
    @AppStorage(DashboardCards.funKey) private var funRaw = ""
    @AppStorage(DashboardCards.modernKey) private var modernRaw = ""
    @AppStorage(DashboardStylePreference.key) private var dashboardStyleRaw = DashboardStyle.modern.rawValue
    @Environment(\.dismiss) private var dismiss

    private var style: DashboardStyle { DashboardStyle(rawValue: dashboardStyleRaw) ?? .modern }
    private var raw: String { style == .fun ? funRaw : modernRaw }
    private var onCards: [DashboardCard] { DashboardCards.ordered(in: raw, for: style) }
    private var offCards: [DashboardCard] { DashboardCards.off(in: raw, for: style) }

    /// The width the system reorder control takes beside a movable row, so
    /// the toggles line up down the whole list.
    private static let handleSlot: CGFloat = 40

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    plainRow(header("Look"))
                    plainRow(lookTiles)
                    plainRow(footnote("Changes right away, behind this sheet."))

                    plainRow(header("On your dashboard"))
                    if onCards.isEmpty {
                        cardRow(text: "Nothing here — just the day's cards.", position: .only)
                    }
                    ForEach(Array(onCards.enumerated()), id: \.element.id) { index, card in
                        row(card, movable: true, proxy: proxy)
                            .listRowBackground(groupBackground(Self.position(index, of: onCards.count)))
                            .listRowInsets(Self.rowInsets)
                            .listRowSeparator(.hidden)
                            .id("on-\(card.rawValue)")
                    }
                    .onMove { source, destination in
                        MADHaptics.tap()
                        write(DashboardCards.moving(fromOffsets: source, toOffset: destination, in: raw, for: style))
                    }
                    plainRow(footnote("Drag the handle to reorder. Your streak, Start Mile, steps and medals stay up top; everything below is yours."))

                    plainRow(header("Add cards"))
                    if offCards.isEmpty {
                        cardRow(text: "Everything's on. More cards will show up here as we build them.", position: .only)
                    }
                    ForEach(Array(offCards.enumerated()), id: \.element.id) { index, card in
                        row(card, movable: false, proxy: proxy)
                            .listRowBackground(groupBackground(Self.position(index, of: offCards.count)))
                            .listRowInsets(Self.rowInsets)
                            .listRowSeparator(.hidden)
                            .id("off-\(card.rawValue)")
                    }
                    plainRow(footnote("A new card lands at the bottom of your dashboard — drag it wherever you like."))
                        .padding(.bottom, MADTheme.Spacing.lg)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
                // Always in edit mode: that is what draws the drag handles. No
                // `.onDelete`, so no red minus buttons — the toggle is the remove.
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Chrome

    private enum RowPosition { case only, first, middle, last }

    private static func position(_ index: Int, of count: Int) -> RowPosition {
        if count <= 1 { return .only }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }

    private static let rowInsets = EdgeInsets(top: 12, leading: 32, bottom: 12, trailing: 32)

    /// One card's slice of the group: corners rounded where the group ends,
    /// a hairline below every row but the last.
    private func groupBackground(_ position: RowPosition) -> some View {
        let radius = MADTheme.CornerRadius.large
        let top: CGFloat = (position == .only || position == .first) ? radius : 0
        let bottom: CGFloat = (position == .only || position == .last) ? radius : 0
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(
                topLeadingRadius: top, bottomLeadingRadius: bottom,
                bottomTrailingRadius: bottom, topTrailingRadius: top,
                style: .continuous)
                .fill(Color.white.opacity(0.05))
            if position == .first || position == .middle {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
    }

    /// A header, footnote or the Look tiles — no chrome, no separator.
    private func plainRow<Content: View>(_ content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .listRowSeparator(.hidden)
    }

    private func cardRow(text: String, position: RowPosition) -> some View {
        Text(text)
            .font(.system(size: 13, design: .rounded))
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(groupBackground(position))
            .listRowInsets(Self.rowInsets)
            .listRowSeparator(.hidden)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.5))
            .padding(.top, 6)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(.white.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Look

    private var lookTiles: some View {
        HStack(spacing: 10) {
            ForEach(DashboardStyle.allCases) { option in
                styleChoice(option)
            }
        }
    }

    /// The real flames, not icons: Flamey for Fun, the ring flame for
    /// Modern — the tile shows what you'd get.
    private func styleChoice(_ option: DashboardStyle) -> some View {
        let selected = style == option
        return Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) {
                DashboardStylePreference.choose(option)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(option == .fun
                            ? Color(red: 0.18, green: 0.05, blue: 0.06)
                            : Color(red: 0.09, green: 0.09, blue: 0.10))
                        .frame(height: 96)
                    if option == .fun {
                        FlameBuddyView(health: .healthy, size: 72)
                    } else {
                        ProfessionalFlameView(
                            phase: .burning, health: .healthy, size: 62,
                            ringProgress: 0.72,
                            dayEnd: Date().addingTimeInterval(22 * 3600))
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(selected ? MADTheme.Colors.madRed : .white.opacity(0.3))
                    Text(option.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Text(option.subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .strokeBorder(selected ? MADTheme.Colors.madRed.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Cards

    /// Centre-aligned so the toggle sits level with the system drag handle;
    /// rows without a handle reserve its width so every toggle lines up.
    private func row(_ card: DashboardCard, movable: Bool, proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(MADTheme.Colors.madRed.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: card.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MADTheme.Colors.madRed)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundColor(.white)
                Text(card.subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding(for: card, proxy: proxy))
                .labelsHidden()
                .tint(MADTheme.Colors.madRed)
            if !movable {
                Color.clear.frame(width: Self.handleSlot, height: 1)
            }
        }
    }

    private func binding(for card: DashboardCard, proxy: ScrollViewProxy) -> Binding<Bool> {
        Binding(
            get: { DashboardCards.isOn(card, in: raw, for: style) },
            set: { on in
                MADHaptics.tap()
                withAnimation(.easeInOut(duration: 0.25)) {
                    write(DashboardCards.toggling(card, on: on, in: raw, for: style))
                }
                // A card just added lands at the bottom of "On your dashboard"
                // with its handle: bring it into view so it can be dragged
                // into place right away.
                if on {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("on-\(card.rawValue)", anchor: .center)
                        }
                    }
                }
            }
        )
    }

    private func write(_ value: String) {
        if style == .fun { funRaw = value } else { modernRaw = value }
    }
}
