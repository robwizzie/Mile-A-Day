import SwiftUI

/// FAQ, contact, and the legal pages.
///
/// The tour and the version used to appear here AND on the Settings page; each
/// now has one place there (Help → Take the tour, and the footer).
struct HelpAndSupportView: View {
    @State private var legalURL: URL?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    SettingsSection("Questions") {
                        faqItem(
                            question: "How does streak tracking work?",
                            answer: "Your streak counts consecutive days where you've done a mile or walked 10,000 steps — either one counts for the day. Missing a day resets your streak to zero. Workouts from Apple Fitness or any compatible app, and steps from Apple Health, sync automatically via HealthKit."
                        )
                        SettingsDivider(inset: 0)
                        faqItem(
                            question: "How do I sync my workouts?",
                            answer: "Workouts sync automatically from Apple Health, as long as Mile A Day has access. Check it in Settings → Health access. Workouts from Apple Watch, Apple Fitness and other apps that write to Apple Health appear on their own."
                        )
                        SettingsDivider(inset: 0)
                        faqItem(
                            question: "How do I add friends?",
                            answer: "Go to the Friends tab and tap the search icon. You can search for other users by username. Send a friend request and once they accept, you'll be able to see each other's stats and compete together."
                        )
                        SettingsDivider(inset: 0)
                        faqItem(
                            question: "What are badges and how do I earn them?",
                            answer: "Badges are achievements you earn by hitting milestones — streak counts, total miles, pace records, and more. Check your profile to see all your earned badges."
                        )
                        SettingsDivider(inset: 0)
                        faqItem(
                            question: "How does the step goal work?",
                            answer: "The step goal tracks your daily steps from Apple Health with a target of 10,000 steps. Reaching it completes your day for the streak, just like a mile does — so a busy day on your feet keeps your streak alive. The calendar view shows your step progress for each day with color-coded indicators."
                        )
                    }

                    SettingsSection("Referrals") {
                        NavigationLink(destination: ReferralsView()) {
                            SettingsRow(
                                icon: "gift.fill",
                                title: "Invite friends and rewards",
                                subtitle: "How referrals work and your progress",
                                tint: MADTheme.Colors.madRed
                            )
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                        if let url = ReferralService.supportURL(username: UserManager.shared.currentUser.username) {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                SettingsRow(
                                    icon: "person.crop.circle.badge.exclamationmark",
                                    title: "Referral not connected?",
                                    subtitle: "Email us and we'll fix it",
                                    tint: .orange,
                                    accessory: .external
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SettingsSection("Contact", footer: "A question, or found a bug? We'd love to hear from you.") {
                        Button {
                            if let url = URL(string: "mailto:support@mileaday.run?subject=Mile%20A%20Day%20Support%20-%20v\(appVersion)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            SettingsRow(
                                icon: "envelope.fill",
                                title: "Email support",
                                subtitle: "support@mileaday.run",
                                tint: MADTheme.Colors.madRed,
                                accessory: .external
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Reachable outside the Plus screen too (5.1.1: the privacy
                    // policy must be easy to find in the app).
                    SettingsSection("Legal") {
                        Button { legalURL = PlusLinks.privacy } label: {
                            SettingsRow(icon: "hand.raised.fill", title: "Privacy policy", tint: .secondary)
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                        Button { legalURL = PlusLinks.terms } label: {
                            SettingsRow(icon: "doc.text", title: "Terms of use", tint: .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $legalURL) { url in
            SafariWebView(url: url)
                .ignoresSafeArea()
        }
    }

    private func faqItem(question: String, answer: String) -> some View {
        DisclosureGroup {
            Text(answer)
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MADTheme.Spacing.sm)
        } label: {
            Text(question)
                .font(MADTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
        .tint(.secondary)
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        HelpAndSupportView()
    }
}
