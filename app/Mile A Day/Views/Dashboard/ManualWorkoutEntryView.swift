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
    @State private var isDistanceFocused = false
    @FocusState private var distanceFieldFocused: Bool

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

    /// Computed pace in min/mi
    private var paceString: String? {
        guard let d = distance, d > 0, totalDuration > 0 else { return nil }
        let paceSeconds = totalDuration / d
        let mins = Int(paceSeconds) / 60
        let secs = Int(paceSeconds) % 60
        return String(format: "%d:%02d /mi", mins, secs)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background matching app theme
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                if showSuccess {
                    successOverlay
                } else {
                    mainContent
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveWorkout() }
                    } label: {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Workout Type Selector
                workoutTypeSection

                // Distance Input
                distanceSection

                // Duration Picker
                durationSection

                // Pace Display (computed)
                if let pace = paceString {
                    paceSection(pace: pace)
                }

                // Date Picker
                dateSection

                // Manual workout info
                infoSection

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(MADTheme.Colors.error)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MADTheme.Colors.error.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium))
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if isSaving {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                            Text("Saving workout...")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large))
                    }
            }
        }
    }

    // MARK: - Workout Type

    private var workoutTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WORKOUT TYPE")

            HStack(spacing: 12) {
                workoutTypeCard(
                    type: "running",
                    icon: "figure.run",
                    label: "Run"
                )
                workoutTypeCard(
                    type: "walking",
                    icon: "figure.walk",
                    label: "Walk"
                )
            }
            .padding(.horizontal)
        }
    }

    private func workoutTypeCard(type: String, icon: String, label: String) -> some View {
        let isSelected = workoutType == type
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                workoutType = type
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(isSelected ? MADTheme.Colors.redGradient : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                    )

                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .strokeBorder(isSelected ? MADTheme.Colors.primary.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Distance

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DISTANCE")

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0.00", text: $distanceString)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .focused($distanceFieldFocused)

                Text("mi")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .strokeBorder(
                                distanceFieldFocused ? MADTheme.Colors.primary.opacity(0.5) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
            .padding(.horizontal)
            .onTapGesture {
                distanceFieldFocused = true
            }
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DURATION")

            HStack(spacing: 0) {
                durationWheel(value: $hours, label: "hr", range: 0...23)

                Text(":")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(y: -2)

                durationWheel(value: $minutes, label: "min", range: 0...59)

                Text(":")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(y: -2)

                durationWheel(value: $seconds, label: "sec", range: 0...59)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
        }
    }

    private func durationWheel(value: Binding<Int>, label: String, range: ClosedRange<Int>) -> some View {
        VStack(spacing: 2) {
            Picker(label, selection: value) {
                ForEach(range, id: \.self) { n in
                    Text(String(format: "%02d", n))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 70, height: 120)
            .clipped()

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
        }
    }

    // MARK: - Pace

    private func paceSection(pace: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "speedometer")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(MADTheme.Colors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Avg Pace")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .textCase(.uppercase)
                Text(pace)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeOut(duration: 0.3), value: paceString)
    }

    // MARK: - Date

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DATE & TIME")

            DatePicker(
                "When",
                selection: $workoutDate,
                in: thirtyDaysAgo...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(MADTheme.Colors.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange.opacity(0.8))

            Text("Manual workouts are flagged so friends can see they were hand-entered.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: workoutType == "running" ? "figure.run" : "figure.walk")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(MADTheme.Colors.redGradient)

            Text("Workout Saved!")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if let d = distance {
                Text(String(format: "%.2f mi", d))
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 20)
    }

    // MARK: - Save

    private func saveWorkout() async {
        guard let distance = distance else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await workoutService.uploadManualWorkout(
                distance: distance,
                duration: totalDuration,
                date: workoutDate,
                workoutType: workoutType
            )

            let hkType: HKWorkoutActivityType = workoutType == "running" ? .running : .walking
            await workoutService.writeManualWorkoutToHealthKit(
                distance: distance,
                duration: totalDuration,
                date: workoutDate,
                workoutType: hkType
            )

            WorkoutIndex.clear()
            healthManager.workoutIndex = nil
            #if !os(watchOS)
            healthManager.isIndexBuilding = false
            #endif
            healthManager.fetchAllWorkoutData()

            isSaving = false

            // Show success animation briefly before dismissing
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showSuccess = true
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}
