import SwiftUI

/// Profile showcase that displays up to 3 pinned badges side-by-side.
/// Used on both the local user's profile (with manage affordance) and friend profiles (read-only).
struct PinnedBadgesShowcase: View {
    /// Pinned badges, already ordered by pin slot ascending.
    let pinnedBadges: [Badge]
    /// When non-nil, an "Edit" pencil appears; tapping it invokes this closure.
    let onManageTapped: (() -> Void)?
    /// Tapping a filled slot.
    let onBadgeTapped: ((Badge) -> Void)?
    /// Display name for empty-state copy. Pass `nil` for the local user (we'll say "you").
    let ownerDisplayName: String?

    private static let slotCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Showcase")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
                if let onManageTapped {
                    Button(action: onManageTapped) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                            Text(pinnedBadges.isEmpty ? "Add" : "Edit")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MADTheme.Colors.madRed.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(0..<Self.slotCount, id: \.self) { slot in
                    if slot < pinnedBadges.count {
                        let badge = pinnedBadges[slot]
                        Button {
                            onBadgeTapped?(badge)
                        } label: {
                            PinnedBadgeSlotFilled(badge: badge)
                        }
                        .buttonStyle(BadgeCardButtonStyle())
                        .disabled(onBadgeTapped == nil)
                    } else {
                        PinnedBadgeSlotEmpty(isInteractive: onManageTapped != nil) {
                            onManageTapped?()
                        }
                    }
                }
            }

            if pinnedBadges.isEmpty {
                Text(emptyStateText)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var emptyStateText: String {
        if onManageTapped != nil {
            return "Pin up to 3 of your favorite medals to show off on your profile."
        }
        if let name = ownerDisplayName {
            return "\(name) hasn't pinned any medals yet."
        }
        return "No pinned medals yet."
    }
}

private struct PinnedBadgeSlotFilled: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [badge.rarity.color.opacity(0.35), badge.rarity.color.opacity(0)],
                            center: .center,
                            startRadius: 15,
                            endRadius: 45
                        )
                    )
                    .frame(width: 90, height: 90)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: medalGradientColors(for: badge),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), badge.rarity.color.opacity(0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: badge.rarity.color.opacity(0.4), radius: 10, x: 0, y: 4)

                Image(systemName: iconName(for: badge))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
            }
            .frame(width: 90, height: 90)

            Text(badge.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PinnedBadgeSlotEmpty: View {
    let isInteractive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 64, height: 64)

                    Image(systemName: isInteractive ? "plus" : "pin")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .frame(width: 90, height: 90)

                Text(" ")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
    }
}

// MARK: - Visual helpers (mirrors PremiumBadgeCard styling so the showcase looks consistent)

func iconName(for badge: Badge) -> String {
    if badge.id.starts(with: "streak_") || badge.id.starts(with: "consistency_") {
        return "flame.fill"
    } else if badge.id.starts(with: "miles_") {
        return "figure.run"
    } else if badge.id.starts(with: "pace_") {
        return "bolt.fill"
    } else if badge.id.starts(with: "daily_") {
        return "figure.run.circle.fill"
    } else if badge.id.starts(with: "challenge_") {
        return "trophy.fill"
    } else if badge.id.starts(with: "hidden_") || badge.id.starts(with: "secret_") || badge.id.starts(with: "special_") {
        return "sparkles"
    }
    return "star.fill"
}

func medalGradientColors(for badge: Badge) -> [Color] {
    switch badge.rarity {
    case .legendary:
        return [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.45, blue: 0.0)]
    case .rare:
        return [Color(red: 0.7, green: 0.4, blue: 1.0), Color(red: 0.5, green: 0.15, blue: 0.85)]
    case .common:
        return [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.15, green: 0.45, blue: 0.85)]
    }
}
