import SwiftUI

struct BadgesView: View {
    @ObservedObject var userManager: UserManager
    /// Optional badge to immediately drill into when this screen first appears.
    let initialBadge: Badge?
    /// Filter to apply when the screen first appears (e.g. `.new` from the trophy nav).
    var initialFilter: BadgeFilter = .all

    @State private var showConfetti = false
    @State private var selectedFilter: BadgeFilter = .all
    @State private var selectedBadge: Badge?
    @State private var isShowingDetail = false
    /// Snapshot of badge IDs that were `isNew` when this screen first appeared.
    /// We keep them visible under the "New" filter even after `markBadgesAsViewed()` flips
    /// the local flag, so the filter doesn't empty out as soon as the user lands here.
    @State private var newBadgeIdsAtOpen: Set<String> = []
    @State private var didFirstAppear = false
    /// HOW each of your medals was earned (`earned_detail` summaries), read
    /// once per visit — never per tile, since it decodes a UserDefaults blob.
    @State private var earnedSummaries: [String: String] = [:]

    var body: some View {
        ZStack {
            // Gradient background
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    // Header stats card
                    badgeStatsHeader
                        .padding(.horizontal)
                    
                    // Filter section
                    filterSection

                    // Per-category progress (skipped for All — header covers it —
                    // and New, which is inherently all-earned).
                    if selectedFilter != .all && selectedFilter != .new {
                        filterProgressCaption
                    }

                    // Badges grid
                    if filteredBadges.isEmpty {
                        emptyStateView
                    } else {
                        badgesGridView
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle("Medals")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Snapshot "new" badge IDs BEFORE we mark them viewed so the New filter
            // and any badges that were unread keep their visual treatment on this visit.
            if !didFirstAppear {
                didFirstAppear = true
                newBadgeIdsAtOpen = Set(
                    userManager.currentUser.badges.filter { $0.isNew }.map { $0.id }
                )
                selectedFilter = initialFilter
            }
            earnedSummaries = MedalStory.summaries()

            // Show confetti for new badges
            if userManager.hasNewBadges {
                showConfetti = true

                // Mark badges as viewed after displaying (also syncs to server)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    userManager.markBadgesAsViewed()
                }
            }

            // If we were given an initial badge from the home screen,
            // immediately navigate to its detail inside the Badges nav stack.
            if let initialBadge, selectedBadge == nil {
                selectedBadge = initialBadge
                isShowingDetail = true
            }
        }
        .task {
            await userManager.refreshBadgesFromServer()
            earnedSummaries = MedalStory.summaries()
        }
        .confetti(isShowing: $showConfetti)
        .navigationDestination(isPresented: $isShowingDetail) {
            // Only show when we actually have a badge selected
            if let badge = selectedBadge {
                BadgeDetailView(badge: badge, userManager: userManager)
            }
        }
    }
    
    // MARK: - Stats Header

    /// Earned X of Y, the completion ring, the rarest medal on the shelf and
    /// the rarity split — one card, read left to right.
    private var badgeStatsHeader: some View {
        let earned = userManager.currentUser.badges.filter { !$0.isLocked }
        let earnedCount = earned.count
        let totalCount = userManager.currentUser.getAllBadges().count
        let progress = totalCount > 0 ? Double(earnedCount) / Double(totalCount) : 0
        let rarest = MedalStory.rarest(in: earned)

        return VStack(spacing: 16) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed, MADTheme.Colors.madRed.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text(ProgressCalculator.formatProgress(progress))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(earnedCount)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("of \(totalCount)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .lineLimit(1)
                        Text("medals earned")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    if let rarest {
                        HStack(spacing: 8) {
                            MedalView(badge: rarest, size: 24, showShimmer: false)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("RAREST")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundColor(rarest.rarity.color)
                                Text(rarest.name)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Spacer(minLength: 0)
            }

            // Rarity breakdown
            HStack(spacing: 8) {
                rarityCounter(for: .legendary)
                rarityCounter(for: .rare)
                rarityCounter(for: .common)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func rarityCounter(for rarity: BadgeRarity) -> some View {
        let count = userManager.currentUser.badges.filter { !$0.isLocked && $0.rarity == rarity }.count

        return HStack(spacing: 5) {
            Circle()
                .fill(rarity.color)
                .frame(width: 7, height: 7)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(rarity.rawValue.capitalized)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(rarity.color.opacity(0.13)))
    }

    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BadgeFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.title,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        action: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedFilter = filter
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Badges Grid
    
    private var filteredBadges: [Badge] {
        let allBadges = userManager.currentUser.getAllBadges()

        switch selectedFilter {
        case .all:
            return allBadges
        case .streak:
            return allBadges.filter { $0.id.starts(with: "streak_") || $0.id.starts(with: "consistency_") }
        case .miles:
            return allBadges.filter { $0.id.starts(with: "miles_") }
        case .speed:
            return allBadges.filter { $0.id.starts(with: "pace_") }
        case .distance:
            return allBadges.filter { $0.id.starts(with: "daily_") }
        case .challenges:
            return allBadges.filter { $0.id.starts(with: "challenge_") }
        case .social:
            // Story / hype / nudge / competition medals, grouped by family then
            // by tier so the progression reads cleanly.
            return allBadges
                .filter { b in BadgeFilter.socialPrefixes.contains { b.id.hasPrefix($0) } }
                .sorted { Self.socialSortKey($0.id) < Self.socialSortKey($1.id) }
        case .buddy:
            return allBadges
                .filter { b in BadgeFilter.buddyPrefixes.contains { b.id.hasPrefix($0) } }
                .sorted { Self.buddySortKey($0.id) < Self.buddySortKey($1.id) }
        case .ghost:
            return allBadges
                .filter { b in BadgeFilter.ghostPrefixes.contains { b.id.hasPrefix($0) } }
                .sorted { Self.familySortKey($0.id, BadgeFilter.ghostPrefixes)
                    < Self.familySortKey($1.id, BadgeFilter.ghostPrefixes) }
        case .holiday:
            // Calendar order — the catalog's own order.
            let order = HolidayKey.allCases.map(\.badgeId)
            return allBadges
                .filter { $0.id.hasPrefix(HolidayKey.badgePrefix) }
                .sorted { (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count) }
        case .new:
            // Use the on-open snapshot so the list survives mark-as-viewed.
            let snapshot = newBadgeIdsAtOpen
            return allBadges.filter { ($0.isNew || snapshot.contains($0.id)) && !$0.isLocked }
        }
    }

    /// Orders a buddy medal by family (walks → crew → races won), then tier.
    private static func buddySortKey(_ id: String) -> (Int, Int) {
        familySortKey(id, BadgeFilter.buddyPrefixes)
    }

    /// Orders a medal by its family's position in `prefixes`, then by the
    /// numeric tier its id ends with.
    private static func familySortKey(_ id: String, _ prefixes: [String]) -> (Int, Int) {
        let family = prefixes.firstIndex { id.hasPrefix($0) } ?? prefixes.count
        let tier = Int(id.split(separator: "_").last ?? "") ?? 0
        return (family, tier)
    }

    /// Orders a social badge by family (story → hype → nudge → competitions),
    /// then by numeric tier within the family.
    private static func socialSortKey(_ id: String) -> (Int, Int) {
        let family = BadgeFilter.socialPrefixes.firstIndex { id.hasPrefix($0) }
            ?? BadgeFilter.socialPrefixes.count
        let tier = Int(id.split(separator: "_").last ?? "") ?? 0
        return (family, tier)
    }

    private static let shimmeringMedalLimit = 3

    private var filterProgressCaption: some View {
        let earned = filteredBadges.filter { !$0.isLocked }.count
        let total = filteredBadges.count
        return HStack(spacing: 6) {
            Image(systemName: earned == total && total > 0 ? "checkmark.seal.fill" : selectedFilter.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(earned == total && total > 0 ? .green : MADTheme.Colors.madRed)
            Text("\(earned) of \(total) \(selectedFilter.title.lowercased()) medals earned")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal)
    }

    private var badgesGridView: some View {
        let badges = filteredBadges
        let user = userManager.currentUser
        // Only the few most recently earned medals sweep. Every shimmer is a
        // repeatForever re-composite of a 3D-tilted, shadowed disc, and a full
        // shelf of them kept the whole grid re-rendering offscreen. At rest a
        // medal with and without the sweep is the same picture.
        let shimmering = Set(
            badges.filter { !$0.isLocked }
                .sorted { $0.dateAwarded > $1.dateAwarded }
                .prefix(Self.shimmeringMedalLimit)
                .map(\.id)
        )
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ],
            spacing: 16
        ) {
            ForEach(badges, id: \.id) { badge in
                Button {
                    badge.isLocked ? MADHaptics.tap() : MADHaptics.action()
                    selectedBadge = badge
                    isShowingDetail = true
                } label: {
                    PremiumBadgeCard(
                        badge: badge,
                        showShimmer: shimmering.contains(badge.id),
                        progress: badge.isLocked ? MedalProgress.forLocked(badge, user: user) : nil,
                        earnedStory: badge.isLocked ? nil : MedalStory.measuredLine(for: badge, summaries: earnedSummaries)
                    )
                }
                .buttonStyle(BadgeCardButtonStyle())
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text(selectedFilter == .all ? "No Medals Yet" : "No \(selectedFilter.title) Medals")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(selectedFilter == .all
                 ? "Complete running goals and milestones to earn medals!"
                 : "Keep running to unlock medals in this category!")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Premium Badge Card

/// One medal tile. Every tile is the same height whatever it says: the medal,
/// a two-line name, then a fixed footer — rarity, then either WHEN it was
/// earned (plus the measured line, for the families that have one) or, while
/// locked, how close you are (or what it asks, when we can't measure it).
struct PremiumBadgeCard: View {
    let badge: Badge
    var showShimmer: Bool = true
    /// Locked medals only: an honest measure of how close the viewer is.
    var progress: MedalProgress? = nil
    /// Earned medals only: a line worth reading ("You ran a 7:42 mile").
    var earnedStory: String? = nil

    static let footerHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                MedalView(badge: badge, size: 84, showShimmer: showShimmer)
            }
            .frame(width: 104, height: 100)
            .overlay(alignment: .topTrailing) {
                if badge.isNew && !badge.isLocked {
                    newTag
                }
            }
            // Fun only: the Flamey item this medal unlocks, on its corner.
            .overlay(alignment: .bottomTrailing) {
                FlameyMedalItemGlyphLive(badgeId: badge.id, earned: !badge.isLocked)
                    .offset(x: 2, y: -4)
            }

            Text(badge.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(badge.isLocked ? .white.opacity(0.45) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(height: 36, alignment: .top)

            footer
                .frame(height: Self.footerHeight, alignment: .top)
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 6) {
            rarityLine
            if badge.isLocked {
                if let progress {
                    MedalProgressBar(fraction: progress.fraction, tint: badge.rarity.color)
                        .padding(.horizontal, 6)
                    Text(progress.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(badge.description)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            } else {
                if let earnedStory {
                    Text(earnedStory)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("Earned \(MedalStory.shortDate(badge.dateAwarded))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
    }

    /// "LEGENDARY" — or, when a measured line takes the footer, "LEGENDARY · SEP 30"
    /// so the date is never lost. Locked medals say what they WILL be, dimmed.
    private var rarityLine: some View {
        HStack(spacing: 4) {
            if badge.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .black))
                    .accessibilityHidden(true)
            }
            Text(rarityText)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(badge.isLocked ? .white.opacity(0.32) : badge.rarity.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(badge.isLocked ? Color.white.opacity(0.05) : badge.rarity.color.opacity(0.15))
        )
    }

    private var rarityText: String {
        let rarity = badge.rarity.rawValue.uppercased()
        if !badge.isLocked, earnedStory != nil {
            return "\(rarity) · \(MedalStory.shortDate(badge.dateAwarded).uppercased())"
        }
        return rarity
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20)
        return shape
            .fill(
                LinearGradient(
                    colors: badge.isLocked
                        ? [Color.white.opacity(0.035), Color.white.opacity(0.02)]
                        : [badge.rarity.color.opacity(0.13), Color.white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Earned tiles wear their rarity as a light along the top edge.
            .overlay(alignment: .top) {
                if !badge.isLocked {
                    LinearGradient(
                        colors: [.clear, badge.rarity.color.opacity(0.9), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 2)
                    .padding(.horizontal, 22)
                }
            }
            .overlay(
                shape.stroke(
                    badge.isLocked ? Color.white.opacity(0.06) : badge.rarity.color.opacity(0.28),
                    lineWidth: 1
                )
            )
    }

    private var newTag: some View {
        Text("NEW")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Capsule().fill(MADTheme.Colors.madRed))
            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            .offset(x: 4, y: 2)
    }
}

/// A thin capsule bar — the locked tile's "how close".
struct MedalProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Medal progress & story

/// What a LOCKED medal can honestly say about how close you are. Mirrors
/// `BadgeDetailView.lockedProgressCard` family-for-family (same inputs, same
/// targets) so the tile and the screen it opens never disagree; families that
/// screen doesn't measure (pace has no bar there either) return nil and the
/// tile shows the requirement instead. A measure at or past the target on a
/// still-locked medal is a sync lag, not progress — nil there too, rather
/// than a full bar under a lock.
struct MedalProgress: Equatable {
    let fraction: Double
    let label: String

    static func forLocked(_ badge: Badge, user: User) -> MedalProgress? {
        guard badge.isLocked else { return nil }
        let id = badge.id
        if id.hasPrefix("streak_") || id.hasPrefix("consistency_") {
            guard let target = number(in: id), target > 0 else { return nil }
            let current = max(0, user.streak)
            guard current < target else { return nil }
            return MedalProgress(fraction: Double(current) / Double(target),
                                 label: "\(current) of \(target) days")
        }
        if id.hasPrefix("miles_") {
            guard let target = number(in: id), target > 0 else { return nil }
            return distance(current: user.totalMiles, target: Double(target), prefix: nil)
        }
        if id.hasPrefix("daily_") {
            guard let target = dailyTargetMiles[id] else { return nil }
            return distance(current: user.mostMilesInOneDay, target: target, prefix: "Best day ")
        }
        return nil
    }

    /// Miles in, display unit out: "41.2 / 100 mi" (or km).
    private static func distance(current: Double, target: Double, prefix: String?) -> MedalProgress? {
        let cur = max(0, current)
        guard cur < target else { return nil }
        let curShown = ((cur.inDisplayUnit * 10).rounded(.down)) / 10
        let targetShown = target.inDisplayUnit
        let targetText = targetShown.rounded() == targetShown || targetShown >= 100
            ? String(format: "%.0f", targetShown.rounded())
            : String(format: "%.1f", targetShown)
        let label = "\(prefix ?? "")\(String(format: "%.1f", curShown)) / \(targetText) \(DistanceUnits.current.abbreviation)"
        return MedalProgress(fraction: cur / target, label: label)
    }

    private static func number(in id: String) -> Int? {
        id.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.first
    }

    /// Same table as `BadgeDetailView.dailyTargetMiles` (private there).
    private static let dailyTargetMiles: [String: Double] = [
        "daily_2": 2, "daily_3": 3.1, "daily_5": 5, "daily_8": 8, "daily_10": 10,
        "daily_10k": 6.2, "daily_half": 13.1, "daily_15": 15, "daily_20": 20,
        "daily_marathon": 26.2, "daily_50k": 31, "daily_ultra": 50,
    ]
}

/// The little stories medals tell on the grid and the showcase.
enum MedalStory {
    /// This account's "how earned" summaries by badge id (the server's
    /// `earned_detail.summary`). Own medals only — the store is per account.
    static func summaries() -> [String: String] {
        BadgeEarnedDetails.all().compactMapValues { entry in
            guard let s = entry.summary, !s.isEmpty else { return nil }
            return s
        }
    }

    /// A summary only when it carries something MEASURED — the pace you ran,
    /// the distance of the day, the margin over a ghost, the holiday walk. A
    /// streak or a lifetime-miles summary only restates the medal's own name
    /// ("You reached a 30-day streak" under "30 Day Streak"), so those tiles
    /// keep their date instead.
    static func measuredLine(for badge: Badge, summaries: [String: String]) -> String? {
        guard let summary = summaries[badge.id] else { return nil }
        let measured = ["pace_", "daily_", "holiday_", "ghost_margin_"]
        return measured.contains(where: { badge.id.hasPrefix($0) }) ? summary : nil
    }

    /// "Sep 30" this year, "Sep 30, 2025" otherwise.
    static func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Legendary · Sep 30" — the fallback line when there's no summary.
    static func rarityAndDate(_ badge: Badge) -> String {
        "\(badge.rarity.rawValue.capitalized) · \(shortDate(badge.dateAwarded))"
    }

    /// The rarest earned medal; ties go to the most recently earned.
    static func rarest(in earned: [Badge]) -> Badge? {
        func weight(_ r: BadgeRarity) -> Int {
            switch r { case .legendary: return 3; case .rare: return 2; case .common: return 1 }
        }
        return earned.max { a, b in
            let wa = weight(a.rarity), wb = weight(b.rarity)
            if wa != wb { return wa < wb }
            return a.dateAwarded < b.dateAwarded
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? MADTheme.Colors.madRed : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Badge Filter

enum BadgeFilter: CaseIterable {
    case all, streak, miles, speed, distance, challenges, social, buddy, ghost, holiday, new

    var title: String {
        switch self {
        case .all: return "All"
        case .streak: return "Streaks"
        case .miles: return "Miles"
        case .speed: return "Speed"
        case .distance: return "Distance"
        case .challenges: return "Challenges"
        case .social: return "Social"
        case .buddy: return "Buddy"
        case .ghost: return "Ghost"
        case .holiday: return "Holidays"
        case .new: return "New"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .streak: return "flame.fill"
        case .miles: return "figure.run"
        case .speed: return "bolt.fill"
        case .distance: return "road.lanes"
        case .challenges: return "trophy.fill"
        case .social: return "person.2.fill"
        case .buddy: return "figure.2"
        case .ghost: return "flag.checkered"
        case .holiday: return "gift.fill"
        case .new: return "sparkles"
        }
    }

    /// Badge-id prefixes that count as "social / app-function" medals, in the
    /// order they should appear under the Social filter.
    static let socialPrefixes = [
        "story_", "hype_", "nudge_",
        "comp_started_", "comp_entered_", "comp_won_", "comp_",
    ]

    /// Buddy Walk medal families, in progression order. Deliberately NOT folded
    /// into `socialPrefixes`: buddy medals are earned by doing a walk with
    /// someone, not by app-function activity, and burying seven of them at the
    /// end of the Social list is how a whole category goes unnoticed.
    static let buddyPrefixes = ["buddy_done_", "buddy_crew_", "buddy_won_"]

    /// Ghost race medal families, in progression order: races won, then the
    /// biggest single winning margin.
    static let ghostPrefixes = ["ghost_beat_", "ghost_margin_"]
}

// MARK: - Badge Card Button Style

struct BadgeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BadgesView(userManager: UserManager(), initialBadge: nil)
    }
}
