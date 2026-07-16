import SwiftUI

/// Branded, shareable achievement cards (badge unlock + personal record),
/// rendered to a crisp image for the system share sheet. Deliberately share the
/// same dark-gradient / radial-glow / MADLogoMark language as
/// `CelebrationShareCardView` and `RunStatsCardView` so every card the app
/// produces reads as one family. Fixed 600×900 (4:5-ish portrait) at @3x.

/// Render a fixed-size share card to a crisp @3x image (a 600×900 card → an
/// 1800×2700 export), matching the existing celebration share pipeline
/// (`GoalCompletedCelebrationView.generateShareCardImage`).
@MainActor
func renderAchievementShareImage<Card: View>(_ card: Card) -> UIImage? {
    let renderer = ImageRenderer(content: card)
    renderer.scale = 3.0
    renderer.isOpaque = false
    return renderer.uiImage
}

// MARK: - Shared chrome

/// The dark gradient + a rarity/accent-tinted glow shared by every card.
private struct AchievementCardBackground: View {
    let glow: Color
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.05, green: 0.02, blue: 0.04),
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [glow.opacity(0.5), glow.opacity(0.14), .clear],
                center: UnitPoint(x: 0.5, y: 0.2),
                startRadius: 10, endRadius: 320
            )
        }
    }
}

private struct AchievementCardFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            MADLogoMark(size: 34)
            Text("Mile A Day")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

// MARK: - Badge share card

struct BadgeShareCardView: View {
    let badge: Badge

    private let cardWidth: CGFloat = 600
    private let cardHeight: CGFloat = 900

    var body: some View {
        ZStack {
            AchievementCardBackground(glow: badge.rarity.color)

            VStack(spacing: 22) {
                Spacer()

                Text("BADGE UNLOCKED")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.6))

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: medalGradientColors(for: badge),
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 220, height: 220)
                        .shadow(color: badge.rarity.color.opacity(0.6), radius: 30)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 3)
                        .frame(width: 220, height: 220)
                    Image(systemName: iconName(for: badge))
                        .font(.system(size: 96, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                }

                Text(badge.rarity.rawValue.uppercased())
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(
                        Capsule().fill(badge.rarity.color.opacity(0.35))
                            .overlay(Capsule().strokeBorder(badge.rarity.color, lineWidth: 1))
                    )

                VStack(spacing: 10) {
                    Text(badge.name)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(badge.description)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                Spacer()
                AchievementCardFooter().padding(.bottom, 40)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

// MARK: - Personal-record share card

/// A generic "big number" record card — reused for race PRs, best day, fastest
/// mile, etc. Callers format the value/unit/caption for their record type.
struct PRShareRecord {
    var icon: String
    var banner: String          // e.g. "PERSONAL RECORD"
    var value: String           // e.g. "6:42" or "5.20"
    var unit: String            // e.g. "/mi" or "mi"
    var title: String           // e.g. "Fastest Mile"
    var caption: String         // e.g. "Mar 3, 2026"
    var accent: Color = MADTheme.Colors.madRed
}

struct PRShareCardView: View {
    let record: PRShareRecord

    private let cardWidth: CGFloat = 600
    private let cardHeight: CGFloat = 900

    var body: some View {
        ZStack {
            AchievementCardBackground(glow: record.accent)

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: record.icon)
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.white, record.accent],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: record.accent.opacity(0.6), radius: 16)

                Text(record.banner)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundColor(record.accent)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(record.value)
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text(record.unit)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .shadow(color: record.accent.opacity(0.4), radius: 8)

                VStack(spacing: 6) {
                    Text(record.title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(record.caption)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

                Spacer()
                AchievementCardFooter().padding(.bottom, 40)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}
