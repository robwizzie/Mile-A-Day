import SwiftUI

/// Lightweight settings page pushed from the Dashboard header's gear icon.
/// Gives quick access to the daily goal, app tour, and other dashboard-level
/// preferences without leaving the Dashboard tab.
struct DashboardSettingsView: View {
    @ObservedObject var userManager: UserManager
    let currentGoal: Double
    let onSetGoal: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Reopenable What's New — lives here next to the App Tour so both
    /// "show me around" surfaces share one home.
    @State private var showWhatsNew = false
    @AppStorage(DashboardStylePreference.key) private var dashboardStyleRaw = DashboardStyle.modern.rawValue

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

            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                MADSettingsRow(
                    icon: "paintbrush.pointed.fill",
                    title: "Dashboard Style",
                    subtitle: selectedStyle.subtitle,
                    iconColor: .orange
                )

                Picker("Dashboard Style", selection: $dashboardStyleRaw) {
                    ForEach(DashboardStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: dashboardStyleRaw) { _, newValue in
                    DashboardStylePreference.current = DashboardStyle(rawValue: newValue) ?? .modern
                    DashboardStylePreference.markChosen()
                    MADHaptics.tap()
                }
            }
            .padding(.bottom, MADTheme.Spacing.xs)

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

            settingsDivider

            Button {
                showWhatsNew = true
            } label: {
                MADSettingsRow(
                    icon: "sparkles",
                    title: "What's New",
                    subtitle: "See what changed in the latest update",
                    iconColor: .orange
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView()
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.06))
            .padding(.vertical, MADTheme.Spacing.xs)
    }

    private var selectedStyle: DashboardStyle {
        DashboardStyle(rawValue: dashboardStyleRaw) ?? .modern
    }
}
