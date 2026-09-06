import SwiftUI

// MARK: - Goal Setting Sheet with Version Info

struct GoalSettingSheet: View {
    let currentGoal: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newGoalMiles: Double = 1.0

    // Version information from bundle
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var versionString: String {
        "v\(appVersion) (\(buildNumber))"
    }

    private var unit: DisplayDistanceUnit { DistanceUnits.current }

    /// The stepper's number in the display unit, written back as miles.
    private var displayGoal: Binding<Double> {
        Binding(
            get: { newGoalMiles.inDisplayUnit },
            set: { newGoalMiles = $0 / DistanceUnits.current.perMile }
        )
    }

    // Exact race distances in miles, so a km user reads "5.00 km" and a
    // miles user "3.10 mi" for the same goal.
    static let oneMile = 1.0
    static let fiveK = 5.0 / 1.609344
    static let tenK = 10.0 / 1.609344

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Goal") {
                    // The goal is stored in miles; the stepper walks it in
                    // whatever the user reads (0.1 km steps for a km user).
                    Stepper(value: displayGoal, in: 0.1...(26.2 * unit.perMile), step: 0.1) {
                        HStack {
                            Text("\(unit.title):")
                            Text(newGoalMiles.distanceFormatted)
                                .fontWeight(.bold)
                        }
                    }
                }

                Section("Common Goals") {
                    Button("1 mile (\(Self.oneMile.distanceFormatted))") { newGoalMiles = Self.oneMile }
                    Button("5K (\(Self.fiveK.distanceFormatted))") { newGoalMiles = Self.fiveK }
                    Button("10K (\(Self.tenK.distanceFormatted))") { newGoalMiles = Self.tenK }
                }

                Section("App Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Build Date")
                        Spacer()
                        Text(getBuildDate())
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(newGoalMiles)
                        dismiss()
                    }
                }
            }
            .onAppear {
                newGoalMiles = currentGoal
            }
        }
    }

    private func getBuildDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let infoAttrs = try? FileManager.default.attributesOfItem(atPath: infoPath),
           let infoDate = infoAttrs[.modificationDate] as? Date {
            return formatter.string(from: infoDate)
        }

        return formatter.string(from: Date())
    }
}
