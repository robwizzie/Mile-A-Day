import SwiftUI
import HealthKit

struct ManualWorkoutEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var healthManager: HealthKitManager
    @StateObject private var workoutService = WorkoutService()

    @State private var workoutType: String = "running"
    @State private var distanceString: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 0
    @State private var workoutDate: Date = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private var distance: Double? {
        Double(distanceString)
    }

    private var totalDuration: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    private var isValid: Bool {
        guard let d = distance, d > 0, d < 100 else { return false }
        return totalDuration > 0
    }

    private var thirtyDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                // Workout Type
                Section {
                    Picker("Type", selection: $workoutType) {
                        Label("Run", systemImage: "figure.run")
                            .tag("running")
                        Label("Walk", systemImage: "figure.walk")
                            .tag("walking")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Workout Type")
                }

                // Distance
                Section {
                    HStack {
                        TextField("0.00", text: $distanceString)
                            .keyboardType(.decimalPad)
                        Text("miles")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Distance")
                }

                // Duration
                Section {
                    HStack(spacing: 12) {
                        durationPicker(value: $hours, label: "hr", range: 0...23)
                        durationPicker(value: $minutes, label: "min", range: 0...59)
                        durationPicker(value: $seconds, label: "sec", range: 0...59)
                    }
                } header: {
                    Text("Duration")
                }

                // Date
                Section {
                    DatePicker(
                        "Date",
                        selection: $workoutDate,
                        in: thirtyDaysAgo...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("When")
                }

                // Info
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.orange)
                        Text("Manual workouts are flagged so friends can see they were hand-entered.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveWorkout() }
                    }
                    .disabled(!isValid || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Saving...")
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
        }
    }

    private func durationPicker(value: Binding<Int>, label: String, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Picker(label, selection: value) {
                ForEach(range, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 100)
            .clipped()

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func saveWorkout() async {
        guard let distance = distance else { return }

        isSaving = true
        errorMessage = nil

        do {
            // 1. Save to backend first (source of truth)
            try await workoutService.uploadManualWorkout(
                distance: distance,
                duration: totalDuration,
                date: workoutDate,
                workoutType: workoutType
            )

            // 2. Write to HealthKit (fire-and-forget for Apple Health sync)
            let hkType: HKWorkoutActivityType = workoutType == "running" ? .running : .walking
            await workoutService.writeManualWorkoutToHealthKit(
                distance: distance,
                duration: totalDuration,
                date: workoutDate,
                workoutType: hkType
            )

            // 3. Force full index rebuild so the new manual workout is picked up
            WorkoutIndex.clear()
            healthManager.workoutIndex = nil
            #if !os(watchOS)
            healthManager.isIndexBuilding = false
            #endif
            healthManager.fetchAllWorkoutData()

            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}
