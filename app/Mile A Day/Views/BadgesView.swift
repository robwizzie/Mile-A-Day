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
    
    private var badgeStatsHeader: some View {
        let earnedCount = userManager.currentUser.badges.filter { !$0.isLocked }.count
        let totalCount = userManager.currentUser.getAllBadges().count
        let progress = totalCount > 0 ? Double(earnedCount) / Double(totalCount) : 0
        
        return VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Earned count
                VStack(spacing: 4) {
                    Text("\(earnedCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Earned")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed, MADTheme.Colors.madRed.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                // Total count
                VStack(spacing: 4) {
                    Text("\(totalCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Total")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Rarity breakdown
            HStack(spacing: 16) {
                rarityCounter(for: .legendary)
                rarityCounter(for: .rare)
                rarityCounter(for: .common)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func rarityCounter(for rarity: BadgeRarity) -> some View {
        let count = userManager.currentUser.badges.filter { !$0.isLocked && $0.rarity == rarity }.count
        
        return HStack(spacing: 6) {
            Circle()
                .fill(rarity.color)
                .frame(width: 8, height: 8)
            
            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(rarity.rawValue.capitalized)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(rarity.color.opacity(0.15))
        )
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
        case .new:
            // Use the on-open snapshot so the list survives mark-as-viewed.
            let snapshot = newBadgeIdsAtOpen
            return allBadges.filter { ($0.isNew || snapshot.contains($0.id)) && !$0.isLocked }
        }
    }

    /// Orders a social badge by family (story → hype → nudge → competitions),
    /// then by numeric tier within the family.
    private static func socialSortKey(_ id: String) -> (Int, Int) {
        let family = BadgeFilter.socialPrefixes.firstIndex { id.hasPrefix($0) }
            ?? BadgeFilter.socialPrefixes.count
        let tier = Int(id.split(separator: "_").last ?? "") ?? 0
        return (family, tier)
    }

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
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ],
            spacing: 16
        ) {
            ForEach(filteredBadges, id: \.id) { badge in
                Button {
                    UIImpactFeedbackGenerator(style: badge.isLocked ? .light : .medium).impactOccurred()
                    selectedBadge = badge
                    isShowingDetail = true
                } label: {
                    PremiumBadgeCard(badge: badge)
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

struct PremiumBadgeCard: View {
    let badge: Badge
    
    private var badgeIcon: String {
        // Shared resolver covers every category, incl. story / hype / competition.
        iconName(for: badge)
    }
    
    var body: some View {
        VStack(spacing: 14) {
            // Badge medal — fixed 110pt frame so locked cards (which have no glow) match unlocked
            ZStack {
                // Outer glow for unlocked
                if !badge.isLocked {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [badge.rarity.color.opacity(0.4), badge.rarity.color.opacity(0)],
                                center: .center,
                                startRadius: 20,
                                endRadius: 55
                            )
                        )
                        .frame(width: 110, height: 110)
                }
                
                // Medal base
                Circle()
                    .fill(
                        LinearGradient(
                            colors: badge.isLocked ? [
                                Color(white: 0.25),
                                Color(white: 0.15)
                            ] : medalGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: badge.isLocked ? [
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.05)
                                    ] : [
                                        Color.white.opacity(0.5),
                                        badge.rarity.color.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: badge.isLocked ? .clear : badge.rarity.color.opacity(0.4),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                
                // Inner ring
                if !badge.isLocked {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 60, height: 60)
                }
                
                // Icon
                if badge.isLocked {
                    ZStack {
                        Image(systemName: badgeIcon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white.opacity(0.15))
                        
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                            .offset(x: 18, y: -18)
                    }
                } else {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                }
                
                // Tags
                if badge.isNew && !badge.isLocked {
                    newTag
                        .offset(x: 28, y: -28)
                }
            }
            .frame(width: 110, height: 110)

            // Badge name — reserves 2 lines of space so every card is the same height
            Text(badge.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(badge.isLocked ? .white.opacity(0.4) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 36, alignment: .top)
            
            // Rarity pill
            Text(badge.rarity.rawValue.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundColor(badge.isLocked ? .white.opacity(0.25) : badge.rarity.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(badge.isLocked ? Color.white.opacity(0.05) : badge.rarity.color.opacity(0.15))
                )
            
            // Date or status
            if badge.isLocked {
                Text("TAP TO VIEW")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.25))
            } else {
                Text(badge.dateAwarded.formattedShortDate)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: badge.isLocked ? [
                        Color.white.opacity(0.03),
                        Color.white.opacity(0.02)
                    ] : [
                        badge.rarity.color.opacity(0.08),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: badge.isLocked ? [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ] : [
                                badge.rarity.color.opacity(0.3),
                                badge.rarity.color.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
    
    private var medalGradientColors: [Color] {
        switch badge.rarity {
        case .legendary:
            return [
                Color(red: 1.0, green: 0.85, blue: 0.4),
                Color(red: 0.85, green: 0.55, blue: 0.15)
            ]
        case .rare:
            return [
                Color(red: 0.7, green: 0.5, blue: 0.9),
                Color(red: 0.5, green: 0.3, blue: 0.75)
            ]
        case .common:
            return [
                Color(red: 0.45, green: 0.65, blue: 0.95),
                Color(red: 0.3, green: 0.5, blue: 0.8)
            ]
        }
    }
    
    private var newTag: some View {
        Text("NEW")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [MADTheme.Colors.madRed, MADTheme.Colors.madRed.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
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
    case all, streak, miles, speed, distance, challenges, social, new

    var title: String {
        switch self {
        case .all: return "All"
        case .streak: return "Streaks"
        case .miles: return "Miles"
        case .speed: return "Speed"
        case .distance: return "Distance"
        case .challenges: return "Challenges"
        case .social: return "Social"
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
        case .new: return "sparkles"
        }
    }

    /// Badge-id prefixes that count as "social / app-function" medals, in the
    /// order they should appear under the Social filter.
    static let socialPrefixes = [
        "story_", "hype_", "nudge_",
        "comp_started_", "comp_entered_", "comp_won_", "comp_",
    ]
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
