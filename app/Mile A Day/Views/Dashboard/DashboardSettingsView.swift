import SwiftUI

/// Lightweight settings page pushed from the Dashboard header's gear icon.
/// Gives quick access to the daily goal, app tour, and other dashboard-level
/// preferences without leaving the Dashboard tab.
struct DashboardSettingsView: View {
    @ObservedObject var userManager: UserManager
    let currentGoal: Double
    let onSetGoal: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                settingsCard
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Dashboard Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Button(action: onSetGoal) {
                MADSettingsRow(
                    icon: "target",
                    title: "Daily Goal",
                    subtitle: "\(String(format: "%.1f", currentGoal)) miles per day",
                    iconColor: .green
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                // Pop back to Dashboard first, then start the tour overlay
                // on MainTabView after a beat so the navigation stack settles.
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MAD_StartGuidedTour"),
                        object: nil
                    )
                }
            } label: {
                MADSettingsRow(
                    icon: "map.fill",
                    title: "App Tour",
                    subtitle: "Take a guided walkthrough of the app",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.06))
            .padding(.vertical, MADTheme.Spacing.xs)
    }
}
