import SwiftUI

struct AppSettingsView: View {
    @State private var appPrefs = AppPreferences.load()
    @ObservedObject var healthManager: HealthKitManager

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Timezone Settings
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        Text("TIMEZONE SETTINGS")
                            .font(MADTheme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        Toggle("Use Location-Based Timezone", isOn: $appPrefs.useLocationBasedTimezone)
                            .font(MADTheme.Typography.body)
                            .tint(MADTheme.Colors.madRed)
                            .onChange(of: appPrefs.useLocationBasedTimezone) { _, newValue in
                                healthManager.useLocationBasedTimezone = newValue
                                healthManager.recalculateStreakWithCurrentSettings()
                            }

                        Text("When enabled, streaks are calculated based on the timezone where workouts occurred. This prevents streak loss when traveling across timezones.")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()

                    // Debug Section (conditional)
                    if appPrefs.useLocationBasedTimezone {
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                            Text("DEBUG INFORMATION")
                                .font(MADTheme.Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .tracking(0.5)

                            Toggle("Show Timezone Debug Info", isOn: $appPrefs.showTimezoneDebugInfo)
                                .font(MADTheme.Typography.body)
                                .tint(MADTheme.Colors.madRed)

                            Divider().overlay(Color.white.opacity(0.06))

                            Button {
                                healthManager.debugWorkoutTimezones()
                            } label: {
                                HStack {
                                    Image(systemName: "globe.americas.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Analyze Hawaii Workouts")
                                        .font(MADTheme.Typography.body)
                                }
                                .foregroundColor(MADTheme.Colors.madRed)
                            }

                            if appPrefs.showTimezoneDebugInfo && !healthManager.timezoneDebugInfo.isEmpty {
                                Text(healthManager.timezoneDebugInfo)
                                    .font(MADTheme.Typography.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, MADTheme.Spacing.xs)
                            }
                        }
                        .padding(MADTheme.Spacing.md)
                        .madLiquidGlass()
                    }

                    // Help Section
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MADTheme.Colors.redGradient)
                            Text("Location-Based Timezone")
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.primary)
                        }

                        Text("This feature helps maintain accurate streaks when traveling:")
                            .font(MADTheme.Typography.body)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                            helpBullet("Workouts are grouped by local day where they occurred")
                            helpBullet("Prevents streak loss due to timezone changes")
                            helpBullet("Works best with GPS-enabled workouts")
                            helpBullet("Falls back to device timezone if location unavailable")
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()
                }
                .padding(MADTheme.Spacing.md)
            }
        }
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSettings()
                }
                .foregroundColor(MADTheme.Colors.madRed)
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            appPrefs.useLocationBasedTimezone = healthManager.useLocationBasedTimezone
        }
    }

    private func helpBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
            Circle()
                .fill(MADTheme.Colors.madRed)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
        }
    }

    private func saveSettings() {
        appPrefs.save()
        healthManager.useLocationBasedTimezone = appPrefs.useLocationBasedTimezone
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

#Preview {
    NavigationView {
        AppSettingsView(healthManager: HealthKitManager())
    }
}
