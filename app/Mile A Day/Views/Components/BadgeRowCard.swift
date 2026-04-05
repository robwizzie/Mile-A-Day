import SwiftUI

/// Compact badge row for inline display in cards. Shows the medal circle, name, rarity, and lock/earned status.
/// Tapping navigates to BadgeDetailView.
struct BadgeRowCard: View {
    let badge: Badge
    var userManager: UserManager?

    @State private var isShowingDetail = false

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

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                // Mini medal
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: badge.isLocked
                                    ? [Color(white: 0.25), Color(white: 0.15)]
                                    : medalGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(
                                    badge.isLocked
                                        ? Color.white.opacity(0.08)
                                        : Color.white.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: badge.isLocked ? .clear : badge.rarity.color.opacity(0.3),
                            radius: 6, x: 0, y: 3
                        )

                    if badge.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    } else {
                        Image(systemName: badgeIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    }
                }

                // Name & rarity
                VStack(alignment: .leading, spacing: 2) {
                    Text(badge.name)
                        .font(MADTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(badge.isLocked ? .secondary : .primary)

                    Text(badge.rarity.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(badge.isLocked ? .secondary.opacity(0.5) : badge.rarity.color)
                }

                Spacer()

                // Status
                if badge.isLocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(badge.rarity.color)
                }
            }
            .padding(.vertical, MADTheme.Spacing.xs)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(badge.isLocked ? 0.6 : 1.0)
        .navigationDestination(isPresented: $isShowingDetail) {
            BadgeDetailView(badge: badge, userManager: userManager)
        }
    }
}
