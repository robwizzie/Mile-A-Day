import SwiftUI

struct BadgesView: View {
    @ObservedObject var userManager: UserManager
    /// Optional badge to immediately drill into when this screen first appears.
    let initialBadge: Badge?
    
    @State private var showConfetti = false
    @State private var selectedFilter: BadgeFilter = .all
    @State private var selectedBadge: Badge?
    @State private var isShowingDetail = false
    
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
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Show confetti for new badges
            if userManager.hasNewBadges {
                showConfetti = true
                
                // Mark badges as viewed after displaying
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
        // Also get earned hidden badges (they won't be in getAllBadges locked list)
        let earnedHiddenBadges = userManager.currentUser.badges.filter { $0.isHidden }
        
        switch selectedFilter {
        case .all:
            // Include earned hidden badges in all view
            var badges = allBadges
            for hidden in earnedHiddenBadges {
                if !badges.contains(where: { $0.id == hidden.id }) {
                    badges.append(hidden)
                }
            }
            return badges
        case .streak:
            return allBadges.filter { $0.id.starts(with: "streak_") || $0.id.starts(with: "consistency_") }
        case .miles:
            return allBadges.filter { $0.id.starts(with: "miles_") }
        case .speed:
            return allBadges.filter { $0.id.starts(with: "pace_") }
        case .distance:
            return allBadges.filter { $0.id.starts(with: "daily_") }
        case .secret:
            // Show only earned secret/hidden badges
            return earnedHiddenBadges
        case .new:
            return allBadges.filter { $0.isNew && !$0.isLocked }
        }
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
            if selectedFilter == .secret {
                // Special empty state for secret badges
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.purple.opacity(0.5))
                
                Text("No Secret Badges Yet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Secret badges are hidden achievements that you discover through special accomplishments. Keep running and exploring - you never know when you'll unlock one!")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                
                // Mystery hint cards
                VStack(spacing: 12) {
                    MysteryBadgeHint(hint: "Some secrets involve perfect numbers...")
                    MysteryBadgeHint(hint: "Combining achievements may reveal surprises...")
                    MysteryBadgeHint(hint: "Lucky streaks have special rewards...")
                }
                .padding(.top, 16)
            } else {
                Image(systemName: "trophy")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
                
                Text(selectedFilter == .all ? "No Badges Yet" : "No \(selectedFilter.title) Badges")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(selectedFilter == .all 
                     ? "Complete running goals and milestones to earn badges!"
                     : "Keep running to unlock badges in this category!")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Mystery Badge Hint

struct MysteryBadgeHint: View {
    let hint: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.purple.opacity(0.7))
            
            Text(hint)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Premium Badge Card

struct PremiumBadgeCard: View {
    let badge: Badge
    
    private var badgeIcon: String {
        if badge.id.starts(with: "streak_") || badge.id.starts(with: "consistency_") {
            return "flame.fill"
        } else if badge.id.starts(with: "miles_") {
            return "figure.run"
        } else if badge.id.starts(with: "pace_") {
            return "bolt.fill"
        } else if badge.id.starts(with: "daily_") {
            return "figure.run.circle.fill"
        } else if badge.id.starts(with: "hidden_") || badge.id.starts(with: "secret_") || badge.id.starts(with: "special_") {
            return "sparkles"
        } else {
            return "star.fill"
        }
    }
    
    var body: some View {
        VStack(spacing: 14) {
            // Badge medal
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
                if badge.isHidden && !badge.isLocked {
                    secretTag
                        .offset(x: 28, y: -28)
                } else if badge.isNew && !badge.isLocked {
                    newTag
                        .offset(x: 28, y: -28)
                }
            }
            
            // Badge name
            Text(badge.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(badge.isLocked ? .white.opacity(0.4) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
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
    
    private var secretTag: some View {
        HStack(spacing: 2) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(5)
        .background(
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple, Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
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
    case all, streak, miles, speed, distance, secret, new
    
    var title: String {
        switch self {
        case .all: return "All"
        case .streak: return "Streaks"
        case .miles: return "Miles"
        case .speed: return "Speed"
        case .distance: return "Distance"
        case .secret: return "Secret"
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
        case .secret: return "eye.slash.fill"
        case .new: return "sparkles"
        }
    }
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
