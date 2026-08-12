import SwiftUI
import UIKit

// MARK: - Workout Recap View

/// Post-workout summary shown inside WorkoutTrackingView's full-screen cover,
/// over its red gradient background. Every metric is a snapshot captured when
/// the workout ended — the live managers keep refreshing underneath while
/// HealthKit re-syncs, so reading them here would drift or double-count.
struct WorkoutRecapView: View {
    let distance: Double          // Miles covered in this workout
    let duration: TimeInterval    // Seconds elapsed in this workout
    let activityName: String      // "Run" or "Walk"
    let activityIcon: String      // SF Symbol for the activity
    let startingDistance: Double  // Miles already done today before this workout
    let goalDistance: Double      // Daily goal in miles
    let streak: Int               // Current streak in days
    let healthManager: HealthKitManager
    var workoutId: String? = nil
    var isIndoor: Bool = false
    /// Quarter-by-quarter against the ghost, empty when this wasn't a race.
    /// Defaulted so every existing construction site is unaffected.
    var raceSplits: [BestEffortStore.RaceSplit] = []
    var raceGhostName: String = "your ghost"
    var onDistanceAdjusted: ((Double) -> Void)? = nil
    let onDismiss: () -> Void

    @State private var treadmillBaselineDistance: Double?

    // Staggered entrance
    @State private var showHero = false
    @State private var showDistance = false
    @State private var showStats = false
    @State private var showGoal = false

    private var totalDailyDistance: Double { startingDistance + distance }

    private var goalMet: Bool {
        goalDistance > 0 && totalDailyDistance >= goalDistance
    }

    private var goalProgress: Double {
        guard goalDistance > 0 else { return 0 }
        return min(totalDailyDistance / goalDistance, 1.0)
    }

    /// What's left, rounded UP to the hundredth — the counterpart of the
    /// floored distance displays: never promise the goal is closer than it
    /// is. (The epsilon absorbs float error so an exact 0.01 can't ceil to
    /// 0.02.)
    private var milesRemaining: Double {
        let raw = max(goalDistance - totalDailyDistance, 0)
        return (raw * 100.0 - 1e-6).rounded(.up) / 100.0
    }

    private var formattedTime: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedPace: String {
        guard distance > 0.01 else { return "--" }
        let paceSeconds = duration / distance
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    /// Where the race was won or lost.
    ///
    /// The live chip could only ever show the running total, so "I was down at
    /// halfway and took it in the last quarter" — the actual shape of the race
    /// — was never visible anywhere. Four rows, your split against the ghost's,
    /// with the quarter you gained tinted green and the one you gave away
    /// orange.
    @ViewBuilder
    private var raceBreakdown: some View {
        if !raceSplits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 12, weight: .bold))
                    Text("VS \(raceGhostName.uppercased())")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(0.8)
                }
                .foregroundColor(.white.opacity(0.6))

                ForEach(raceSplits) { split in
                    HStack(spacing: 12) {
                        Text(split.label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 26, alignment: .leading)

                        Text(BestEffortStore.formatSeconds(split.yours))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)

                        Text(BestEffortStore.formatSeconds(split.ghost))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.45))

                        Spacer()

                        Text(deltaText(split.delta))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(split.delta >= 0 ? .green : .orange)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }

    /// "+3s" / "−2s" — seconds gained on the ghost in that quarter.
    private func deltaText(_ delta: TimeInterval) -> String {
        let whole = Int(delta.rounded())
        if whole == 0 { return "even" }
        return whole > 0 ? "+\(whole)s" : "\(whole)s"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                        .padding(.top, 32)

                    distanceSection

                    statsGrid

                    if isIndoor, let workoutId {
                        TreadmillDistanceAdjustmentCard(
                            workoutId: workoutId,
                            recordedDistance: treadmillBaselineDistance ?? distance,
                            currentDistance: distance,
                            duration: duration,
                            workoutType: activityName == "Run" ? "running" : "walking",
                            healthManager: healthManager,
                            onSaved: onDistanceAdjusted
                        )
                    }

                    raceBreakdown

                    goalCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            doneButton
        }
        .onAppear {
            if treadmillBaselineDistance == nil {
                treadmillBaselineDistance = distance
            }
            MADHaptics.success()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { showHero = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.2)) { showDistance = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.35)) { showStats = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) { showGoal = true }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 116, height: 116)

                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 116, height: 116)

                if goalMet {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    Image(systemName: activityIcon)
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(showHero ? 1.0 : 0.4)
            .opacity(showHero ? 1 : 0)

            VStack(spacing: 6) {
                Text(goalMet ? "Goal Complete!" : "Great Work!")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("\(activityName) saved to Apple Health")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
            }
            .opacity(showHero ? 1 : 0)
            .offset(y: showHero ? 0 : 12)
        }
    }

    // MARK: - Distance

    private var distanceSection: some View {
        VStack(spacing: 4) {
            Text(distance.milesText)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("MILES THIS \(activityName.uppercased())")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
                .tracking(1.5)
        }
        .opacity(showDistance ? 1 : 0)
        .offset(y: showDistance ? 0 : 12)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            RecapStatCell(icon: "clock.fill", label: "Time", value: formattedTime)
            RecapStatCell(icon: "speedometer", label: "Avg Pace", value: "\(formattedPace) /mi")
            RecapStatCell(icon: activityIcon, label: "Activity", value: activityName)
            RecapStatCell(icon: "chart.bar.fill", label: "Daily Total", value: totalDailyDistance.milesFormatted)
        }
        .opacity(showStats ? 1 : 0)
        .offset(y: showStats ? 0 : 12)
    }

    // MARK: - Goal Progress

    private var goalCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "target")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text("Daily Goal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Floored: "1.00 / 1.00" must never appear while goalMet is
                // still false (0.995 used to render exactly that).
                Text("\(totalDailyDistance.milesText) / \(goalDistance.milesText) mi")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: goalMet ? [.green, .mint] : [.orange, .yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        // Bar fills from zero as part of the entrance animation
                        .frame(width: showGoal ? max(geo.size.width * goalProgress, goalProgress > 0 ? 10 : 0) : 0)
                }
            }
            .frame(height: 10)

            HStack(spacing: 6) {
                if goalMet {
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text(streak > 0 ? "\(streak)-day streak is safe for today" : "Your streak is safe for today")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                } else {
                    Image(systemName: "figure.walk.motion")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text(String(format: "%.2f mi to go — you've got this", milesRemaining))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .opacity(showGoal ? 1 : 0)
        .offset(y: showGoal ? 0 : 12)
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text("Back to Dashboard")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 217/255, green: 64/255, blue: 63/255),
                                    Color(red: 180/255, green: 50/255, blue: 50/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 40)
        .buttonStyle(PlainButtonStyle())
    }
}

private struct TreadmillDistanceAdjustmentCard: View {
    let workoutId: String
    let recordedDistance: Double
    let currentDistance: Double
    let duration: TimeInterval
    let workoutType: String
    let healthManager: HealthKitManager
    var onSaved: ((Double) -> Void)?

    @StateObject private var workoutService = WorkoutService()
    @State private var distanceString = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showManualFlagConfirmation = false
    @State private var showEditSheet = false
    @FocusState private var distanceFieldFocused: Bool

    private var enteredDistance: Double? {
        Double(distanceString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var addsMoreThan25Percent: Bool {
        guard recordedDistance > 0, let enteredDistance else { return false }
        return enteredDistance > recordedDistance * 1.25
    }

    private var canSave: Bool {
        guard let enteredDistance, enteredDistance > 0, enteredDistance < 100 else { return false }
        return abs(enteredDistance - currentDistance) > 0.001 && !isSaving
    }

    private var formattedTime: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Treadmill Distance", systemImage: "figure.walk.motion")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Text("\(currentDistance.milesText) mi")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                TextField("0.00", text: $distanceString)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .focused($distanceFieldFocused)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )

                Text("mi")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))

                Button {
                    distanceFieldFocused = false
                    saveTapped()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(canSave ? Color.green.opacity(0.9) : Color.white.opacity(0.14))
                )
                .foregroundColor(.white)
                .disabled(!canSave)
            }

            HStack {
                Label(formattedTime, systemImage: "clock.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .monospacedDigit()

                Spacer()

                Button("Edit") {
                    distanceFieldFocused = false
                    showEditSheet = true
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            }

            if addsMoreThan25Percent {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Adding more than 25% will mark this workout as manually entered.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.orange)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .onAppear {
            if distanceString.isEmpty {
                distanceString = String(format: "%.2f", currentDistance)
            }
        }
        .alert("Mark as manual?", isPresented: $showManualFlagConfirmation) {
            Button("Save as Manual", role: .destructive) {
                Task { await saveDistance(source: .manual) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This treadmill distance adds more than 25% to the recorded workout, so it will be visible as a manual entry.")
        }
        .sheet(isPresented: $showEditSheet) {
            EditWorkoutView(
                workoutId: workoutId,
                currentDistance: currentDistance,
                currentDuration: duration,
                currentWorkoutType: workoutType
            )
            .environmentObject(healthManager)
        }
    }

    private func saveTapped() {
        if addsMoreThan25Percent {
            showManualFlagConfirmation = true
        } else {
            Task { await saveDistance(source: .healthkit) }
        }
    }

    private func saveDistance(source: WorkoutSource) async {
        guard let enteredDistance else { return }
        isSaving = true
        errorMessage = nil

        do {
            _ = try await workoutService.updateWorkout(
                workoutId: workoutId,
                distance: enteredDistance,
                totalDuration: nil,
                workoutType: nil,
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
            TrackedWorkoutLedger.shared.userOverride(workoutId: workoutId, miles: enteredDistance)
            WorkoutIndex.clear()
            healthManager.workoutIndex = nil
            healthManager.isIndexBuilding = false
            healthManager.fetchAllWorkoutData()
            onSaved?(enteredDistance)
            isSaving = false
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Recap Stat Cell

private struct RecapStatCell: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1)
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
