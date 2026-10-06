import SwiftUI
import HealthKit

/// Your newest few workouts, on your own profile directly under the week
/// chart. Every part of it opens the full history — `WorkoutsView`, the same
/// calendar / list / trends / routes screen the Dashboard's Recent Workouts
/// card pushes — so it is a doorway to that history, not a second copy of it.
struct OwnRecentWorkoutsCard: View {
    @ObservedObject var healthManager: HealthKitManager
    let onOpenHistory: () -> Void

    /// Long lists on a profile cap at three and say "See all".
    private static let previewCount = 3

    private var preview: [HKWorkout] {
        Array(healthManager.recentWorkouts.prefix(Self.previewCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            header
            content
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
    }

    private var header: some View {
        Button(action: onOpenHistory) {
            HStack {
                ProfileCardLabel(text: "WORKOUTS")
                Spacer()
                HStack(spacing: 3) {
                    Text("See all")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundColor(MADTheme.Colors.madRed)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workouts, see all")
    }

    @ViewBuilder
    private var content: some View {
        if preview.isEmpty {
            if healthManager.hasLoadedRecentWorkoutsOnce {
                // A successful query genuinely returned nothing.
                Text("No workouts yet. Your walks and runs will show up here.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            } else {
                // Not loaded yet (or a locked-device query is still retrying):
                // never the "no workouts" line, which reads as history lost.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading workouts…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        } else {
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(preview, id: \.uuid) { workout in
                    Button(action: onOpenHistory) {
                        WorkoutRow(workout: workout, showDate: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }
}
