import SwiftUI

struct AppSettingsView: View {
    @State private var appPrefs = AppPreferences.load()
    @ObservedObject var healthManager: HealthKitManager
    
    var body: some View {
        Form {
            Section(header: Text("Timezone Settings")) {
                Toggle("Use Location-Based Timezone", isOn: $appPrefs.useLocationBasedTimezone)
                    .onChange(of: appPrefs.useLocationBasedTimezone) { _, newValue in
                        healthManager.useLocationBasedTimezone = newValue
                        // Recalculate streak with new setting
                        healthManager.recalculateStreakWithCurrentSettings()
                    }
                
                Text("When enabled, streaks are calculated based on the timezone where workouts occurred. This prevents streak loss when traveling across timezones.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            
            if appPrefs.useLocationBasedTimezone {
                Section(header: Text("Debug Information")) {
                    Toggle("Show Timezone Debug Info", isOn: $appPrefs.showTimezoneDebugInfo)
                    
                    Button("Analyze Hawaii Workouts") {
                        healthManager.debugWorkoutTimezones()
                    }
                    .foregroundColor(.blue)
                    
                    if appPrefs.showTimezoneDebugInfo && !healthManager.timezoneDebugInfo.isEmpty {
                        Text(healthManager.timezoneDebugInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            
            Section(header: Text("Help")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location-Based Timezone")
                        .font(.headline)
                    
                    Text("This feature helps maintain accurate streaks when traveling:")
                        .font(.subheadline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Workouts are grouped by local day where they occurred")
                        Text("• Prevents streak loss due to timezone changes")
                        Text("• Works best with GPS-enabled workouts")
                        Text("• Falls back to device timezone if location unavailable")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSettings()
                }
            }
        }
        .onAppear {
            // Sync current health manager setting with preferences
            appPrefs.useLocationBasedTimezone = healthManager.useLocationBasedTimezone
        }
    }
    
    private func saveSettings() {
        appPrefs.save()
        healthManager.useLocationBasedTimezone = appPrefs.useLocationBasedTimezone
        
        // Give user feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

#Preview {
    NavigationView {
        AppSettingsView(healthManager: HealthKitManager())
    }
}
