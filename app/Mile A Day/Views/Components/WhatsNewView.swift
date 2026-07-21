import SwiftUI

// MARK: - Catalog

/// One feature bullet on a What's New page.
struct WhatsNewFeature: Identifiable {
    let emoji: String
    let title: String
    let blurb: String
    let tint: Color
    var id: String { title }
}

/// One release's worth of announcements. `id` is monotonically increasing —
/// bump it (and add a new entry at the top of `releases`) each update; users
/// auto-see a release exactly once and can reopen it from Settings anytime.
struct WhatsNewRelease: Identifiable {
    let id: Int
    let versionLabel: String
    let headline: String
    let features: [WhatsNewFeature]
}

enum WhatsNewCatalog {
    /// Newest first. Edit copy freely — keep it user-facing (no internal
    /// names, no "beta"), one short line per feature.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            id: 1,
            versionLabel: "July 2026 Update",
            headline: "Your streak just got backup",
            features: [
                WhatsNewFeature(
                    emoji: "\u{1F525}",
                    title: "Streak Tokens",
                    blurb: "Earn Double Down, Streak Save, and Streak Assist by running — and use them to protect your streak when life happens.",
                    tint: .orange
                ),
                WhatsNewFeature(
                    emoji: "\u{1F91D}",
                    title: "Save a friend's streak",
                    blurb: "Go 20 miles past your goal to earn an Assist, then rescue a friend the day after their streak breaks.",
                    tint: MADTheme.Colors.madRed
                ),
                WhatsNewFeature(
                    emoji: "\u{1F3C5}",
                    title: "The Pure Flame",
                    blurb: "A gold flame on your profile when every day of your streak was earned on the day.",
                    tint: .yellow
                ),
                WhatsNewFeature(
                    emoji: "\u{1F4AC}",
                    title: "Comments & collabs",
                    blurb: "Comment on friends' posts and share a run together as a collab.",
                    tint: MADTheme.Colors.walkBlue
                ),
                WhatsNewFeature(
                    emoji: "\u{1F5D3}",
                    title: "Your workouts, organized",
                    blurb: "A calendar of every run, swipe between workouts, and photos that load instantly.",
                    tint: .green
                ),
                WhatsNewFeature(
                    emoji: "\u{1F44F}",
                    title: "Unlimited hypes",
                    blurb: "Cheer your friends as much as you want — no daily cap.",
                    tint: .purple
                ),
            ]
        ),
    ]

    static var latest: WhatsNewRelease { releases[0] }
}

// MARK: - Seen tracking

enum WhatsNewManager {
    private static let seenKey = "whatsNewSeenReleaseId"

    /// Auto-present once per release — but never on a brand-new install
    /// (the welcome tour owns that moment; we just mark the release seen).
    static var shouldAutoPresent: Bool {
        let seen = UserDefaults.standard.integer(forKey: seenKey)
        guard WhatsNewCatalog.latest.id > seen else { return false }
        if !UserDefaults.standard.bool(forKey: "hasSeenWelcomeTour") {
            markSeen()
            return false
        }
        return true
    }

    static func markSeen() {
        UserDefaults.standard.set(WhatsNewCatalog.latest.id, forKey: seenKey)
    }

    /// Dev helper: forget the seen marker so the popup auto-fires again.
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: seenKey)
    }
}

// MARK: - Sheet

/// The What's New page: auto-appears once per release after an update, and
/// reopens anytime from Settings → What's New.
struct WhatsNewView: View {
    var release: WhatsNewRelease = WhatsNewCatalog.latest
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        header
                        VStack(spacing: MADTheme.Spacing.sm) {
                            ForEach(Array(release.features.enumerated()), id: \.element.id) { index, feature in
                                featureRow(feature)
                                    .opacity(revealed ? 1 : 0)
                                    .offset(y: revealed ? 0 : 14)
                                    .animation(
                                        .spring(response: 0.5, dampingFraction: 0.8)
                                            .delay(0.15 + Double(index) * 0.07),
                                        value: revealed
                                    )
                            }
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.lg)
                }

                // Pinned dismiss CTA
                Button {
                    WhatsNewManager.markSeen()
                    dismiss()
                } label: {
                    Text("Keep Running")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(MADTheme.Colors.redGradient)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.md)
            }
        }
        .onAppear {
            revealed = true
            // Opening the sheet counts as seeing the release, however it closes
            // (swipe-down included) — never nag someone twice.
            WhatsNewManager.markSeen()
        }
    }

    private var header: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(MADTheme.Colors.redGradient)
                    .frame(width: 64, height: 64)
                    .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 12)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }

            Text("What's New")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)

            Text(release.headline)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Text(release.versionLabel)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundColor(MADTheme.Colors.madRed)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(MADTheme.Colors.madRed.opacity(0.14)))
        }
        .frame(maxWidth: .infinity)
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(feature.tint.opacity(0.16))
                    .frame(width: 44, height: 44)
                Text(feature.emoji)
                    .font(.system(size: 21))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text(feature.blurb)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}
