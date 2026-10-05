import SwiftUI

/// Compact badge row for inline display in cards: the medal, its name, then
/// either when it was earned or — while locked — how close you are (when the
/// family can be measured; see `MedalProgress`). Tapping opens BadgeDetailView.
struct BadgeRowCard: View {
    let badge: Badge
    var userManager: UserManager?

    @State private var isShowingDetail = false

    private var progress: MedalProgress? {
        guard badge.isLocked, let user = userManager?.currentUser else { return nil }
        return MedalProgress.forLocked(badge, user: user)
    }

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                // Mini medal — shared premium look (no shimmer at this small size).
                MedalView(badge: badge, size: 44, showShimmer: false)
                    // Fun only: the Flamey item this medal unlocks.
                    .overlay(alignment: .bottomTrailing) {
                        FlameyMedalItemGlyphLive(badgeId: badge.id, earned: !badge.isLocked)
                            .scaleEffect(0.62, anchor: .bottomTrailing)
                            .offset(x: 6, y: 4)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(badge.name)
                        .font(MADTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(badge.isLocked ? .secondary : .primary)
                        .lineLimit(1)

                    if let progress {
                        HStack(spacing: 8) {
                            MedalProgressBar(fraction: progress.fraction, tint: badge.rarity.color)
                                .frame(maxWidth: 90)
                            Text(progress.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundColor(badge.isLocked ? .secondary.opacity(0.6) : badge.rarity.color)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if badge.isLocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(badge.rarity.color)
                        .accessibilityLabel("Earned")
                }
            }
            .padding(.vertical, MADTheme.Spacing.xs)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(badge.isLocked ? 0.75 : 1.0)
        .navigationDestination(isPresented: $isShowingDetail) {
            BadgeDetailView(badge: badge, userManager: userManager)
        }
    }

    /// "RARE · EARNED SEP 30" — or just the rarity while locked.
    private var subtitle: String {
        let rarity = badge.rarity.rawValue.uppercased()
        guard !badge.isLocked else { return rarity }
        return "\(rarity) · EARNED \(MedalStory.shortDate(badge.dateAwarded).uppercased())"
    }
}
