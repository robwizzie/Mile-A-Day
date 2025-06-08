import SwiftUI

struct BadgesView: View {
    @ObservedObject var userManager: UserManager
    @State private var showConfetti = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
    
    // Grid layout for badges
    private var badgesGridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
            ForEach(userManager.currentUser.badges) { badge in
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
                    .fill(badge.rarity.color.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: badgeIcon(for: badge))
                    .font(.system(size: 35))
                    .foregroundColor(badge.rarity.color)
            }
            .overlay(alignment: .topTrailing) {
                if badge.isNew {
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
                .multilineTextAlignment(.center)
            
            Text(badge.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text(rarityLabel(for: badge.rarity))
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badge.rarity.color.opacity(0.2))
                .foregroundColor(badge.rarity.color)
                .cornerRadius(10)
            
            Text("Earned \(badge.dateAwarded.formattedDate)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 150)
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: badge.rarity.color.opacity(0.2), radius: 5, x: 0, y: 2)
    }
    
    // Helper to get appropriate icon for badge
    private func badgeIcon(for badge: Badge) -> String {
        if badge.id.starts(with: "streak_") {
            return "flame.fill"
        } else if badge.id.starts(with: "miles_") {
            return "figure.run"
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

#Preview {
    NavigationStack {
        BadgesView(userManager: UserManager())
    }
} 