import SwiftUI

struct BadgesView: View {
    @ObservedObject var userManager: UserManager
    @State private var showConfetti = false
    @State private var selectedFilter: BadgeFilter = .all
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Badge count header
                if !userManager.currentUser.badges.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Your Badges")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                            let earnedCount = filteredBadges.filter { !$0.isLocked }.count
                            let totalCount = filteredBadges.count
                            Text("\(earnedCount) of \(totalCount)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Filter buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(BadgeFilter.allCases, id: \.self) { filter in
                                    FilterButton(
                                        title: filter.title,
                                        isSelected: selectedFilter == filter,
                                        action: { selectedFilter = filter }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                }
                
                if userManager.currentUser.badges.isEmpty {
                    emptyBadgesView
                } else {
                    badgesGridView
                }
            }
            .padding()
        }
        .navigationTitle("Your Badges")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Show confetti for new badges
            if userManager.hasNewBadges {
                showConfetti = true
                
                // Mark badges as viewed after displaying
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    userManager.markBadgesAsViewed()
                }
            }
        }
        .confetti(isShowing: $showConfetti)
    }
    
    // Empty state view
    private var emptyBadgesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.7))
            
            Text("No Badges Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Complete running goals and milestones to earn badges!")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // Filtered badges based on selected filter
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
        case .new:
            return allBadges.filter { $0.isNew && !$0.isLocked }
        }
    }
    
    // Grid layout for badges
    private var badgesGridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
            ForEach(filteredBadges) { badge in
                BadgeCard(badge: badge)
            }
        }
    }
}

// Badge Card Component
struct BadgeCard: View {
    let badge: Badge
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badge.isLocked ? Color.gray.opacity(0.2) : badge.rarity.color.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                if badge.isLocked {
                    // Locked badge appearance
                    ZStack {
                        Image(systemName: badgeIcon(for: badge))
                            .font(.system(size: 35))
                            .foregroundColor(.gray)
                            .opacity(0.3)
                        
                        // Lock overlay
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                            .offset(x: 20, y: -20)
                    }
                } else {
                    // Unlocked badge appearance
                    Image(systemName: badgeIcon(for: badge))
                        .font(.system(size: 35))
                        .foregroundColor(badge.rarity.color)
                }
            }
            .overlay(alignment: .topTrailing) {
                if badge.isNew && !badge.isLocked {
                    Text("NEW")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .cornerRadius(8)
                        .offset(x: 10, y: -5)
                }
            }
            
            Text(badge.name)
                .font(.headline)
                .foregroundColor(badge.isLocked ? .gray : .primary)
                .multilineTextAlignment(.center)
            
            Text(badge.description)
                .font(.caption)
                .foregroundColor(badge.isLocked ? .gray.opacity(0.7) : .secondary)
                .multilineTextAlignment(.center)
            
            Text(rarityLabel(for: badge.rarity))
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badge.isLocked ? Color.gray.opacity(0.2) : badge.rarity.color.opacity(0.2))
                .foregroundColor(badge.isLocked ? .gray : badge.rarity.color)
                .cornerRadius(10)
            
            if badge.isLocked {
                Text("LOCKED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
            } else {
                Text("Earned \(badge.dateAwarded.formattedDate)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 150)
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: badge.isLocked ? Color.gray.opacity(0.1) : badge.rarity.color.opacity(0.2), radius: 5, x: 0, y: 2)
    }
    
    // Helper to get appropriate icon for badge
    private func badgeIcon(for badge: Badge) -> String {
        if badge.id.starts(with: "streak_") {
            return "flame.fill"
        } else if badge.id.starts(with: "miles_") {
            return "figure.run"
        } else if badge.id.starts(with: "pace_") {
            return "bolt.fill"
        } else if badge.id.starts(with: "daily_") {
            return "figure.run.circle.fill"
        } else if badge.id.starts(with: "consistency_") {
            return "calendar.badge.clock"
        } else {
            return "star.fill"
        }
    }
    
    // Helper to get rarity label
    private func rarityLabel(for rarity: BadgeRarity) -> String {
        switch rarity {
        case .common:
            return "COMMON"
        case .rare:
            return "RARE"
        case .legendary:
            return "LEGENDARY"
        }
    }
}

// MARK: - Badge Filter
enum BadgeFilter: CaseIterable {
    case all, streak, miles, speed, distance, new
    
    var title: String {
        switch self {
        case .all:
            return "All"
        case .streak:
            return "Streaks"
        case .miles:
            return "Miles"
        case .speed:
            return "Speed"
        case .distance:
            return "Distance"
        case .new:
            return "New"
        }
    }
}

// MARK: - Filter Button
struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color("appPrimary") : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationStack {
        BadgesView(userManager: UserManager())
    }
} 