import SwiftUI

// MARK: - Catalog

/// One feature bullet on a What's New page. Icons are SF Symbols rendered in
/// tinted squircles — deliberately no emoji anywhere on this surface.
struct WhatsNewFeature: Identifiable {
    let icon: String
    let title: String
    let blurb: String
    let tint: Color
    var id: String { title }
}

/// One release's worth of announcements. `id` is monotonically increasing —
/// bump it (and add a new entry at the top of `releases`) each update; users
/// auto-see a release exactly once and can reopen it from Dashboard settings.
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
            id: 2,
            versionLabel: "Summer 2026 Update",
            headline: "The biggest update yet",
            features: [
                WhatsNewFeature(
                    icon: "square.grid.2x2.fill",
                    title: "A brand-new Dashboard",
                    blurb: "Your mile, your streak, and your tokens in one clean view — and it greets you with the day of your streak.",
                    tint: MADTheme.Colors.madRed
                ),
                WhatsNewFeature(
                    icon: "clock.badge.exclamationmark",
                    title: "Lock Screen countdown",
                    blurb: "Streak at risk in the evening? A live countdown appears on your Lock Screen with one-tap Start Mile.",
                    tint: .orange
                ),
                WhatsNewFeature(
                    icon: "snowflake",
                    title: "Streak stories",
                    blurb: "When a token saves a day — yours or a friend's — the app tells you the story, not just the math.",
                    tint: MADTheme.Colors.walkBlue
                ),
                WhatsNewFeature(
                    icon: "shield.lefthalf.filled",
                    title: "Tokens everywhere",
                    blurb: "On your dashboard, profile, widget, and watch — with meters that visibly tick as you run.",
                    tint: Color(red: 1.0, green: 0.84, blue: 0.35)
                ),
                WhatsNewFeature(
                    icon: "chart.bar.fill",
                    title: "Your month, wrapped",
                    blurb: "When the calendar flips, see your miles, your best day, and a card worth sharing.",
                    tint: .green
                ),
                WhatsNewFeature(
                    icon: "hand.tap",
                    title: "Start from your widget",
                    blurb: "Tap the streak widget and you're already in the tracker.",
                    tint: .purple
                ),
            ]
        ),
        WhatsNewRelease(
            id: 1,
            versionLabel: "July 2026 Update",
            headline: "Your streak just got backup",
            features: [
                WhatsNewFeature(
                    icon: "flame.fill",
                    title: "Streak Tokens",
                    blurb: "Earn Double Down, Streak Save, and Streak Assist by running — and use them to protect your streak when life happens.",
                    tint: .orange
                ),
                WhatsNewFeature(
                    icon: "lifepreserver",
                    title: "Save a friend's streak",
                    blurb: "Go 20 miles past your goal to earn an Assist, then rescue a friend the day after their streak breaks.",
                    tint: MADTheme.Colors.madRed
                ),
                WhatsNewFeature(
                    icon: "checkmark.seal.fill",
                    title: "The Pure Flame",
                    blurb: "A gold flame on your profile when every day of your streak was earned on the day.",
                    tint: Color(red: 1.0, green: 0.84, blue: 0.35)
                ),
                WhatsNewFeature(
                    icon: "text.bubble.fill",
                    title: "Comments & collabs",
                    blurb: "Comment on friends' posts and share a run together as a collab.",
                    tint: MADTheme.Colors.walkBlue
                ),
                WhatsNewFeature(
                    icon: "calendar",
                    title: "Your workouts, organized",
                    blurb: "A calendar of every run, swipe between workouts, and photos that load instantly.",
                    tint: .green
                ),
                WhatsNewFeature(
                    icon: "hand.thumbsup.fill",
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
/// reopens anytime from Dashboard settings (under App Tour). Flat, calm,
/// icon-driven — same design language as the redesigned dashboard.
struct WhatsNewView: View {
    var release: WhatsNewRelease = WhatsNewCatalog.latest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        header
                        VStack(spacing: 10) {
                            ForEach(Array(release.features.enumerated()), id: \.element.id) { index, feature in
                                featureRow(feature)
                                    .opacity(revealed ? 1 : 0)
                                    .offset(y: revealed ? 0 : 14)
                                    .animation(
                                        reduceMotion
                                            ? .default
                                            : .spring(response: 0.5, dampingFraction: 0.8)
                                                .delay(0.15 + Double(index) * 0.06),
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
        .presentationDragIndicator(.visible)
        .onAppear {
            revealed = true
            // Opening the sheet counts as seeing the release, however it closes
            // (swipe-down included) — never nag someone twice.
            WhatsNewManager.markSeen()
        }
    }

    /// Left-aligned editorial header — version eyebrow, big title, one-line
    /// headline. No floating logo circle, no ornament.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(release.versionLabel.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundColor(MADTheme.Colors.madRed)

            Text("What's New")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            Text(release.headline)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(feature.tint)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(feature.tint.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(feature.blurb)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}
