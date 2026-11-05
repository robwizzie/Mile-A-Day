import SwiftUI

struct EditWorkoutView: View {
    let workoutId: String
    let currentDistance: Double
    let currentDuration: TimeInterval
    let currentWorkoutType: String
    /// What the device measured before any edit — what `WorkoutEditPolicy`
    /// judges against, so a correction can't be stacked one save at a time.
    /// Nil falls back to the current figures (older callers).
    var recordedDistance: Double? = nil
    var recordedDuration: TimeInterval? = nil
    /// Treadmill / indoor: far more room for distance corrections.
    var isIndoor: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var healthManager: HealthKitManager
    @StateObject private var workoutService = WorkoutService()

    @State private var distanceString: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 0
    @State private var workoutType: String = "running"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDiscardConfirmation = false
    @State private var showManualFlagConfirmation = false
    @FocusState private var distanceFieldFocused: Bool

    private var distance: Double? {
        Double(distanceString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var totalDuration: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    private var hasChanges: Bool {
        distanceChanged || durationChanged || typeChanged
    }

    /// Flagged "Edited" under the old rules, which flagged ANY time or type
    /// change. Saving re-judges it under `WorkoutEditPolicy`, so Save stays
    /// enabled even with nothing changed — that's how an old badge comes off.
    private var carriesOldEditFlag: Bool {
        ManualWorkoutRegistry.sourceFor(workoutId) == .edited
    }

    private var canSave: Bool {
        isValid && (hasChanges || carriesOldEditFlag) && !isSaving
    }

    private var isValid: Bool {
        guard let d = distance, d > 0, d < 100 else { return false }
        return totalDuration > 0
    }

    private var distanceChanged: Bool {
        guard let d = distance else { return false }
        return abs(d - currentDistance) > 0.001
    }

    private var durationChanged: Bool {
        abs(totalDuration - currentDuration) > 1
    }

    private var typeChanged: Bool {
        workoutType != currentWorkoutType
    }

    private var flagReason: WorkoutEditPolicy.Reason? {
        guard let d = distance else { return nil }
        return WorkoutEditPolicy.flagReason(
            recordedDistance: recordedDistance ?? currentDistance,
            recordedDuration: recordedDuration ?? currentDuration,
            newDistance: d,
            newDuration: totalDuration,
            isIndoor: isIndoor
        )
    }

    private var editSource: WorkoutSource {
        flagReason == nil ? .healthkit : .manual
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
                            .focused($distanceFieldFocused)
                        Text("miles")
                            .foregroundColor(.secondary)
                    }
                    if (recordedDistance ?? currentDistance) > 0 {
                        Text("Recorded: \(String(format: "%.2f", recordedDistance ?? currentDistance)) mi")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Distance")
                }

                // Duration
                Section {
                    HStack(spacing: 0) {
                        durationPicker(value: $hours, label: "hr", range: 0...23)
                        durationPicker(value: $minutes, label: "min", range: 0...59)
                        durationPicker(value: $seconds, label: "sec", range: 0...59)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    let origMin = Int(recordedDuration ?? currentDuration) / 60
                    let origSec = Int(recordedDuration ?? currentDuration) % 60
                    Text("Recorded: \(origMin)m \(origSec)s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Duration")
                }

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: editSource == .manual ? "exclamationmark.triangle.fill" : "pencil.circle.fill")
                            .foregroundColor(.orange)
                        Text(editWarningText)
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
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelTapped() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        distanceFieldFocused = false
                        saveTapped()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
                // The decimal pad has no return key — without this there is no
                // way to put the keyboard away except dragging the form, which
                // is the same gesture that dismisses the sheet.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { distanceFieldFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                distanceString = String(format: "%.2f", currentDistance)
                workoutType = currentWorkoutType
                let dur = Int(currentDuration)
                hours = dur / 3600
                minutes = (dur % 3600) / 60
                seconds = dur % 60
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
        // An edit sheet holds work the user can't get back. Explicit Cancel
        // still leaves; the post-save dismiss is programmatic and unaffected.
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            "Discard your changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        }
        .alert("Mark as manual?", isPresented: $showManualFlagConfirmation) {
            Button("Save as Manual", role: .destructive) {
                Task { await saveEdit(source: .manual) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(WorkoutEditPolicy.explanation(for: flagReason ?? .distance))
        }
    }

    private var editWarningText: String {
        if let flagReason {
            return WorkoutEditPolicy.explanation(for: flagReason)
        }
        return isIndoor
            ? "Treadmill corrections to distance, time or type aren't flagged. Only a change far beyond what was recorded shows as manual."
            : "Corrections to distance, time or type aren't flagged. Only a change far beyond what was recorded shows as manual."
    }

    private func cancelTapped() {
        distanceFieldFocused = false
        if hasChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    /// Each wheel takes an equal share of the row. The old fixed 60pt wheels
    /// with the label beside them left wide dead gaps where a drag meant for a
    /// wheel scrolled the form instead. Values are zero-padded to match the Add
    /// Workout screen — "5" and "05" reading as different units was its own
    /// small confusion.
    private func durationPicker(value: Binding<Int>, label: String, range: ClosedRange<Int>) -> some View {
        VStack(spacing: 2) {
            Picker(label, selection: value) {
                ForEach(range, id: \.self) { n in
                    Text(String(format: "%02d", n)).tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func saveTapped() {
        if editSource == .manual {
            showManualFlagConfirmation = true
        } else {
            Task { await saveEdit(source: editSource) }
        }
    }

    private func saveEdit(source: WorkoutSource) async {
        guard let distance = distance else { return }

        isSaving = true
        errorMessage = nil

        do {
            let _ = try await workoutService.updateWorkout(
                workoutId: workoutId,
                distance: distance,
                totalDuration: totalDuration,
                workoutType: workoutType,
                source: source
            )

            switch source {
            case .manual:
                ManualWorkoutRegistry.markManual(workoutId)
            case .edited:
                ManualWorkoutRegistry.markEdited(workoutId)
            case .healthkit:
                ManualWorkoutRegistry.markHealthKit(workoutId)
            }

            // A deliberate edit outranks the tracker's receipt — without this,
            // `madDistanceMiles` would floor the display back to the tracked
            // value and the edit would silently never take on any local screen.
            TrackedWorkoutLedger.shared.userOverride(workoutId: workoutId, miles: distance)
            // Same for the time. HealthKit can't be rewritten, and every screen
            // used to read `HKWorkout.duration` directly — the server took the
            // edit while the phone kept showing (and re-offering) the old time.
            if durationChanged || TrackedWorkoutLedger.shared.userDuration(forWorkoutId: workoutId) != nil {
                TrackedWorkoutLedger.shared.userOverrideDuration(workoutId: workoutId, seconds: totalDuration)
            }

            // Force full index rebuild to pick up the source change
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
