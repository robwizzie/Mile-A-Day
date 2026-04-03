import SwiftUI

struct HelpAndSupportView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // FAQ Section
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MADTheme.Colors.redGradient)
                            Text("Frequently Asked Questions")
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.primary)
                        }

                        faqItem(
                            question: "How does streak tracking work?",
                            answer: "Your streak counts consecutive days where you've completed at least your daily mile goal. Missing a day resets your streak to zero. Make sure to log your workout through Apple Fitness or any compatible app — it syncs automatically via HealthKit."
                        )

                        faqItem(
                            question: "How do I sync my workouts?",
                            answer: "Workouts are automatically synced from Apple Health. Make sure you've granted Mile A Day access to your health data. Go to Settings > Health Data to manage permissions. Workouts from Apple Watch, Apple Fitness, and other HealthKit-compatible apps will appear automatically."
                        )

                        faqItem(
                            question: "How do I add friends?",
                            answer: "Go to the Friends tab and tap the search icon. You can search for other users by username. Send a friend request and once they accept, you'll be able to see each other's stats and compete together."
                        )

                        faqItem(
                            question: "What are badges and how do I earn them?",
                            answer: "Badges are achievements you earn by hitting milestones — streak counts, total miles, pace records, and more. Some badges are hidden and unlock when you discover them! Check your profile to see all your earned badges."
                        )

                        faqItem(
                            question: "How does the step goal work?",
                            answer: "The step goal tracks your daily steps from Apple Health with a target of 10,000 steps. The calendar view shows your step progress for each day with color-coded indicators. This is separate from your mile streak goal."
                        )
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()

                    // Contact Section
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MADTheme.Colors.redGradient)
                            Text("Contact Support")
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.primary)
                        }

                        Text("Have a question or found a bug? We'd love to hear from you.")
                            .font(MADTheme.Typography.body)
                            .foregroundColor(.secondary)

                        Button {
                            if let url = URL(string: "mailto:support@mileaday.app?subject=Mile%20A%20Day%20Support%20-%20v\(appVersion)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Send Email")
                                    .font(MADTheme.Typography.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MADTheme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .fill(MADTheme.Colors.redGradient)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()

                    // App Info
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text("Mile A Day")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.primary)

                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(MADTheme.Spacing.lg)
                    .madLiquidGlass()
                }
                .padding(MADTheme.Spacing.md)
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func faqItem(question: String, answer: String) -> some View {
        DisclosureGroup {
            Text(answer)
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)
                .padding(.top, MADTheme.Spacing.sm)
        } label: {
            Text(question)
                .font(MADTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .tint(MADTheme.Colors.madRed)
    }
}

#Preview {
    NavigationStack {
        HelpAndSupportView()
    }
}
